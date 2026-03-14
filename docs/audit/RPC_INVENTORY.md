# W139 — RPC & Database Function Inventory

**Data:** 2026-03-14
**Método:** Cross-reference automatizado frontend grep → DB information_schema

---

## Resultado Principal

| Métrica | Valor |
|---------|-------|
| RPCs chamados pelo frontend | 117 |
| Funções no DB (public schema) | 263 (excl. pg_trgm) |
| RPCs chamados que NÃO existem no DB | **0** |
| Funções no DB sem chamada no frontend | **89** |

### Zero RPCs Quebrados

Todas as 117 chamadas `.rpc('nome')` encontradas no código fonte têm uma função correspondente no schema público do Supabase. **Nenhum RPC vai retornar 404 para o usuário.**

---

## Funções Órfãs no DB (89 funções sem chamada do frontend)

### Categoria 1: Triggers e Internal Helpers (não precisam de chamada frontend)

Estas são legítimas — triggers, computed columns, ou helpers internos:

| Função | Tipo |
|--------|------|
| `auto_publish_approved_article` | Trigger |
| `board_items_set_updated_at` | Trigger |
| `board_source_tribe_map_set_updated_at` | Trigger |
| `compute_legacy_role` / `compute_legacy_roles` | Backward-compat helper |
| `create_notification` | Internal helper (chamada por outros RPCs) |
| `current_member_tier_rank` | Internal helper |
| `decrypt_sensitive` / `encrypt_sensitive` | Internal helper |
| `detect_onboarding_overdue` | Cron/trigger |
| `enforce_board_item_source_tribe_integrity` | Trigger |
| `enforce_project_board_taxonomy` | Trigger |
| `enqueue_artifact_publication_card` | Trigger |
| `events_default_duration_actual` | Trigger |
| `has_min_tier` | RLS helper |
| `notify_on_assignment` | Trigger |
| `notify_on_curation_status_change` | Trigger |
| `notify_on_publication_insert` / `notify_on_publication_published` | Trigger |
| `publish_board_item_from_curation` | Trigger |
| `publish_comms_metrics_batch` | Internal |
| `refresh_cycle_tribe_dim` / `trigger_refresh_cycle_tribe_dim` | Materialized view refresh |
| `sync_attendance_points` / `sync_tribe_id_from_selection` | Internal sync |
| `analytics_is_leadership_role` / `analytics_member_scope` / `analytics_role_bucket` | Analytics helpers |
| `broadcast_count_today` | Internal helper |
| `can_manage_comms_metrics` / `can_manage_knowledge` / `can_read_internal_analytics` | RLS/permission helpers |
| `calculate_rankings` | Internal helper |
| `assign_curation_reviewer` / `set_curation_due_date` / `submit_for_curation` / `suggest_tags` | Internal curation helpers |
| `title_case` | Utility |
| Todas `*_set_updated_at` | Triggers |

### Categoria 2: Ingestion/Governance Pipeline (42 funções) — Backend Only

Estas são funções de um pipeline de ingestão e governança de dados que não tem UI frontend. São operadas via SQL direto ou webhook/cron:

| Prefixo | Quantidade | Propósito |
|---------|-----------|-----------|
| `admin_*_ingestion_*` | 22 | Pipeline de ingestão de dados |
| `admin_*_readiness_*` | 5 | Release readiness gates |
| `admin_*_remediation_*` | 3 | Remediação de anomalias |
| `admin_*_rollback_*` | 4 | Rollback de ingestão |
| `admin_*_provenance_*` | 3 | Verificação de proveniência |
| `exec_readiness_*` | 2 | SLO dashboard |
| `exec_remediation_*` | 1 | Efetividade de remediação |

**Recomendação:** P3 — Manter. Estas funções fazem parte de um pipeline de governança de dados projetado para operação via CLI/cron. Não precisam de UI.

### Categoria 3: Funções com Potencial de UI Futuro (16 funções)

| Função | Propósito | UI Candidata |
|--------|-----------|-------------|
| `admin_anonymize_member` | LGPD anonymization | /admin/settings |
| `admin_change_tribe_leader` | Change tribe leader | /admin/tribes |
| `admin_deactivate_member` | Deactivate member | /admin/index |
| `admin_deactivate_tribe` | Deactivate tribe | /admin/tribes |
| `admin_get_member_details` | Member detail view | /admin/member/[id] |
| `admin_list_members_with_pii` | PII-aware member list | /admin/index |
| `admin_manage_publication` | Publication CRUD | /publications |
| `admin_move_member_tribe` | Move member between tribes | /admin/tribes |
| `admin_remove_tribe_selection` | Remove tribe selection | /admin/tribes |
| `admin_update_board_columns` | Update board columns | /admin/board/[id] |
| `exec_all_tribes_summary` | All tribes summary | /admin/tribes |
| `get_evaluation_form` / `get_evaluation_results` | Selection evaluation | /admin/selection |
| `mark_interview_status` / `submit_interview_scores` / `schedule_interview` / `submit_evaluation` | Selection process | /admin/selection |
| `get_onboarding_dashboard` | Onboarding dashboard | /admin |
| `get_publication_detail` | Publication detail | /publications |
| `knowledge_*` (5 funções) | Knowledge management | Sem UI planejada |
| `kpi_summary` | KPI summary (replaced by exec_portfolio_health) | Deprecated |
| `platform_activity_summary` | Platform activity | /admin/analytics |

### Categoria 4: Deprecadas/Legacy (5 funções)

| Função | Razão |
|--------|-------|
| `comms_metrics_latest` | Substituída por `comms_metrics_latest_by_channel` |
| `exec_funnel_v2` | Versão anterior de `exec_funnel_summary` |
| `kpi_summary` | Substituída por `exec_portfolio_health` |
| `move_board_item_to_board` | Duplicata de `move_item_to_board` |
| `finalize_decisions` | Legado do processo seletivo v1 |

---

## Referências a Colunas Legadas

### Verificação: `.role` na tabela `members`

**Resultado: LIMPO.** Zero funções no DB referenciam `members.role` ou `v_caller.role` ou `v_member.role` (corrigido no W138).

### Colunas `role` existentes em tabelas (legítimas)

| Tabela | Coluna | Tipo | Status |
|--------|--------|------|--------|
| `board_item_assignments` | `role` | text | ✅ Legítimo (author, reviewer, etc.) |
| `member_attendance_summary` | `role` | text | ⚠️ View — pode referenciar coluna dropada |
| `project_memberships` | `role` | text | ✅ Legítimo (member role in project) |
| `selection_committee` | `role` | text | ✅ Legítimo (lead, member, observer) |

**Ação necessária:** Verificar se a view `member_attendance_summary` referencia `members.role` (dropada). Se sim, atualizar para `operational_role`.
