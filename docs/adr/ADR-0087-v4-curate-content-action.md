# ADR-0087: V4 `curate_content` action — deprecate `'curator' = ANY(designations)` gate

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-05-19 (sessão p200) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migrations | `20260519182455` (seed) · `20260519182828` (scope='organization' correction) · `20260519183234` (batch A board) · `20260519183819` (batch B cert) · `20260519183955` (batch C governance) · `20260519184046` (batch D gate+reviewer) |
| Cross-ref | [ADR-0011](./ADR-0011-v4-auth-pattern-rpcs-mcp.md) (V4 auth pattern) · [ADR-0086](./ADR-0086-curation-manual-structured-review-pattern.md) (curation pipeline) · [ADR-0041](./ADR-0041-governance-review-action.md) (participate_in_governance_review precedent) |
| Closes | OPP-196.E (this ADR + 5 batched migrations) |

## Context

Audit p200 boot identificou **14 fns SECURITY DEFINER** usando o padrão V3 `'curator' = ANY(member.designations)` como auth gate. O backlog OPP-196.E estimava 8 fns; survey via `pg_proc.prosrc ILIKE '%curator%' AND prosrc ILIKE '%designations%'` (filtrado para auth-gate vs data-projection) confirmou 14.

Pré-ADR-0011 (V4 cutover 2026-04-13), `members.designations` (text[]) era a fonte operacional de "papéis transversais" (curator, co_gp, ambassador, comms_leader, chapter_liaison etc.). Pós-V4, a fonte canônica é `engagements × engagement_kind_permissions` consultada via `can()/can_by_member()`. ADR-0011 §1 define explicitamente: *"`engagement_kind_permissions` é a única fonte de verdade de autoridade"*. Manter `'curator' = ANY(designations)` viola esse invariante e cria drift silencioso:

- **Silent drift risk**: se um novo curator é onboarded via `committee_coordinator` engagement mas `designations` array não é atualizado, todos os 14 gates falham — apesar do MCP layer (que usa `canV4`) já aceitar.
- **Dual source of truth**: novas seeds em `engagement_kind_permissions` requerem patch paralelo no array. Conflito direto com ADR-0011.
- **Onboarding/offboarding atomicidade**: V3 path exige sync `members.designations` + `engagements` em duas operações distintas. Sem trigger garantindo idempotência.

ADR-0086 (curation pipeline 2026-05-18) reafirmou centralidade do curator role no fluxo `peer_review → leader_review → curation_pending → published`; é o momento certo para fechar o legado V3.

3 curators ativos em produção (p200 snapshot):
- **Fabricio Costa**: designations=`[ambassador, founder, curator, co_gp, deputy_manager]` + active `committee_coordinator × leader` engagement em init `6a93cc94` (curation committee)
- **Roberto Macêdo**: designations=`[chapter_liaison, ambassador, curator]` + active `committee_coordinator × coordinator` em init `6a93cc94` + active `observer × curator` em init `9cbaf0b9` (cross-initiative observer-curator)
- **Sarah Faria Macedo Rodovalho**: designations=`[ambassador, founder, curator]` + active `committee_coordinator × coordinator` em init `6a93cc94`

Os 3 curadores têm V4 engagement coverage suficiente. Sweep não requer backfill de engagement; apenas seed da action nova.

## Decision

### §1. Introduzir action `curate_content` em `engagement_kind_permissions`

3 tuples seed:

```sql
INSERT INTO engagement_kind_permissions (kind, role, action) VALUES
  ('committee_coordinator', 'coordinator', 'curate_content'),
  ('committee_coordinator', 'leader',       'curate_content'),
  ('observer',              'curator',      'curate_content');
```

Cobertura empírica pós-seed:
- Fabricio: ✅ via committee_coordinator.leader
- Roberto: ✅ via committee_coordinator.coordinator + observer.curator
- Sarah: ✅ via committee_coordinator.coordinator

Observer.curator é incluído explicitamente porque modela "cross-initiative curator" — quem cura conteúdo de iniciativa em que não é membro pleno (Roberto em init `9cbaf0b9`). Distinto semanticamente de committee_coordinator (que é membro do comitê de curadoria).

### §2. Sweep V4: substituir `'curator' = ANY(designations)` por `can_by_member('curate_content')` em 14 fns

Agrupadas em 4 batches por purpose:

**Batch A — Board ops (5 fns)**: `admin_archive_board_item`, `assign_member_to_item`, `create_board_item`, `update_board_item`, `upsert_board_item`. Padrão: curator clause em OR chain com `tribe_leader`/`co_gp`/`communicator`. Swap apenas a clause curator; demais permanecem (escopo OPP-196.E é narrow — apenas curator V3→V4).

**Batch B — Certificate ops (3 fns)**: `get_all_certificates`, `issue_certificate`, `update_certificate`. Padrão inverso: `AND NOT ('curator' = ANY(designations))` (curator é exception ao gate manager-only). Swap preserva inversão lógica: `AND NOT can_by_member('curate_content')`.

**Batch C — Governance/curation ops (4 fns)**: `review_change_request`, `submit_change_request`, `get_application_score_breakdown`, `upsert_publication_submission_event`. Mix de OR chains e standalone checks.

**Nota PII (Batch C `get_application_score_breakdown`)**: a fn já chama `_log_application_pii_access` com lista de 14 campos PII expostos a callers autorizados (linha ~49 da migration `20260519183955`). O `curate_content` gate (Batch C) **mantém o mesmo set de callers autorizados** que o V3 `designations && ARRAY['curator']`, então não há scope expansion. Auditoria via PII log preserved. (Council code-reviewer HIGH #1 — note tracking; nenhuma mudança de código necessária.)

**Batch D — Special semantics (2 fns)**:
- `_can_sign_gate`: gate kind 'curator' retorna `'curator' = ANY(v_member.designations)`. Swap direto.
- `assign_curation_reviewer`: valida o REVIEWER target (não caller). Swap para `can_by_member(p_reviewer_id, 'curate_content')` — semantic shift (target-user check em vez de caller-check, mas same V4 pattern).

### §3. Não-targets (data refs, não auth-gates)

Fns que mencionam `curator` mas não usam como auth gate permanecem inalteradas:

- `_auto_remove_designation_on_cert` — função inferior que mapeia function_role string → designation array (DATA, não auth)
- `check_schema_invariants` — invariant N5 conta engagements com role IN (...'curator'...)
- `create_document_comment` — `'curator_only'` é VISIBILITY enum, não designation
- `get_attendance_panel` — projeta `is_curator boolean` para enriquecimento de payload
- `get_board_members` — projeta 'curator' label como categoria de membership
- `get_org_chart` — agrega lista de curators para org tree
- `get_tribe_event_roster` — usa curator filter como cohort selection
- `is_event_mandatory_for_member` — usa `v_is_curator` para regra de obrigatoriedade

Audit completo via `pg_proc` survey confirmou 22 fns total referenciando curator+designations; 14 são gates → sweep; 8 são data refs → no-op.

### §4. Rollback

Por batch (cada um é git revert independente):

```sql
-- Rollback seed (após reverter os 4 batches):
DELETE FROM engagement_kind_permissions WHERE action = 'curate_content';
```

Para reverter as 14 fns, fazer git revert dos 4 batches em ordem inversa (D → C → B → A). DDL é idempotente (CREATE OR REPLACE FUNCTION via apply_migration MCP).

Side effect crítico ao rollback: o V3 path `'curator' = ANY(designations)` deve continuar funcionando porque o array NÃO foi tocado. Não há lossy migration de state.

### §5. Não-decisões (escopo OPP-196.E é narrow)

Decisões deliberadamente fora desta ADR (carry para futuros itens de backlog):

- **`co_gp` V3 designation gate** (presente em board fns): mantida em V3 até GAP futuro
- **`tribe_leader` operational_role check**: mantido em V3 (operational_role cache continua válido per ADR-0011 §4)
- **`communicator` operational_role check**: idem
- **Total deprecate de `members.designations` column**: não desta ADR; carry como WATCH item se sweep V4 atinge ≥80% das gates

## Validation

Pós-sweep:
1. `check_schema_invariants()` → 16/16=0 (não introduz violation)
2. Smoke `can_by_member('<curator_id>', 'curate_content')` → true para 3 curators
3. Smoke `can_by_member('<non_curator_id>', 'curate_content')` → false
4. RPC body-hash drift gate em `tests/contracts/rpc-body-drift.test.mjs` (allowlist atualizado pós-sweep ou ratchet down)
5. Tests offline baseline 1449/0/46 (sem regressão)

## Consequences

Positive:
- Source-of-truth consolidation para curator authority (ADR-0011 compliance)
- New curator onboarding requer apenas engagement INSERT (não designations array touch)
- Drift entre MCP layer e RPC layer eliminado para curator gate
- ADR-0086 curation pipeline ganha mais um pilar V4

Negative:
- 14 fns alteradas em uma sessão → blast radius moderado; mitigado por batch grouping e per-batch rollback
- ADR-0011 sweep continua incompleto: `co_gp`/`tribe_leader`/`communicator` ainda V3
- Body-hash drift allowlist pode precisar regen pós-sweep (verify em batch close)

Neutral:
- `members.designations` array continua sendo escrito (não deprecated); apenas deixa de ser AUTH gate para curator
- Frontend (admin panels) que usa `designations` para UI labels não muda (data-only)
