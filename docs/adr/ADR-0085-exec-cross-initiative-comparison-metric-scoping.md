# ADR-0085: `exec_cross_initiative_comparison` metric scoping contract

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-05-18 (sessão p195) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migrations | `20260700000000` (V4 introduction, p192) · `20260702000000` (GAP-192.C total_hours strict scope, p194) · `20260703000000` (GAP-194.A members_inactive_30d strict scope, p194) |
| Cross-ref | [ADR-0042](./ADR-0042-view-chapter-dashboards-action.md) (authority gate) · [ADR-0011](./ADR-0011-v4-auth-pattern-rpcs-mcp.md) Batch 1 (V4 reader catalog) · GAP-192.C + GAP-194.A + GAP-194.B (issue/gap/opportunity log) |
| Closes | LOW-194.E (rate/hours asymmetry doc) — partially via §3 below |

## Context

`exec_cross_initiative_comparison(p_kind, p_cycle)` foi introduzida em p192 (migration `20260700000000`) como sucessora unificada das V3 readers `exec_cross_tribe_comparison(text)` e `get_cross_tribe_comparison()`, ambas dropped no arc V3→V4. A RPC retorna um envelope `{ initiatives: [...], kinds_present: [...], generated_at }` com **17 campos por iniciativa** cobrindo 5 kinds: `research_tribe`, `workgroup`, `committee`, `study_group`, `congress`.

Durante p194 dois bugs paralelos foram identificados via audit empírica + decisão PM:
- **GAP-192.C** (`total_hours`): subquery sumava horas de membros across ALL events no ciclo, sem filtro `ev.initiative_id = i.id`. Resultava em **inflação cross-kind** severa: Publicações WG mostrava 180.5h apesar do WG ter 0 events scoped; Comitê Curadoria 40h; LATAM Congress 21h. Research_tribes inflated ~30-60h vs V3 actual (geral + kickoff hours contabilizados via attendance).
- **GAP-194.A** (`members_inactive_30d`): mesma anti-pattern na NOT IN attendance subquery. Workgroup member que atendia event de research_tribe contava como "ativo" no workgroup. Resultado: workgroups/committees mostravam 0 inativos mesmo sem qualquer membro engajando com a própria iniciativa.

Ambos foram resolvidos com strict scope `AND ev.initiative_id = i.id` (PM Option B em GAP-192.C, PM Option A em GAP-194.A).

Restou ambiguidade semântica: alguns campos da RPC mantêm scoping diferente por razões de domínio. Este ADR codifica o **contrato de scoping** para evitar regressão futura e ajudar future readers.

## Decision

### §1. Princípio canônico: event-derived metrics são strict-scoped

Todos os campos derivados de `events` × `attendance` em `exec_cross_initiative_comparison` filtram explicitamente por `ev.initiative_id = i.id` (ou condição equivalente). Não há fallback cross-initiative para essas métricas.

Campos abrangidos por este princípio (post-p194):
- `total_hours` (migration `20260702000000`)
- `members_inactive_30d` (migration `20260703000000`)
- `meetings_count` (sempre teve o filtro)
- `last_meeting_date` (sempre teve o filtro)
- `days_since_last_meeting` (sempre teve o filtro)

Semântica: "métricas de atividade scoped a esta iniciativa".

**Consequência operacional**: kinds sem events próprios (workgroups/committees/congress sem meetings) mostram naturalmente 0h, 0 ativos (= 100% inativos), 0 meetings, NULL last_meeting. Isto é tautologicamente correto e honest — workgroups operam async e seu output deve ser medido por outras métricas (board cards, articles_submitted).

### §2. Exceção documentada: `attendance_rate` mantém NULL fallback para research_tribes

A subquery de `attendance_rate` retém:

```sql
WHERE (ev.initiative_id = i.id
       OR (i.kind = 'research_tribe' AND ev.initiative_id IS NULL))
```

Razão: histórico operacional. Research_tribes herdaram "geral" meetings com `initiative_id IS NULL` antes do V4 surface assignment. Removê-las do denominator da rate causaria 8/8 research_tribes terem rate inflada vs realidade (member counts unchanged; events count cai mas attendance count também). PM Option B (GAP-192.C) aceitou explicitamente esta assimetria com a justificativa "research_tribes inheritance + cross-kind comparability não conflitam neste campo".

**Consequência**: `attendance_rate` e `total_hours` para um membro research_tribe podem se referir a conjuntos diferentes de events. Um membro pode aparecer no denominador da rate (via geral meeting) mas suas horas do mesmo event NÃO aparecem em total_hours. Esta assimetria é **intencional e específica do kind research_tribe**.

### §3. Exceção codificada: XP é cohort-scoped por limitação de schema

`total_xp` e `avg_xp` filtram apenas por `gp.member_id IN (initiative members)` — não há filtro de scope sobre os points themselves. Razão: `gamification_points` schema **não tem coluna `initiative_id`** (verificado em p194 close via `information_schema.columns`).

Semântica atual: "XP total ganho por membros desta iniciativa across todas atividades do chapter no ciclo" — cohort-scoped, NÃO activity-scoped.

**Esta é uma limitação de schema, não um anti-pattern**. Para mudar para activity-scoped (paridade com total_hours) seria necessário:
1. ADR separado propondo `ALTER TABLE gamification_points ADD COLUMN initiative_id uuid`
2. Migration de backfill (heurística para points históricos)
3. Atualização de todas as RPCs award-point para set initiative_id (gamification triggers, register_event_showcase, award_champion, etc.)
4. Re-write das subqueries XP em `exec_cross_initiative_comparison` para usar o novo filter

Tracked no backlog como **GAP-194.B**. Decisão PM diferida — pode ser justificável OU não dependendo de feedback dos GP leaders sobre como interpretam XP cross-kind.

### §4. Campos não-event-derived são naturalmente scoped via tabela parent

Campos `total_cards`, `cards_completed`, `articles_submitted` filtram via `JOIN project_boards pb ON pb.id = bi.board_id WHERE pb.initiative_id = i.id` — scoping é pela tabela `project_boards`, não por `events`. Não há ambiguidade aqui porque cards são intrinsecamente initiative-scoped (cada board pertence a uma initiative).

Campo `member_count` filtra por `engagements.initiative_id = i.id AND engagements.status = 'active' AND engagements.kind != 'observer'` — scoping pela tabela `engagements`. Sem ambiguidade.

Campos `leader`, `quadrant`, `tribe_id`, `tribe_name` vêm direto da row da initiative + bridge tribe. Sem ambiguidade.

## Tests / Enforcement

Dois contract tests em `tests/contracts/impact-crosstribe.test.mjs` (offline static body-grep) reforçam o princípio §1:

```javascript
test('exec_cross_initiative_comparison total_hours is strict-scoped to initiative (p194 GAP-192.C ...)', () => {
  // asserts `AND ev.initiative_id = i.id` is present in total_hours subquery body
});

test('exec_cross_initiative_comparison members_inactive_30d is strict-scoped to initiative (p194 GAP-194.A)', () => {
  // asserts `AND ev.initiative_id = i.id` is present in members_inactive_30d NOT IN body
});
```

Phase C body-hash drift gate (`tests/helpers/rpc-body-drift-parser.mjs` shared parser) detecta mudanças no body via md5 hash post-p194 captures.

## Consequences

### Positivas
- **Cross-kind comparability**: workgroups/committees mostram honest 0h ao invés de inflação. Researchers vs operations apples-to-apples no UI `/admin/tribes`.
- **Type-as-documentation reinforced**: ADR-0085 atua como referência canônica para "what does each field mean" sem precisar reler RPC body.
- **Future regression guard**: contract tests ratchet down — qualquer migration acidentalmente removendo strict scope falha CI.

### Negativas / Trade-offs aceitos
- **Research_tribe rate/hours asymmetry** (§2): pode confundir auditors que comparam os dois campos. Documentado explicitamente acima.
- **XP cohort vs activity** (§3): leaders que querem "XP earned WITHIN this initiative" não têm essa métrica disponível. Requer schema change separado (GAP-194.B).
- **100% inactive para meetings-less kinds**: workgroups/committees mostram visualmente alarmante `(N inat.)` red. PM aceitou (Option A em GAP-194.A) com nota de que UX refinement (suppress/tooltip) é backlog OPP-194.F.

### Para path A/B/C optionality
- **Path A (PMI internal)**: positivo — metric semantics canônicas reduce risk de leader misinterpretation.
- **Path B (consultoria/multi-chapter)**: positivo — exportável como "métricas comparáveis cross-iniciativa" sem caveats inflacionários.
- **Path C (community-only)**: neutro.

## Status / Next Action

- [x] §1 enforced via migrations `20260702000000` + `20260703000000`
- [x] §2 documented (intentional asymmetry, PM-accepted)
- [x] §3 documented (schema limitation, backlog GAP-194.B)
- [x] §4 codified (parent-table scoping pattern)
- [x] Contract tests gating §1 (offline static body-grep)
- [ ] **OPP-194.F** UX refinement: suppress/tooltip `(N inat.)` for kinds with `meetings_count = 0` (backlog)
- [ ] **GAP-194.B** PM decision: doc-only acceptance vs schema addition for activity-scoped XP (backlog)

## Rollback

Não aplicável — este ADR codifica decisões já implementadas em migrations registradas. Reverter §1 (strict scope) seria reaplicar `20260700000000` body e reintroduzir as inflações documentadas em GAP-192.C + GAP-194.A. Não recomendado.
