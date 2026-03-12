# RPC Registry

Audit of Supabase RPC functions: unused definitions and duplicate migrations.

Last updated: 2026-03-12

---

## RPCs with No Direct Frontend Call-Site

RPCs that are defined in migrations but have no `sb.rpc('...')` call in `src/`.

| RPC Name | Defined In | Status | Notes |
|---|---|---|---|
| `get_curation_cross_board` | `20260317100000_board_engine_rpcs.sql` | **Deprecated** | Returns ALL board items — CuratorshipBoardIsland uses `list_curation_pending_board_items` instead. Do not delete (may serve future admin dashboard). |
| `list_webinars` | `20260309140000_webinars_and_rpc_security.sql` | **Deprecated** | Webinars page uses `get_events_with_attendance`. Superseded. |
| `platform_activity_summary` | `20260312030000_list_volunteer_applications_rpc.sql` | **Deprecated** | No consumer exists. Candidate for removal next cycle. |
| `publish_board_item_from_curation` | `20260315000007_curation_workflow_board_items.sql` | **Internal** | Called by `submit_curation_review` (line 136 of `20260316140000`). Not orphaned — do not remove. |
| `kpi_summary` | `20260309001000_kpi_summary_rpc.sql` | **Active** | Wired to `KpiSection.astro` (commit `7ecd314`). Shows live progress on home page. |

> **Policy**: Deprecated RPCs are kept in the database but not maintained. They may be dropped in a future migration consolidation. Internal RPCs must not be removed without checking all SQL callers.

---

## Duplicate RPC Definitions

RPCs that are defined via `CREATE OR REPLACE FUNCTION` in multiple migrations.
The **authoritative** definition is the latest migration (last one applied wins).

| RPC Name | Migrations (chronological) | Authoritative Migration |
|---|---|---|
| `move_board_item` | `20260312000000_project_boards.sql`, `20260314170000_global_publications_and_operational_board_scope.sql`, `20260317100000_board_engine_rpcs.sql` | `20260317100000_board_engine_rpcs.sql` |
| `list_board_items` | `20260312000000_project_boards.sql`, `20260315000007_curation_workflow_board_items.sql` | `20260315000007_curation_workflow_board_items.sql` |
| `list_tribe_deliverables` | `20260309030000_tribe_deliverables.sql`, `20260309140000_webinars_and_rpc_security.sql` | `20260309140000_webinars_and_rpc_security.sql` |
| `upsert_tribe_deliverable` | `20260309040000_deliverable_crud_rpcs.sql`, `20260309070000_admin_global_access_and_timelock_bypass.sql` | `20260309070000_admin_global_access_and_timelock_bypass.sql` |
| `select_tribe` | `20260309010000_select_tribe_deadline_check.sql`, `20260309070000_admin_global_access_and_timelock_bypass.sql` | `20260309070000_admin_global_access_and_timelock_bypass.sql` |
| `list_curation_pending_board_items` | `20260315000007_curation_workflow_board_items.sql`, `20260316140000_curation_review_log_and_sla.sql` | `20260316140000_curation_review_log_and_sla.sql` |
| `list_curation_board` | `20260311000000_curatorship_kanban_rpc.sql`, `20260311030000_fix_curation_board_columns.sql`, `20260311040000_fix_curation_board_suggest_tags_cast.sql` | `20260311040000_fix_curation_board_suggest_tags_cast.sql` |

> **Action**: Earlier definitions are superseded and harmless (each `CREATE OR REPLACE` overwrites the previous). No cleanup required unless consolidating migrations.
