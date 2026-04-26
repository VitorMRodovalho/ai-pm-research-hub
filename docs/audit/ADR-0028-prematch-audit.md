# ADR-0028 Phase 1 Prematch Audit — Pacote M

**Date**: 2026-04-26 (p64 session)
**Author**: Claude (autonomous Phase 1 audit per ADR-0028 §"Implementation phases")
**Status**: COMPLETE — surfaces unexpected state requiring PM checkpoint before Phase 2

---

## TL;DR — MAJOR FINDING

The original ADR-0028 scope (30 admin_* + 7 extended exec_* = 37 fns)
assumed all fns are **live production code** with cron/EF callers
preserved by the service-role-bypass adapter. Phase 1 audit found that
**32 of 37 fns (86%) reference one or more tables that DO NOT EXIST
in the live database**.

| Status | Count | Description |
|---|---|---|
| **OK** | 5 | All referenced tables exist; fn would execute end-to-end |
| **PARTIAL_BROKEN** | 4 | Some refs OK, some MISSING; fn errors at runtime if missing branch hit |
| **FULLY BROKEN** | 28 | All primary write/read targets MISSING; fn cannot execute body |

The substrate tables (`ingestion_apply_locks`, `ingestion_runs`,
`ingestion_alerts`, `ingestion_alert_remediation_*`,
`ingestion_rollback_*`, `release_readiness_history`,
`release_readiness_decisions`, `governance_bundle_snapshots`,
`ingestion_provenance_signatures`, `notion_import_staging`,
`legacy_tribes`, `legacy_tribe_board_links`, `ingestion_batches`,
`partner_governance_metrics`) were created in migrations dated
20260308–20260314 but no longer exist in the live database. No DROP
TABLE migration was found for them in `supabase/migrations/`,
suggesting they were dropped via Supabase SQL editor or `execute_sql`
DDL — exactly the drift pattern documented in
`docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md`.

`mcp_usage_log` shows **zero successful calls** to any of the 37 fns
in the last 90 days, and **zero pg_cron jobs** are scheduled to call
them. Edge Functions in `supabase/functions/` reference none of them.
The only callsite is `src/lib/database.gen.ts` — auto-generated TS
types pulled from `pg_proc`, with no runtime dependency.

**Conclusion**: 32 of 37 fns are dead code referencing non-existent
substrate. The remaining 5 OK + 4 PARTIAL_BROKEN may or may not be in
active use (no telemetry confirms either way).

---

## Per-fn classification — Batch 1 (30 admin_* fns)

### OK (5 fns) — substrate exists, fn fully executable

| Function | Target table | Notes |
|---|---|---|
| `admin_capture_data_quality_snapshot` | data_quality_audit_snapshots | INSERT row, actor_id nullable |
| `admin_check_ingestion_source_timeout` | ingestion_source_sla | Pure read |
| `admin_set_ingestion_source_sla` | ingestion_source_sla | UPSERT, updated_by nullable |
| `admin_set_release_readiness_policy` | release_readiness_policies | UPSERT, updated_by nullable |
| `admin_get_ingestion_source_policy` | ingestion_source_controls | Pure read |

### PARTIAL_BROKEN (4 fns) — mixed working/broken refs

| Function | Tables referenced | Risk |
|---|---|---|
| `admin_release_readiness_gate` | ingestion_alerts (MISSING) + release_readiness_policies (OK) + data_quality_audit_snapshots (OK) | INSERT ingestion_alerts will error |
| `admin_resolve_remediation_action` | ingestion_alerts (MISSING) + remediation_escalation_matrix (OK) | UPDATE ingestion_alerts will error |
| `admin_data_quality_audit` | tribes (OK) + project_boards (OK) + initiatives (OK) + tribe_lineage (OK) + legacy_tribes (MISSING) + legacy_tribe_board_links (MISSING) | SELECT from missing legacy tables errors |
| `admin_run_post_ingestion_chain` | Orchestrator: calls admin_run_post_ingestion_healthcheck (BROKEN) + admin_capture_data_quality_snapshot (OK) + admin_release_readiness_gate (PARTIAL) | First call fails |

### FULLY BROKEN (21 fns) — primary substrate missing

| Function | Missing target table |
|---|---|
| admin_acquire_ingestion_apply_lock | ingestion_apply_locks |
| admin_release_ingestion_apply_lock | ingestion_apply_locks |
| admin_register_ingestion_run | ingestion_run_ledger |
| admin_complete_ingestion_run | ingestion_run_ledger |
| admin_sign_ingestion_file_provenance | ingestion_provenance_signatures |
| admin_verify_ingestion_provenance_batch | ingestion_provenance_signatures |
| admin_raise_provenance_anomaly_alert | ingestion_alerts |
| admin_update_ingestion_alert_status | ingestion_alerts |
| admin_run_ingestion_alert_remediation | ingestion_alerts + alert_remediation_runs + alert_remediation_rules |
| admin_set_ingestion_alert_remediation_rule | ingestion_alert_remediation_rules |
| admin_plan_ingestion_rollback | ingestion_rollback_plans |
| admin_approve_ingestion_rollback | ingestion_rollback_plans |
| admin_execute_ingestion_rollback | ingestion_rollback_plans |
| admin_simulate_ingestion_rollback | ingestion_rollback_plans |
| admin_append_rollback_audit_event | rollback_audit_events |
| admin_record_release_readiness_decision | release_readiness_history |
| admin_check_readiness_slo_breach | ingestion_alerts + release_readiness_history |
| admin_run_dry_rehearsal_chain | Orchestrator: calls admin_data_quality_audit (PARTIAL) + admin_release_readiness_gate (PARTIAL) + admin_check_ingestion_source_timeout (OK) — partial-at-best |
| admin_capture_governance_bundle_snapshot | governance_bundle_snapshots |
| admin_run_post_ingestion_healthcheck | ingestion_alerts |
| admin_suggest_notion_board_mappings | notion_import_staging |

---

## Per-fn classification — Batch 2 (7 extended exec_* fns)

ALL Batch 2 fns are FULLY or PARTIALLY BROKEN — every one references
at least one missing table.

| Function | Missing target tables |
|---|---|
| exec_governance_export_bundle | (orchestrator — calls broken exec_partner_*) |
| exec_partner_governance_summary | ingestion_alerts + ingestion_batches |
| exec_partner_governance_scorecards | ingestion_batches |
| exec_partner_governance_trends | ingestion_alerts + release_readiness_history |
| exec_readiness_slo_by_source | ingestion_batches |
| exec_readiness_slo_dashboard | release_readiness_history |
| exec_remediation_effectiveness | ingestion_alert_remediation_runs |

---

## Privilege expansion check (V3 set vs V4 manage_platform set)

For Batch 1 fns ONLY (Batch 2 is moot if dropped, see Pivot Options):

```sql
WITH v3_broad AS (
  SELECT id FROM members WHERE is_active = true AND (
    is_superadmin OR operational_role IN ('manager','deputy_manager') OR ('co_gp' = ANY(designations))
  )
),
v4 AS (
  SELECT id FROM members WHERE is_active = true AND can_by_member(id, 'manage_platform') = true
)
-- v3 GAIN: 0 members, LOSE: 0 members. Sets are IDENTICAL = {Fabricio Costa, Vitor Maia Rodovalho}.
```

**Confirmed**: Batch 1 V3-set vs V4-set diff is empty. Conversions
would have been clean for the 5 OK + 4 PARTIAL fns. The 21 FULLY
BROKEN fns have the same property but it doesn't matter — they cannot
execute.

---

## Actor_id NULL handling strategy (only relevant if convert path picked)

For the 5 OK + 4 PARTIAL fns that have v_caller.id refs in INSERT/UPDATE:

| Function | Column referenced | Nullable | Strategy |
|---|---|---|---|
| admin_capture_data_quality_snapshot | data_quality_audit_snapshots.created_by (uuid, nullable) | YES | `COALESCE(v_caller_id, NULL::uuid)` (= just NULL when service_role) |
| admin_set_ingestion_source_sla | ingestion_source_sla.updated_by (uuid, nullable) | YES | Same |
| admin_set_release_readiness_policy | release_readiness_policies.updated_by (uuid, nullable) | YES | Same |
| admin_release_readiness_gate (PARTIAL) | data_quality_audit_snapshots.created_by + ingestion_alerts.created_by (table missing — moot) | YES | Same for OK col |
| admin_resolve_remediation_action (PARTIAL) | ingestion_alerts.* (missing — moot) | n/a | n/a |
| admin_check_ingestion_source_timeout (OK) | (read-only) | n/a | None |
| admin_get_ingestion_source_policy (OK) | (read-only) | n/a | None |

**All actor columns in existing tables are nullable** — confirmed via
`information_schema.columns` query. The current V3 code already passes
NULL when service_role calls (because `get_my_member_record()` returns
NULL → `v_caller.id` = NULL → INSERT NULL). Adapter pattern preserves
this behavior identically.

---

## PM Pivot Options

**This is the PM checkpoint** mandated by ADR-0028 §"Phase 1 →
Phase 2" gate. Three viable paths:

### Option P1 — Full V4 conversion as planned (37 fns)

Convert all 37 fns to V4 adapter pattern regardless of dead-code
status. Pros: closes the V3 surface entirely (Phase B'' jumps to 91/246
= 37%); preserves work substrate intact for future restore. Cons:
~450 lines of mechanical migration churn for code that nobody calls
and 86% of which cannot execute even if called. Pacote M completes as
originally scoped (~6h).

### Option P2 — DROP all 37 dead-code fns

Drop the 37 fns as orphan code (no tables, no callers). Pros: cleanest
— closes V3 surface AND the dead-code drift surface in one move; less
maintenance burden going forward; subtracts 37 fns from the 246
denominator → Phase B'' true progress jumps without conversion work.
Cons: loses the substrate if someone wants to restore the ingestion
subsystem later (would need to re-create from migration files); does
not preserve the V4 cleanup pattern in the codebase.

### Option P3 — Per-fn classify + split

- **Convert 5 OK fns** to V4 adapter (real-work conversion, low risk).
- **Drop 28 BROKEN + 4 PARTIAL fns** as orphan dead code.
- Net: Phase B'' +5 conversions + 32 fns removed from V3 surface.
- ADR-0028 amends to "5 fns scope" + new ADR or addendum captures
  drop list with rationale.
- ~3-4h work (less than P1, more than P2).

### Option P4 — Investigate first

Pause Pacote M. Invoke security-engineer + accountability-advisor
agents to:
1. Verify whether the table drops were intentional (a tracker decision
   I missed) or accidental (DDL drift from execute_sql usage).
2. Determine whether the ingestion subsystem is on roadmap for
   restoration or formally retired.
3. Consult ADR-0023 or any retired-system documentation.

Then revisit with informed pivot.

---

## My recommendation

**Option P3 — per-fn classify + split** is the correct technical move:
- Rewards the 5 fns that work with proper V4 conversion (preserves
  the work pattern's integrity).
- Removes the 32 dead-code fns from the V3 surface without
  preservation cost (they cannot run; restoring them requires
  recreating tables anyway, at which point a fresh V4 fn is the right
  artifact).
- Shrinks the 246-denominator by 32, so Phase B'' tally bumps without
  artificial inflation: 61/246 → 66/214 (~30.8% true progress, with
  reduced scope).
- ~4h work in this session (single migration with mixed CREATE OR
  REPLACE + DROP statements + COMMENT additions for the 5 V4 fns).

**Caveat**: P3 commits to dropping work substrate. If PM is uncertain
about the ingestion subsystem's future, **P4 (investigate first)** is
the safer move — it costs ~30min of agent consultation and zero
production risk. If the subsystem is genuinely retired, P3 confirmed
is the technical answer; if it might be restored, P1 (conversion-only)
preserves optionality at modest cost.

DO NOT recommend P1 as default — it spends ~6h of session time on
mechanical churn for code that does not run, with no test that can
verify the conversion (no telemetry, no callers).

DO NOT recommend P2 as default — too aggressive without per-fn
classification; the 5 OK fns deserve preservation through proper V4
conversion to stay alive in the codebase even if nobody calls them
right now.

---

## Next steps (per PM decision)

- **If P1**: proceed with originally-planned Pacote M migration covering all 37 fns.
- **If P2**: write `pacote_m_drop_dead_admin_fns.sql` migration; update ADR-0028 status to "Superseded (dead-code dropped)"; add ADR-0029 documenting the drop rationale.
- **If P3 (recommended)**: write `pacote_m_split_5convert_32drop.sql`; update ADR-0028 with revised 5-fn scope; ADR-0029 documents the 32 drops with table-missing evidence; commit with explicit per-fn rationale.
- **If P4**: spawn security-engineer + accountability-advisor agents with this audit doc as input; resume Pacote M next session post-investigation.

---

## Evidence sources

- `pg_proc` query for SECDEF fns with `auth.role() = 'service_role'` pattern (37 fns surfaced).
- `information_schema.tables` query for substrate existence (32 of ~14 referenced tables MISSING).
- `cron.job` query for pg_cron schedules referencing the 37 fns (0 jobs found).
- `mcp_usage_log` query for last 90 days (0 rows for any of the 37 fns).
- `grep -r` over `supabase/functions/` (0 EF references; only `src/lib/database.gen.ts` auto-generated types).
- `grep -r DROP TABLE` over `supabase/migrations/` (0 explicit drops found — confirms execute_sql/dashboard DDL drift).
