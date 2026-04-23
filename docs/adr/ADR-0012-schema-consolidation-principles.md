# ADR-0012: Schema Consolidation Principles (fact × dimension × cache)

- Status: Accepted
- Data: 2026-04-17
- Aprovado por: Vitor (PM) em 2026-04-17
- Autor: Vitor (PM) + Claude (comitê arquitetural)
- Escopo: Decisões de schema para evitar drift entre colunas que representam o mesmo conceito. Complementa ADRs V4 (0004-0009) e ADR-0011 (autoridade).

## Contexto

Auditoria 17/Abr (Eixo B da sessão) identificou drift estrutural em 5 áreas:

1. **Pessoa/membro**: `member_status × operational_role × is_active × designations` armazenam informação sobreposta. Caso âncora — Wellington 16/Abr: `designations=['observer']` + `member_status='observer'` + `operational_role='none'`. Audit revelou **11 rows em drift** (todos offboards pré-2026-04-17).
2. **Eventos**: 150 eventos com `tribe_id + initiative_id` (dual escopo pós-V4). 65 com `recurrence_group` mas `nature != 'recorrente'` — semantic drift tolerado.
3. **Logs fragmentados**: 17 tabelas log/audit (`admin_audit_log`, `member_role_changes`, `member_status_transitions`, `platform_settings_log`, `curation_review_log`, `pii_access_log`, `mcp_usage_log`, `broadcast_log`, ...). `admin_audit_log` já tem shape genérico suficiente mas é subutilizado.
4. **Bridge V4**: 22 tabelas com `tribe_id` legacy, 17 com `initiative_id`, 4 com `legacy_tribe_id` em tabelas de migração. Migração V4 parou no meio — dual-write funcional mas legacy não foi deprecado.
5. **Duplicação de fluxos**: `volunteer_applications` (143 rows batch 10/Mar, 64 emails) paralela a `selection_applications` (80 rows ativa 14/Mar→hoje, 75 emails). Dois fluxos de aplicação históricos coexistindo.

Conceitos como "pessoa ativa" são computáveis de múltiplas formas hoje — e o resultado nem sempre coincide. A dor é real: jornadas de UI divergem porque queries SQL escolhem colunas diferentes como fonte.

## Decisão

### Princípio 1 — Single source of truth por conceito

Para cada conceito de domínio (status de membro, autoridade, escopo de evento), **uma coluna é fonte; as demais são cache explicitamente documentado**.

| Conceito | Source of truth | Cache/espelhos |
|---|---|---|
| Autoridade operacional | `engagements` (via `can()` — ADR-0007) | `members.operational_role` (trigger-synced) |
| Status de membro | `members.member_status` | `members.is_active` (derivado), `members.designations` (cleared on terminal) |
| Escopo de evento | `events.initiative_id` (V4) | `events.tribe_id` (bridge, ADR-0005) |
| Identidade | `persons` (V4) | `members.person_id` (FK bridge) |
| Kind+role de engagement | `engagements` (V4) | `members.operational_role` (cache) |

Se o valor derivado diverge do source of truth, **o derivado é corrigido** (via trigger, batch sync, ou migration), **nunca o reverso**.

### Princípio 2 — Cache columns exigem trigger de sync explícito

Toda coluna cache deve ter:
- **Origem documentada** no CREATE TABLE (comment ou ADR ref)
- **Trigger de sync** (`sync_<concept>_consistency`) instalado na tabela source OU na tabela cache
- **Invariante testável** via query — e.g. `SELECT COUNT(*) WHERE cache <> expected = 0`

Exemplo (instalado 17/Abr para members):

```sql
CREATE TRIGGER trg_sync_member_status_consistency
BEFORE INSERT OR UPDATE OF member_status, operational_role, is_active, designations
ON public.members
FOR EACH ROW EXECUTE FUNCTION public.sync_member_status_consistency();
```

Invariantes enforçadas:
- `member_status='active'` ⇒ `is_active=true`
- `member_status IN ('observer','alumni','inactive')` ⇒ `is_active=false`, `designations='{}'`
- `member_status='alumni'` ⇒ `operational_role='alumni'`
- `member_status='observer'` ⇒ `operational_role IN ('observer','guest','none')`

### Princípio 3 — Coerção, não rejeição

Triggers corrigem valores inconsistentes **silenciosamente** (coerce), não rejeitam. Motivo: caller (RPC, admin UI, sync job) pode ter informação parcial; rejeitar quebra a UX. Audit de coerção pode ser adicionado em `admin_audit_log` se a auditoria for necessária.

### Princípio 4 — Deprecation explícita de dupla-fonte

Quando duas tabelas cobrem o mesmo domínio (ex: `volunteer_applications` × `selection_applications`):

1. Marcar a legacy com `COMMENT ON TABLE` apontando para a current + data de deprecation
2. Bloquear novas INSERTs via RLS (só SELECT)
3. Plano de migração dos dados únicos da legacy → current (se existirem)
4. Tracking no master doc de tech debt

### Princípio 5 — Logs especializados devem ter propósito distinto

`admin_audit_log` é a dimensão mestra de auditoria (target_type flexível, changes jsonb, actor_id, metadata). Tabelas de log especializadas só se justificam se:
- **Shape é fundamentalmente diferente** (ex: `mcp_usage_log` tem tool_name + duration_ms, não se encaixa em audit_log)
- **Volume de escrita é desproporcionalmente alto** (isolamento de IO)
- **Retenção tem política distinta** (ex: `pii_access_log` LGPD 5y, `admin_audit_log` indefinido)

Tables que violam o critério e devem ser consolidadas (tech debt):
- `member_role_changes` → `admin_audit_log` com `action='role_changed'`, `target_type='member'`
- `member_status_transitions` → `admin_audit_log` com `action='status_changed'`, `target_type='member'` (preservando semantic de `previous_status`, `new_status`, `reason_category` em `changes` jsonb)
- `platform_settings_log` → `admin_audit_log` com `action='setting_changed'`

### Princípio 6 — Invariant checklist obrigatório para schema change

Quando uma migration altera tabelas de domínio (members, events, persons, engagements, board_items), deve declarar explicitamente:
- Quais invariantes novos introduz
- Quais invariantes existentes não quebra
- Test de contract (se possível)

## Consequências

### Positivas
- Wellington-like drifts impossíveis de ocorrer silenciosamente (trigger coerce)
- Novos desenvolvedores entendem o modelo via ADR + triggers explícitos
- Mudanças de política se propagam automaticamente (cache é derivado, não escrito manualmente)
- Audit consolidado reduz fragmentação de investigação

### Negativas / Tech debt conhecida (tracked)
- **22 tabelas com tribe_id legacy** — dual-write funcional mas não-deprecado. Plano de migração pendente.
- **5 tabelas log** candidatas a consolidar em `admin_audit_log` — refactor dedicado (não urgente).
- **volunteer_applications** legacy com 143 rows em standby — decidir migração ou arquivar.
- **cycles × selection_cycles** — separação válida (dim genérica × dim específica), mas documentar a fronteira para evitar confusão.

## Saneamento aplicado hoje (17/Abr)

Migration `20260424070000_b5_b7_member_invariants.sql`:
- 9 rows de drift de membro saneadas (3 observer + 6 alumni)
- Trigger `sync_member_status_consistency` instalado (previne drift futuro)
- 1 row flagged para human review: "VP Desenvolvimento Profissional (PMI-GO)" — `member_status='active'` + `is_active=false` + `operational_role='observer'` é policy question, não drift óbvio

## Próximos passos

1. ~~**ADR-0013 (futuro)**: roadmap de deprecation de `tribes`/`tribe_id`~~ — reassigned: ADR-0013 foi usado para log table taxonomy (18/Abr). Tribes deprecation vira ADR novo quando atacado.
2. **B8**: consolidar `member_role_changes` + `member_status_transitions` em `admin_audit_log` (sessão dedicada) — **DONE** migration `20260425020000` (17/Abr)
3. **B9**: decidir destino de `volunteer_applications` — **DONE** kept as historical, RPC migrado para `selection_applications` (migration `20260426010000`)
4. **B10**: test de contract invariants (query-based) rodando em CI — **DONE** migration `20260425010000` + workflow `.github/workflows/invariants-check.yml`

## Referências

- ADR-0005 — Initiative as domain primitive (fonte da dual-write tribe/initiative)
- ADR-0006 — Person + Engagement (fonte da separação identidade × status)
- ADR-0007 — Authority as engagement grant (fonte de `operational_role` como cache)
- ADR-0011 — V4 auth pattern (complementa: source of truth de autoridade)

## Amendment A — artifacts archival closure (23/Abr 2026)

**Status**: closed — schema 100% limpo de artifacts.

Ciclo completo Parts 1-4 aplicou os Princípios 1-4 desta ADR à tabela legacy `public.artifacts` (29 rows congelados pré-V4) que convivia como pseudo-fonte paralela a `publication_submissions`:

- **Part 1** (`20260504080000`, 20/Abr p35 commit `6c58204`): migrou 29 rows legacy → `publication_submissions` com marker `'[Legacy artifact migrated%'` em `reviewer_feedback`. BEFORE INSERT trigger bloqueia novas writes na tabela congelada. `I_artifacts_frozen` invariant instalado.
- **Part 2** (`20260504080001`, 20/Abr p35 commit `6c58204`): 8 readers remapped para `publication_submissions` (`exec_funnel_summary`, `exec_skills_radar`, `get_executive_kpis`, `sync_attendance_points`, `platform_activity_summary`, `list_curation_board`, `list_pending_curation`, `enqueue_artifact_publication_card` marcado deprecated). Semântica preservada (`get_executive_kpis` continua retornando 6 published).
- **Part 3** (`20260507010000`, 23/Abr p37 commit `70bd67f`): `DROP TABLE public.artifacts CASCADE` após janela 48h+ shadow. `I_artifacts_frozen` removido do `check_schema_invariants()` (substituído estruturalmente pela ausência da tabela). Durante smoke pós-DROP descobriu-se 4 frontend surfaces ainda com `sb.from('artifacts')` — mitigado com compat VIEW read-only como backstop temporário.
- **Part 4** (`20260507020000`, 23/Abr p38 commit `a55d67d`): fechou o ciclo. `DROP VIEW public.artifacts` + `DROP FUNCTION reject_artifacts_insert()` (trigger fn órfã) + `DROP FUNCTION enqueue_artifact_publication_card(uuid, uuid)` (deprecated em Part 2) + `REPLACE curate_item` sem branch `'artifacts'` (fazia `UPDATE public.artifacts` em VIEW, que teria falhado — Part 2 COMMENT prometia a excisão mas não executou). 4 frontend surfaces migradas para `publication_submissions` via `primary_author_id`. `/artifacts` virou redirect 301 → `/publications` preservando `?lang=X`.

**Estado final do schema**: zero dependents de `public.artifacts` em qualquer layer. 29 rows legacy continuam consultáveis via `publication_submissions.reviewer_feedback LIKE '[Legacy artifact migrated%'` (backstop histórico read-only).

**Lessons**:
- DROP VIEW requer sweep combinado: `grep sb.from()` frontend + `pg_proc` funções que leem a VIEW. Part 3 smoke pegou só frontend; Part 4 adicionou pg_proc search e encontrou 2 funções stale.
- `CREATE OR REPLACE` herda grants — validado via `has_function_privilege('authenticated', ...)` antes do DROP. `GRANT EXECUTE` defensivo ainda adicionado à migration para runs limpos em novos ambientes.
- Invariantes estruturais podem ser substituídos por ausência física da entidade (Part 3 removeu `I_artifacts_frozen` porque DROP TABLE torna o invariante trivialmente satisfeito).

**Sessões**: p35 (20/Abr, Part 1+2), p37 (23/Abr, Part 3), p38 (23/Abr, Part 4). Council: data-architect (Option B Part 1 + 6 decisões B1-B6 em Part 4) + ux-leader (Opção C Fase 1 em Part 4) + code-reviewer (post-Part 4 findings) + platform-guardian (CONDITIONAL SAFE TO CLOSE).
- Migration `20260424070000` — saneamento + trigger de invariants
