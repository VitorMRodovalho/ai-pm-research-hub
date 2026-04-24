# ADR-0023: `sync_operational_role_cache` trigger contract

- Status: Accepted
- Data: 2026-04-25
- Aprovado por: Vitor (PM)
- Autor: Claude (p42 Track F) + Vitor (PM)
- Escopo: Cache reconciliation entre `engagements`/`auth_engagements` e `members.operational_role`

## Contexto

Domain Model V4 (ADR-0004 a 0009, cutover 2026-04-13) fez de `auth_engagements` × `engagement_kind_permissions` a fonte de verdade de autoridade. ADR-0011 consagrou `can()` / `can_by_member()` como gate canônico. Persistiu, porém, uma coluna cache em `members`: `operational_role text`, usada por:

1. **Triggers legados** (B7 em member_status, várias funções de coerção) — checa `operational_role` em vez de consultar engagements.
2. **Views/queries read-only** — filtram membros por `operational_role IN ('manager','deputy_manager',...)`.
3. **83 RPCs SECURITY DEFINER** (ainda em sweep pós-ADR-0011) — auth gates hardcoded sobre `operational_role`.
4. **Invariants A1/A2/A3** (ver `check_schema_invariants()`) — auditam consistência entre cache e engagements authoritative.
5. **Fast-path exception em ADR-0011 Amendment A** — funções que fan-out N stakeholders podem ler `operational_role` em vez de consultar `can_by_member` por recipient (ex: `notify_offboard_cascade`, `detect_orphan_assignees_from_offboards`).

O contrato entre engagements e o cache é implementado por **um único trigger** — `trg_sync_role_cache` em `engagements` — que chama a função `sync_operational_role_cache()`. A falta de ADR formal deixou o contrato implícito: não há doc que obriga atualizações futuras da ladder de priority a manter paridade com invariant A3, nem especifica o comportamento em edge cases (`NULL` person_id, múltiplas engagements concorrentes, alumni/observer override).

Durante a elaboração deste ADR descobrimos um **drift latente**: o mapping de `volunteer × comms_leader` diverge entre trigger e invariant A3:
- `sync_operational_role_cache` → `comms_leader`
- invariant A3 expected_role → `tribe_leader`

Hoje (2026-04-25) nenhuma engagement ativa tem `role = comms_leader`, então o drift não dispara violations. Mas **é uma time-bomb**: o próximo UPDATE criando esse role vai fazer o trigger popular `comms_leader` e a invariant reportar violation.

## Decisão

Formalizar o contrato do `sync_operational_role_cache()` trigger como Source of Truth (SoT) para reconciliação do cache `members.operational_role` a partir de `auth_engagements`. Documentar:

1. **Trigger shape** (quando fire, o que escreve).
2. **Priority ladder** canônica (qual role vence quando múltiplas engagements coexistem).
3. **Invariant parity rule**: toda mudança na ladder DEVE ser replicada em `check_schema_invariants().A3` no mesmo commit.
4. **Edge cases** tratados (NULL person_id, alumni/observer, external_signer).
5. **Backfill / rollback path** para alterações futuras.

Esta formalização cumpre a ADVISORY #1 de Guardian p41 (ver `docs/council/decisions/`). ADR-0011 Amendment A (fast-path exception) passa a ter um contrato estável para citar.

## Contrato

### Trigger

```sql
CREATE TRIGGER trg_sync_role_cache
  AFTER INSERT OR DELETE OR UPDATE ON public.engagements
  FOR EACH ROW EXECUTE FUNCTION public.sync_operational_role_cache();
```

- **Table watched**: `public.engagements` (a tabela raw; a view `auth_engagements` é o que a função consulta).
- **Events**: INSERT + UPDATE + DELETE. FOR EACH ROW.
- **Timing**: AFTER (post-commit in the statement).
- **Security**: `SECURITY DEFINER` — roda com privilégios do owner para poder atualizar `members`.

Motivo do AFTER-trigger sobre a tabela raw: `auth_engagements` é view que deriva de `engagements` + filtros (`is_authoritative`, `status='active'`, etc.), e precisamos reagir a qualquer alteração no raw que possa mudar o resultado da view para aquela person_id.

### Priority ladder (canonical)

Ao disparar, a função recalcula o role para o `person_id` afetado. A lógica é uma CASE expression com cláusulas `WHEN bool_or(...)` na ordem abaixo — a **primeira que matches vence**:

| Ordem | Condição (auth_engagements) | `operational_role` resultante |
|---|---|---|
| 1 | `kind='volunteer' AND role='manager'` | `manager` |
| 2 | `kind='volunteer' AND role='deputy_manager'` | `deputy_manager` |
| 3 | `kind='volunteer' AND role='leader'` | `tribe_leader` |
| 4 | `kind='volunteer' AND role='co_gp'` | `manager` |
| 5 | `kind='volunteer' AND role='comms_leader'` | **`tribe_leader`** (ver drift note abaixo) |
| 6 | `kind='volunteer' AND role IN ('researcher','facilitator','communicator','curator')` | `researcher` |
| 7 | `kind='external_signer'` | `external_signer` |
| 8 | `kind='observer'` | `observer` |
| 9 | `kind='alumni'` | `alumni` |
| 10 | `kind='sponsor'` | `sponsor` |
| 11 | `kind='chapter_board'` | `chapter_liaison` |
| 12 | `kind='candidate'` | `candidate` |
| — | fallback | `guest` |

Somente engagements com `is_authoritative = true` entram no cálculo.

### Filtros implícitos

1. Se o `person_id` do trigger (NEW ou OLD) não tiver member correspondente, trigger retorna sem alterações.
2. Se o role recalculado for igual ao atual (`operational_role IS NOT DISTINCT FROM`), **nenhum UPDATE é feito** (avoid spurious writes/audit noise).
3. Se não existir nenhuma engagement authoritative ativa para a person, role vira `guest` (row exists, mas sem engagement valid).

### Invariants dependents

| Invariant | Descrição | Ligação ao trigger |
|---|---|---|
| `A1_alumni_role_consistency` | alumni → role=alumni | Garantido via ladder clause 9 — mas B7 trigger em `member_status=alumni` também coerce (override). |
| `A2_observer_role_consistency` | observer → role IN (observer,guest,none) | Garantido via ladder clause 8 + fallback guest. |
| `A3_active_role_engagement_derivation` | active member → role = derivação da ladder | Garantido DIRETAMENTE pelo trigger. **ESTE é o invariant que a ladder deve espelhar exatamente.** |

**Rule mandatória (daqui em diante)**: qualquer PR que altere a CASE expression em `sync_operational_role_cache()` **DEVE** atualizar `check_schema_invariants().A3` no mesmo commit. O contrário também é true. Violar essa regra cria drift latente como o `comms_leader` descrito acima.

### Priority ladder amendment rule

Quando um novo `engagement_kind` ou `role` for adicionado:

1. Decidir onde ele entra na ladder (ordem relativa aos existentes).
2. Atualizar `sync_operational_role_cache()` CASE.
3. Atualizar `check_schema_invariants().A3` CASE com a MESMA ordenação e mesmos returns.
4. Adicionar entry em `engagement_kind_permissions` (actions associadas) se for kind/role com autoridade.
5. Smoke: `SELECT check_schema_invariants()` — A3 deve retornar 0 violations.

## Known drift (to reconcile)

### Drift 1 — `comms_leader` mapping divergence

- Função `sync_operational_role_cache`: maps `volunteer × comms_leader` → `comms_leader`
- Invariant A3: expected_role maps same → `tribe_leader`
- Current prod state: 0 active engagements com `role = 'comms_leader'` → drift latente, zero violations observed.

**Decisão (este ADR)**: adotar `tribe_leader` como canonical (A3 está correto; função está errada). Um próximo commit deve fix o função para alinhar.

Rationale: `comms_leader` é sub-tipo de tribe leader (lidera a tribo 1 — Hub de Comunicação). Role canonical é `tribe_leader`. Separar em cache ID próprio quebraria buscas que pedem "todos os tribe leaders".

### Rollback path

Para reverter este ADR: mudar a docstring da função para apontar invariant A3 como SoT (sem alterar código da função). Dado que função e invariant já compartilham ladder (modulo drift), a formalização não introduz constraint operacional novo — somente escreve o contrato que já existia.

## Consequences

### Positivas

1. **Alertas estruturados**: futuros PRs que toquem a ladder passam por checklist expressa em ADR, não em comment de código.
2. **Guardian sem ADVISORY ambíguo**: ADR-0011 Amendment A pode citar este ADR como fundamento do cache que autoriza fast-path.
3. **Drift `comms_leader` documentado**: visibilidade + path to fix.
4. **Testes structured**: qualquer migration que adicione/remova role na ladder pode ter test "function.ladder == invariant.A3 ladder".

### Negativas / custos

1. **Manutenção**: cada mudança em kind/role exige 2 updates coordenados (função + invariant). Pre-existe mas agora é dever documentado.
2. **Sem enforcement automático**: regra "atualize ambos no mesmo commit" depende de autor + reviewer. Futuro: script CI que compara os dois CASE statements.

### Operational cost

Zero cost at decision time. Drift `comms_leader` fix é follow-up separado (cabe em 1 migration de 3 linhas).

## Related

- ADR-0004 — Multi-tenancy posture
- ADR-0007 — Authority as engagement grant (primary SoT)
- ADR-0011 — V4 Auth Pattern (Amendment A references este ADR como fundamento)
- ADR-0012 — Schema consolidation principles (cache cols as coerce-not-reject)
- `check_schema_invariants()` — A1/A2/A3 reconciliation

## Appendix A — Current CASE (2026-04-25)

```sql
CASE
  WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
  WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
  WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'leader')         THEN 'tribe_leader'
  WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
  WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'comms_leader')   THEN 'comms_leader'  -- ⚠ drift: A3 expects 'tribe_leader'
  WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator')) THEN 'researcher'
  WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
  WHEN bool_or(ae.kind = 'observer')      THEN 'observer'
  WHEN bool_or(ae.kind = 'alumni')        THEN 'alumni'
  WHEN bool_or(ae.kind = 'sponsor')       THEN 'sponsor'
  WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
  WHEN bool_or(ae.kind = 'candidate')     THEN 'candidate'
  ELSE 'guest'
END
```

## Appendix B — `engagement_kind_permissions` relationship

`sync_operational_role_cache` NÃO consulta `engagement_kind_permissions` diretamente. Ele só decide o **cache display role**. A autoridade real (o que aquele member pode fazer) sempre passa por `can() → can_by_member() → engagement_kind_permissions`.

Isso permite:
- Cache displays um label humano simples ("tribe_leader") enquanto permissions são granulares (`write`, `write_board`, `manage_member`).
- Mudar permissions sem tocar no cache (e vice-versa).
- Fast-path do Amendment A: se caller já sabe que o cache diz "manager", ele pode skipar can_by_member para um subset pequeno de operações não-authoritative (notificações, alertas, displays).

## Appendix C — Fast-path exception usages (ADR-0011 Amendment A)

Funções que hoje leem `operational_role` em fast-path (não via can_by_member):

- `notify_offboard_cascade` (p41 commit bcd6ade)
- `detect_orphan_assignees_from_offboards` (p41 commit f47e354)
- (futures) stakeholder fan-out, digest builders, leaderboard readers

Todas devem renovar sua suposição a cada ciclo ("o cache ainda reflete a ladder correta?") — garantido por este ADR + invariant A3.

## Appendix D — Coverage audit (2026-04-25)

Audit feita após contract test de parity (Track I, commit `d2e0b86`) para detectar engagement kinds existentes mas não cobertos pela ladder. Risco: pessoa com ONLY uncovered engagement cairia em `ELSE 'guest'` — correto sintaticamente mas semanticamente duvidoso.

### Kinds × Roles observados em prod (is_authoritative=true, 2026-04-25)

**Cobertos explicitamente pela ladder:**
| Kind | Role | Clause | Result | People |
|---|---|---|---|---|
| chapter_board | board_member | 11 | chapter_liaison | 9 |
| chapter_board | liaison | 11 | chapter_liaison | 3 |
| observer | curator | 8 | observer | 1 |
| observer | observer | 8 | observer | 5 |
| observer | reviewer | 8 | observer | 2 |
| sponsor | sponsor | 10 | sponsor | 5 |
| volunteer | co_gp | 4 | manager | 1 |
| volunteer | leader | 3 | tribe_leader | 7 |
| volunteer | manager | 1 | manager | 1 |
| volunteer | researcher | 6 | researcher | 27 |

**Não cobertos (fall to `ELSE 'guest'`):**
| Kind | Role | People |
|---|---|---|
| committee_coordinator | coordinator | 2 |
| committee_coordinator | leader | 1 |
| committee_member | coordinator | 2 |
| committee_member | leader | 1 |
| speaker | co_presenter | 1 |
| speaker | lead_presenter | 1 |
| workgroup_member | coordinator | 2 |
| workgroup_member | leader | 1 |
| workgroup_member | researcher | 6 |

### Finding

**Zero pessoas afetadas em prod** — todas as 17 pessoas com engagement uncovered TAMBÉM têm uma engagement covered (tipicamente `volunteer` kind) que match clause anterior na ladder. Como o cálculo usa `bool_or`, o primeiro clause covered wins. Example verified: 6 members com `workgroup_member/researcher` também têm `volunteer/leader` → cache correto `tribe_leader` (clause 3), não `guest`.

### Policy (deste ADR)

**Latent gaps aceitos** porque:
1. Committee/workgroup/speaker engagements tipicamente são **secondary** no Núcleo (pessoa faz o grueling trabalho na tribo via `volunteer` kind; comittee/workgroup é overlay organizacional).
2. `ELSE 'guest'` é semanticamente neutro — não implica falta de autoridade, só falta de label operational.
3. Autoridade real (permission to write/manage/etc) continua passando por `can_by_member` → `engagement_kind_permissions`, imune à ladder.

**Trigger para reconciliação**: se aparecer alguém com **ONLY** committee/workgroup/speaker engagements (sem volunteer), e essa situação não for intencional, adicionar clause específica na ladder (e em invariant A3 — parity rule obriga).

### Near-future additions expected

Kinds defined em `engagement_kinds` que ainda não geraram dados:
- `ambassador` (embaixador)
- `guest` (convidado)
- `partner_contact` (contato parceiro)
- `study_group_owner` / `study_group_participant`
- `workgroup_coordinator` (defined mas não observed; tem 0 people em `auth_engagements`)

Quando esses kinds entrarem em operação, revisitar este Appendix + possivelmente adicionar clauses.
