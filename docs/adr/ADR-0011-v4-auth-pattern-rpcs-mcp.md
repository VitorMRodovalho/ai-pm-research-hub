# ADR-0011: V4 Auth Pattern — RPCs + MCP (single source of truth via `can()`)

- Status: Accepted
- Data: 2026-04-17
- Aprovado por: Vitor (PM) em 2026-04-17
- Autor: Vitor (PM) + Claude (comitê arquitetural)
- Escopo: Autenticação e autorização de RPCs, MCP tools e front paths — pós Domain Model V4

## Contexto

O cutover Domain Model V4 (13/Abr/2026 — ver ADR-0007 e `DOMAIN_MODEL_V4_MASTER.md`) entregou as primitivas:
- `public.can(p_person_id, p_action, p_resource_type, p_resource_id)` — retorna boolean consultando `auth_engagements` × `engagement_kind_permissions`
- `public.can_by_member(p_member_id, p_action, ...)` — wrapper que aceita `members.id` em vez de `persons.id`
- `public.rls_can(p_action)` — helper para RLS policies consultando `auth.uid()`
- TypeScript `canV4(sb, member_id, action)` — wrapper para MCP tools (EF `nucleo-mcp`)

Auditoria 17/Abr (Eixo A da sessão de hoje) revelou drift estrutural: de **576 RPCs SECURITY DEFINER**, apenas **5 usam `can()`/`can_by_member()`**. As outras **83 RPCs com auth gate** ainda verificam `operational_role IN ('manager','deputy_manager',...)` hardcoded. Efeitos:

1. **Divergência silenciosa**: se um novo kind/role é adicionado a `engagement_kind_permissions` com permission `manage_event`, o MCP aceita (via `canV4`) mas a RPC rejeita (não reconhece o role).
2. **Dupla fonte de verdade**: MCP-level e RPC-level decidem independentemente. Mudança de política exige dois patches.
3. **`engagement_kind_permissions` subutilizado** como fonte operacional única.

Nenhum incidente reportado em `mcp_usage_log` nos últimos 30 dias (0 unauthorized em 200+ calls), mas o drift é dívida técnica que cresce com o tempo.

## Decisão

**`public.can()` / `public.can_by_member()` é a ÚNICA fonte de verdade de autoridade no banco. Todas as RPCs com auth gate DEVEM invocá-la em vez de verificar `operational_role` hardcoded.**

### Padrão canônico por camada

| Camada | Implementação obrigatória |
|---|---|
| **RLS policies** | `rls_can('<action>')` — helper que lê `auth.uid()` e delega a `can()` |
| **RPC SECURITY DEFINER (write)** | `IF NOT public.can_by_member(v_caller_id, '<action>') THEN RAISE EXCEPTION ...` |
| **RPC SECURITY DEFINER (PII read)** | `IF NOT public.can_by_member(v_caller_id, 'view_pii') THEN RAISE EXCEPTION ...` |
| **RPC SECURITY DEFINER (read s/ PII)** | Auth gate opcional — depender de RLS/MCP gate já é suficiente |
| **MCP tools (write)** | `if (!(await canV4(sb, member.id, '<action>'))) return err("Unauthorized")` |
| **MCP tools (read PII)** | `canV4(sb, member.id, 'view_pii')` ou delegação à RPC (que já gate) |
| **Front paths `/admin/*`** | Middleware verifica via RPC helper e redireciona |

### Actions canônicas

Definidas em `engagement_kind_permissions.action`:
- `write` — operações de escrita de domínio (criar evento, marcar presença, criar ata, notificar tribo)
- `write_board` — criar/mover cards em board (granularidade menor que `write`)
- `manage_event` — editar/cancelar evento, inclusive em série recorrente
- `manage_member` — offboard/reactivate/update member, mudar role/designations
- `manage_partner` — CRUD de parceiros e interactions
- `promote` — triagem/promoção de aplicações do ciclo seletivo
- `view_pii` — ler email/phone/pmi_id/auth_id/cpf de membros/pessoas

Novas actions são introduzidas via seed em `engagement_kind_permissions`, **nunca** via código de RPC.

### Scope refinement quando `can()` não é suficiente

Para casos em que `can()` não modela finura de recurso (ex: "tribe_leader só gerencia eventos da própria tribo"), a RPC aplica **segundo check refinado** APÓS `can_by_member`:

```sql
IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
  RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
END IF;

-- Scope refinement: tribe_leader constrained to own tribe
IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_event_tribe THEN
  RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage events of own tribe';
END IF;
```

Este padrão é **temporário**. A evolução desejada é que `can()` aceite `resource_type='event'` e resolva scope internamente (tracked como tech-debt).

### Proibido (anti-patterns)

- `IF v_caller.operational_role IN ('manager','deputy_manager',...)` como ÚNICO gate
- `IF v_caller.is_superadmin = true` como ÚNICO gate
- Duplicar lógica de role list em RPC quando `can()` já expressa a política
- Introduzir nova RPC com auth gate hardcoded — sempre use `can_by_member`

## Consequências

### Positivas
- **Single source of truth**: política vive em `engagement_kind_permissions`, propaga automaticamente
- **Menor custo de mudança**: adicionar kind/role com permission é seed, não migration de RPCs
- **Audit trail**: `engagement_kind_permissions` documenta a matriz completa
- **Defense in depth real**: MCP gate + RPC gate consultam a mesma fonte; contradições impossíveis

### Negativas / Tech debt conhecida
- **83 RPCs legacy** (pós-auditoria 17/Abr) ainda usam role hardcoded. Fixar uma RPC por sessão quando tocá-la, ou em esforço dedicado.
- `can()` não resolve scope por event/tribe ainda — exige refinement adicional na RPC.
- `operational_role` (cache) ainda é usado em vários places para outras finalidades (filtros, display, sync). Manter como cache, não como fonte de autoridade.

### Bloqueio
- Teste de contract (`tests/contracts/rpc-v4-auth.test.mjs`) falhará se uma RPC SECURITY DEFINER nova for criada com auth gate sem chamar `can*`. Ver A4.5.

## RPCs refatoradas como parte deste ADR (17/Abr)

Migrations `20260424040000`, `20260424050000`, `20260424060000`:

### Event domain (3)
- `drop_event_instance(uuid, boolean)` → `manage_event` + tribe-scope
- `update_event_instance(uuid, ...)` → `manage_event` + tribe-scope
- `update_future_events_in_group(uuid, ...)` → `manage_event` + tribe-scope

### Member admin (6)
- `admin_offboard_member(uuid, text, text, text, uuid)` → `manage_member`
- `admin_reactivate_member(uuid, int, text)` → `manage_member`
- `admin_update_member(uuid, ...)` → `manage_member`
- `admin_update_member_audited(uuid, jsonb)` → `manage_member`
- `promote_to_leader_track(uuid, boolean)` → `promote`
- `manage_selection_committee(uuid, text, uuid, text)` → `promote`
- DROP `admin_reactivate_member(uuid)` overload legacy (sem auth gate)

### PII reads (3)
- `admin_get_member_details(uuid)` → `view_pii`
- `admin_list_members_with_pii(int)` → `view_pii`
- `export_audit_log_csv(text, text, text)` → `view_pii`

## Próximos passos

1. **Refatoração contínua**: cada sessão que tocar uma RPC com drift deve migrá-la (one-at-a-time)
2. **Enriquecer `can()` com scope por event**: quando escalar, resolver event-level scope dentro de `can()` em vez de scope refinement na RPC
3. **ADR-0012 (futuro)**: formalizar o padrão `can()` + `view_X_context` helpers para views sensíveis

## Referências

- ADR-0007 — V4 Authority source of truth (cutover 13/Abr)
- `DOMAIN_MODEL_V4_MASTER.md` — histórico completo do refactor
- `engagement_kind_permissions` — matriz seeded de `kind × role × action × scope`
- Migrations `20260424040000` → `20260424060000` — refactor das 12 RPCs

---

## Amendment A — Fast-path stakeholder fan-out (2026-04-24)

- Status: Accepted
- Aprovado por: Vitor (PM) em 2026-04-24
- Escopo: Carve-out formal para funções `SECURITY DEFINER` que precisam enumerar N stakeholders em um loop síncrono (triggers de notificação, cron de varredura).

### Contexto

Durante a sessão p41 (24/Abr/2026) foram introduzidas três funções que enumeram stakeholders para fan-out de notificações / alertas:

| Função | Propósito | Contexto |
|---|---|---|
| `public.notify_offboard_cascade()` | Fan-out de notif a GPs/DMs + líderes da tribo quando membro offboarda | AFTER UPDATE trigger em `members.member_status` |
| `public.detect_orphan_assignees_from_offboards(uuid?)` | Varre board_items assignados a membros inativos, emite `board_taxonomy_alerts` | RPC chamada pelo trigger acima + pg_cron diário |
| `public.notify_offboard_cascade()` (re-extendida em 20260509050000) | Idem + invoca detector de orphans | Continuação do mesmo trigger |

O padrão canônico desta ADR manda usar `public.can_by_member(member_id, action)` para gate. Mas para fan-out de N stakeholders (onde N pode chegar a 30-50 membros ativos), chamar `can_by_member` em loop seria O(N) com custo prohibitive — cada chamada faz consulta em `auth_engagements × engagement_kind_permissions`.

Guardian (p41 end-of-session) flagged este pattern como ADVISORY (não blocker): as três funções usam `operational_role IN ('manager','deputy_manager')` e `operational_role IN ('tribe_leader','co_leader')` direto, sem delegar a `can()`. 

### Decisão

**Funções SECURITY DEFINER que enumeram stakeholders para fan-out (notificações, alertas, reports) podem consultar `members.operational_role` diretamente como fast-path, desde que cumpram TODOS os critérios abaixo:**

1. **Cache authoritative**: a coluna `members.operational_role` é mantida pelo trigger `sync_operational_role_cache` (ADR-0012), que refresca com base em `auth_engagements`. Portanto o valor reflete a mesma fonte que `can()` consumiria — não há risco de divergência estrutural.
2. **Sem escrita autorizativa**: a função **não** grava decisão autorizativa (não é gate de `write`, `write_board`, `manage_member`). Apenas enumera quem RECEBE uma notificação ou aparece em um report.
3. **Sem PII cross-member**: a função não retorna email/phone/pmi_id de outros membros. Apenas `member_id` + nome + role (dados já não-sensíveis).
4. **Documentada em comentário**: o header da função OU uma linha `COMMENT ON FUNCTION` declara explicitamente "fast-path stakeholder fan-out per ADR-0011 Amendment A".

### Não-exceções (continuam obrigadas a `can_by_member`)

- Gates de escrita: `write`, `write_board`, `manage_member`, `manage_event`, `manage_partner`, `promote`
- Gates de PII read: `view_pii`
- Funções que decidem se o caller pode executar uma ação (o próprio caller é verificado)

### Aplicabilidade retroativa

As três funções listadas acima são formalmente aprovadas como conformes à Amendment A a partir de 2026-04-24, sem necessidade de refactor. Próxima sessão que tocar essas funções por outro motivo deve adicionar o comentário referente à Amendment A.

### Critério de revisão

Se o número de funções usando fast-path exceder 10, ou se surgir incidente onde a cache `operational_role` divergiu de `auth_engagements` (invariant A3 violation), esta Amendment é revisada. Próxima Amendment pode introduzir helper batch `can_batch(member_ids, action)` que mantém a semântica canônica com custo amortizado.

---

## Amendment B — V3→V4 cleanup batch 1+2 (2026-04-26)

- Status: Accepted
- Aprovado por: Vitor (PM) em 2026-04-24
- Escopo: 22 RPCs SECURITY DEFINER pós-cutover (20260424+) que mantinham gate V3 (`operational_role IN (...)`) e haviam escapado do parser do contract test `tests/contracts/rpc-v4-auth.test.mjs` por uso de delimitador tagged (`$function$` / `$fn$`) — o parser original assumia `$$` apenas.

### Contexto

A sessão p48 (2026-04-26) tightening o parser de `rpc-v4-auth.test.mjs` (back-reference `\$(\w*)\$...\$\1\$` em vez de `\$\$...\$\$`, plus `usesV3RoleAuthority()` matcher distinguindo authority context de data filter) surfaced **22 RPCs latent V3** distribuídas em 9 migrations entre 20260428 e 20260510. Triagem inicial reportou 29 candidatos, dos quais:

- **22 = true V3 violations** (pure role-list gate, sem `can*`) — migradas nesta amendment
- **3 = false positives** já V4 (`create_initiative_event`, `manage_initiative_engagement`, `sign_ip_ratification`) — parser refinado para reconhecer `can(arg, 'action')` e helpers `_can_*`
- **4 = baseline-auth-only** (`get_tribe_events_timeline`, `search_board_items`, `get_version_diff`, `get_document_detail`) — pure "is member" gate, sem role authority — não são violações ADR-0011

### RPCs migrados (22)

Aplicados em 2 migrations atomic:

#### Batch 1 — `20260513010000_adr0011_v3_to_v4_admin_readers_batch1.sql` (10 RPCs → `manage_platform`)

| RPC | Origem |
|---|---|
| `detect_and_notify_detractors` | 20260428050000 |
| `detect_operational_alerts` | 20260428050000 |
| `send_attendance_reminders` | 20260428050000 |
| `exec_all_tribes_summary` | 20260428050000 |
| `get_cross_tribe_comparison` | 20260428050000 |
| `exec_cycle_report` | 20260428100000 |
| `get_admin_dashboard` | 20260428130000 |
| `exec_cross_tribe_comparison` | 20260428140000 |
| `get_adoption_dashboard` | 20260428140000 |
| `get_campaign_analytics` | 20260428140000 |

#### Batch 2 — `20260513020000_adr0011_v3_to_v4_writers_batch2.sql` (12 RPCs)

**Sub-grupo 2a — `manage_event` + scope refinement** (5):
- `bulk_mark_excused`, `update_event`, `generate_agenda_template`, `get_tribe_event_roster`, `get_event_detail` (mixed: `gp_only` → `manage_platform`; `leadership` → `manage_event`)

**Sub-grupo 2b — `write_board` + scope refinement** (5):
- `assign_checklist_item`, `complete_checklist_item`, `create_board_item`, `move_board_item`, `update_board_item`

**Sub-grupo 2c — special cases** (2):
- `exec_tribe_dashboard`: own-tribe carve-out (qualquer membro vê própria tribo) + cross-tribe gate via `manage_platform`
- `get_member_attendance_hours`: self carve-out + `view_pii`

### Behavior change documented

A migração tightens authority for **non-superadmin sponsor (5 users) e chapter_liaison (2 users)** que tinham acesso V3 a admin dashboards via role-list gate. Em V4, `manage_platform` não inclui esses operational_roles (volunteer × {manager, deputy_manager, co_gp} apenas). Total impactado: 7 usuários, todos retêm self-tribe view via `exec_tribe_dashboard` carve-out. PM aceitou em 2026-04-24 como tightening alinhado com ADR-0007.

Se PM decidir restaurar acesso, basta seed em `engagement_kind_permissions`:
```sql
INSERT INTO engagement_kind_permissions (kind, role, action, scope) VALUES
  ('sponsor', 'sponsor', 'manage_platform', 'organization'),
  ('chapter_advisory', 'liaison', 'manage_platform', 'organization');
```

### Parser tightening (lockstep)

`tests/contracts/rpc-v4-auth.test.mjs` foi refinado para:

1. **Tagged delimiter support**: regex `\$(\w*)\$...\$\1\$` (back-reference) em vez de `\$\$...\$\$`. Captura `$function$`, `$fn$`, `$body$`, `$$`.
2. **`usesV3RoleAuthority()`**: distinguir authority context (IF/THEN block + caller-lookup WHERE) de data filter (`m.operational_role NOT IN ('sponsor', ...)` em count subquery). Tracks local var aliases (`v_is_admin := is_superadmin OR ...`) e SELECT INTO bindings para detectar V3 indireto.
3. **`usesV4Can()`**: reconhece `can(arg, 'action', ...)` e helpers `public._can_*` além de `public.can()` / `public.can_by_member()` / `rls_can()`.
4. **IF block boundary anchor**: regex ancorado a `(?:^|[;\n])\s*IF` para evitar matching `IF` final de `END IF;`.

### Critério de revisão

Esta amendment é considerada a "varredura final" do drift V3→V4 em RPCs pós-cutover. Próximas migrations devem usar `can_by_member` direto. Se o parser surfacear nova batch (drift por delimitador novo, helper indireto não reconhecido, etc.), nova amendment.

### Tests baseline pós-amendment

- `npm test`: 1361/1/23 → **1360/0/23** (net -1 test count: 6 V3 contract tests substituídos por 5 V4 equivalents; 1 pre-existing `events.tribe_id` fail consertado para usar `i.legacy_tribe_id` post-ADR-0015 phase 3e)
- `tests/contracts/rpc-v4-auth.test.mjs`: 0 violations
- Invariants 11/11 = 0 violations

---

## Cross-reference — ADR-0028 service-role-bypass adapter (2026-04-26)

A segunda classe formal de exceção ao padrão canônico
`can_by_member`-at-top (após Amendment A fast-path stakeholder fan-out)
é o **service-role-bypass adapter** documentado em
`ADR-0028-service-role-bypass-adapter-pattern.md`. Conceitualmente
equivalente a uma "Amendment C" desta ADR-0011, mas mantida como ADR
standalone para discoverability do surface dual-tier (cron/EF +
user-tier).

**Padrão**:
```sql
IF auth.role() = 'service_role' THEN
  NULL;  -- machine-caller class boundary, infrastructure-auth chain
ELSE
  -- V4 contract preserved on user-tier branch
  IF NOT public.can_by_member(v_caller_id, '<action>') THEN
    RAISE EXCEPTION 'permission_denied: <action> required';
  END IF;
END IF;
```

**Surface coberto**: 37 fns (30 Batch 1 clean → `manage_platform`; 7
Batch 2 extended → ADR-0029 `audit_access` action).

**Enforcement**: ADR-0028 §"Q3 resolution" especifica defesa em 4
camadas (allowlist nomeada + size guard + stale-entry cross-check +
COMMENT sentinel + invariant G novo em `check_schema_invariants()`)
para impedir pattern creep além do surface documentado.

**Critério de aplicabilidade**: o adapter é válido APENAS para fns
chamáveis tanto por cron/EFs (autenticadas no nível de infraestrutura
via service_role JWT) QUANTO por usuários admin via UI. NUNCA usar como
escape hatch de conveniência para falhas de gate user-tier.
