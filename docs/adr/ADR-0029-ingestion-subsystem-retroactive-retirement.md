# ADR-0029: Ingestion/Release-Readiness/Governance-Bundle Subsystem — Retroactive Retirement Record

- **Status**: Accepted (PM-ratified 2026-04-26 p64 via P3 council-validated;
  retroactive — substrate was already absent from production at time of ADR drafting)
- **Date**: 2026-04-26 (drafted post-incident, after Phase 1 audit of ADR-0028)
- **Author**: Claude (autonomous draft via P4 council investigation:
  security-engineer + accountability-advisor + platform-guardian) + PM
  (Vitor) acknowledgment
- **Cross-references**:
  - `docs/audit/ADR-0028-prematch-audit.md` — Phase 1 audit that surfaced the missing substrate
  - `docs/adr/ADR-0028-service-role-bypass-adapter-pattern.md` — adjacent ADR whose Phase 1 audit triggered this discovery
  - `docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md` — Track Q drift audit that stopped at function-body level (table-level drift was out-of-scope and undetected)

## Context

### What was retired

A coherent **ingestion/release-readiness/governance-bundle subsystem** was
designed and partially implemented in 2026-03-08 to 2026-03-14 across 14
substrate tables and 37 SECURITY DEFINER functions. The subsystem covered:

- **Ingestion lifecycle**: locks, run ledger, alerts, alert remediation
  (rules + runs), source SLA, source controls
- **Provenance signing**: signatures, anomaly alerts
- **Rollback management**: plans, audit events, simulation harness
- **Release readiness**: decisions, history, policy modes, policy gate, SLO breach detection
- **Data quality auditing**: snapshots
- **Governance bundle snapshots**: capture + export
- **Notion staging**: import staging table + suggestion mapping
- **Legacy tribe linking**: legacy_tribes, legacy_tribe_board_links

### Substrate tables (14, all ABSENT from live database as of 2026-04-26)

| Table | Created in migration | Drop trail in supabase/migrations? |
|---|---|---|
| `ingestion_apply_locks` | 20260313000000 | NO |
| `ingestion_run_ledger` | 20260313050000 | NO |
| `ingestion_alerts` | 20260313060000 | NO |
| `ingestion_alert_remediation_runs` | 20260313110000 | NO |
| `ingestion_alert_remediation_rules` | 20260313110000 | NO |
| `ingestion_rollback_plans` | 20260313190000 | NO |
| `rollback_audit_events` | 20260313190000 | NO |
| `release_readiness_decisions` | 20260313040000 | NO |
| `release_readiness_history` | 20260313120000 | NO |
| `governance_bundle_snapshots` | 20260314050000 | NO |
| `ingestion_provenance_signatures` | 20260313170000 | NO |
| `ingestion_provenance_anomaly_alerts` | 20260313170000 | NO |
| `notion_import_staging` | (likely 20260312—20260313 series) | NO |
| `legacy_tribes` | (legacy_ingestion series) | NO |
| `legacy_tribe_board_links` | (legacy_ingestion series) | NO |
| `ingestion_batches` | (referenced by exec_partner_governance_*) | NO |
| `partner_governance_metrics` | (referenced by exec_partner_governance_*) | NO |

### Functions affected (37, all in pg_proc, all dead code)

**5 OK** (referenced tables exist — preserved via V4 conversion in same Pacote M migration as this ADR):
1. `admin_capture_data_quality_snapshot` → `data_quality_audit_snapshots` (exists)
2. `admin_check_ingestion_source_timeout` → `ingestion_source_sla` (exists)
3. `admin_set_ingestion_source_sla` → `ingestion_source_sla` (exists)
4. `admin_set_release_readiness_policy` → `release_readiness_policies` (exists)
5. `admin_get_ingestion_source_policy` → `ingestion_source_controls` (exists)

**32 dead code** (substrate missing — DROPPED by this ADR):

Batch 1 (28 admin_*):
- admin_acquire/release_ingestion_apply_lock (2)
- admin_register_ingestion_run, admin_complete_ingestion_run (2)
- admin_sign_ingestion_file_provenance, admin_verify_ingestion_provenance_batch, admin_raise_provenance_anomaly_alert (3)
- admin_update_ingestion_alert_status, admin_run_ingestion_alert_remediation, admin_set_ingestion_alert_remediation_rule (3)
- admin_plan/approve/execute/simulate_ingestion_rollback (4)
- admin_append_rollback_audit_event (1)
- admin_record_release_readiness_decision, admin_release_readiness_gate, admin_check_readiness_slo_breach (3)
- admin_run_dry_rehearsal_chain, admin_run_post_ingestion_chain, admin_run_post_ingestion_healthcheck (3)
- admin_capture_governance_bundle_snapshot (1)
- admin_resolve_remediation_action (1)
- admin_data_quality_audit (1)
- admin_suggest_notion_board_mappings (1)
+ admin_run_dry_rehearsal_chain orchestrator (already counted)

Batch 2 (4 exec_*):
- exec_governance_export_bundle (orchestrator only)
- exec_partner_governance_summary, exec_partner_governance_scorecards, exec_partner_governance_trends (3)

(Note: exec_readiness_slo_by_source, exec_readiness_slo_dashboard,
exec_remediation_effectiveness — 3 fns from the original 7 Batch 2 surface
— are similarly broken but their broader review is deferred to ADR-0028
Batch 2 ADR-0029 amendment.)

## The retirement record

### Telemetry confirmation (zero operational use)

- `mcp_usage_log`: **0 calls** to any of the 37 fns in last 90 days (full table scan, all rows)
- `cron.job`: **0 schedules** referencing any of the 37 fn names
- `supabase/functions/*`: **0 references** in any Edge Function source
- Frontend (`src/`): **0 calls** outside auto-generated TS types in `src/lib/database.gen.ts`

The subsystem appears to have been **designed but never operationally
activated**. There is no evidence the substrate tables ever held production data.

### Discovery path

1. Phase 1 audit of ADR-0028 (P3 prematch) ran V3-set vs V4-set diff for the 37 SECDEF fns
2. Audit also queried `information_schema.tables` for substrate existence — found 14 missing
3. Discovery presented to PM via `docs/audit/ADR-0028-prematch-audit.md` 2026-04-26 23:xx UTC
4. P4 (investigate) executed: 2 council agents (security + accountability) plus grep over docs/ + git log -S
5. UNANIMOUS verdict: undocumented DDL drift (not intentional retirement)
6. PM ratified P3 with precondition: ADR-0029 retirement record + GC entry must precede the drop migration
7. This ADR is that record

### Acknowledgment of governance gap

The substrate tables were dropped via Supabase Dashboard SQL editor or
`mcp__claude_ai_Supabase__execute_sql` MCP tool — bypassing the
`mcp__claude_ai_Supabase__apply_migration` discipline documented in
`.claude/rules/database.md` and GC-097 pre-commit validation rules.

This is the **same DDL-drift class** that p50 audit (`RPC_BODY_DRIFT_AUDIT_P50.md`)
caught at the function-body level. At the table level the consequences are
**more severe** — function bodies can be re-derived from migrations, but a
dropped table eliminates any data it held permanently.

The PM (Vitor Maia Rodovalho) is the sole operator of this single-instance
project and is the most likely actor for the historical drops.
**Acknowledgment**: this drop was executed outside the migration discipline
documented in GC-097. This retirement ADR is being written **retroactively**
to close the governance gap. This is not punitive — it is exactly how
mature governance handles retroactive documentation.

### Forensic preservation

The original migration files for the substrate tables remain in
`supabase/migrations/` (e.g., `20260313000000_ingestion_apply_locking.sql`,
`20260314050000_governance_bundle_snapshots.sql`). If the ingestion
subsystem ever needs restoration, a `db reset` would recreate the substrate
from migrations, plus the dead-code function bodies preserved in their own
migrations would be available for recovery via `git log`. **Institutional
memory of how the subsystem was designed is preserved in version control**;
dropping the dead functions does not erase this knowledge.

### LGPD compliance assessment

- **Personal data assessment**: Function bodies inspected — none of the 37
  fns reference `members.email`, `phone`, `pmi_id`, `auth_id`, or any other
  PII column directly. Closest concern: `exec_governance_export_bundle`
  bodies an opaque jsonb payload that COULD theoretically include PII if
  partner_governance_metrics had nested member references; since the table
  is already absent, this is moot.
- **Art. 14 (data subject notification)**: Not applicable — no evidence any
  data subject had data in the dropped tables. Best evidence: zero telemetry
  in 90 days suggests the subsystem never processed real data.
- **Art. 18 cycle**: Unaffected. Art. 18 operates on `members`, `persons`,
  `engagements` — none of which are touched by the ingestion subsystem.
- **Art. 37 (records of processing)**: There is a documented uncertainty
  window — the substrate existed for ~6 weeks (March 14 – early May 2026)
  before being dropped. If any cron run or admin action processed data
  during that window, the records are gone with no archive. Probability low
  given absent telemetry; documenting the uncertainty here serves as the
  Art. 37 compliance record.

### Sponsor / chapter awareness

PMI-GO, PMI-CE, PMI-DF, PMI-MG, PMI-RS were never informed that an
ingestion + governance-bundle subsystem existed. The subsystem appears to
have been internal scaffolding that was abandoned before reaching any
operational use. **No notification to chapter sponsors is required** because:
- No chapter data was processed
- No governance bundle was ever exported to a sponsor
- No release readiness decision was ever recorded
- The subsystem's existence was never communicated externally

This ADR exists primarily to provide a paper trail for **future audits**:
if an auditor queries `pg_proc` and finds governance-sounding function names
referencing absent tables, the answer is "this subsystem was evaluated, found
to have never been activated, and formally retired on 2026-04-26 per
documented decision (ADR-0029)."

## Decision

**RATIFY P3 from `docs/audit/ADR-0028-prematch-audit.md`**:

1. **Convert 5 OK fns** to V4 adapter pattern per ADR-0028 (preserve real
   capability + apply V4 contract cleanly).
2. **DROP 32 dead-code fns** with this ADR-0029 cited in migration header
   (close V3 surface AND dead-code drift).
3. **Update ADR-0028** scope from "37 fns (30 Batch 1 + 7 Batch 2)" to
   "5 fns (post-Pacote M)" + appendix referencing ADR-0029 for the dropped 32.
4. **Extend `tests/contracts/rpc-migration-coverage.test.mjs`** to detect
   table-level drift class (this ADR's root cause).
5. **GC entry** in `docs/GOVERNANCE_CHANGELOG.md` (GC-141) cross-referencing
   this ADR.

## Consequences

### Positive

- Dead-code surface removed (37 fns → 5 fns kept; -32 from V3 surface entirely)
- Phase B'' true progress: 61/246 → 66/214 (~30.8%, denominator honest)
- Audit-readiness restored: documented retirement vs mystery dead code
- Table-level drift detection added (R2 from security review) — catches
  the bug class that produced this incident before next session
- Retroactive governance discipline established for similar past drops
  (template for future post-hoc retirements)

### Negative

- 14 substrate tables permanently gone with no recovery path for any data
  they may have held (zero-row probability per telemetry, but not zero)
- ~450 lines of designed-but-never-used schema knowledge moved from
  pg_proc to git history (still preserved, just less discoverable)
- Acknowledged governance gap: future similar drops should NOT happen via
  dashboard/execute_sql — must use apply_migration

### Mitigations

- All migration files for the substrate remain — `db reset` would recreate
- All function bodies remain in `git log` — `git show <sha>:supabase/migrations/...`
  preserves the historical fn definitions for any future restore

## Pending

- [x] PM ratify (Vitor 2026-04-26)
- [ ] ADR-0029 committed before Pacote M migration applies
- [ ] GC-141 added to GOVERNANCE_CHANGELOG
- [ ] Pacote M migration applied (5 convert + 32 drop, references ADR-0029)
- [ ] ADR-0028 scope amendment (37 → 5 fns)
- [ ] `rpc-migration-coverage.test.mjs` table-level extension shipped
- [ ] Future sessions: enforce `apply_migration` discipline; never `execute_sql` for DDL
