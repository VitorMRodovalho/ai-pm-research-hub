# RPC body drift audit — p50 (Track Q)

**Date:** 2026-04-24
**Trigger:** p49 discovery that `import_vep_applications` live body had drifted from every migration file with no migration capturing the actual deployed state.
**Scope:** Phase 1 (orphan discovery) + sample drift confirmation. Phases 2-3 (full body diff + cleanup) deferred.

## Methodology

1. Enumerated all 642 functions in the `public` schema via `pg_proc`.
2. Filtered out 37 extension-provided functions (`pg_trgm`, `gtrgm_*`, `similarity*`, `word_similarity*`, `set_limit`, `show_*`, `strict_*`, `decrypt_sensitive`, `encrypt_sensitive`).
3. Checked each remaining 605 project functions against `supabase/migrations/*.sql` for any line matching `CREATE [OR REPLACE] FUNCTION [public.]<name>(`.
4. Bucketed by migration-touch count: 0 (orphan) / 1 (single capture) / ≥2 (multi-touch — drift risk grows with count).
5. Sample-checked one top-touched function (`exec_portfolio_health`, 9 migrations) for actual body drift via normalized-prosrc hash comparison.

## Findings

### Coverage distribution (605 project functions)

| Bucket | Count | Risk |
|---|---|---|
| 0 migrations (orphan) | **90** (14.9%) | Highest — function exists in DB but no migration defines it. Cannot be reproduced from migrations alone. |
| 1 migration | 313 (51.7%) | Low — single canonical capture. |
| 2 migrations | 95 | Medium — successive `CREATE OR REPLACE` rounds increase divergence chance. |
| 3 migrations | 53 | Medium-high. |
| 4 migrations | 34 | High. |
| 5+ migrations | 20 | Very high — `import_vep_applications` (touched 6+) and `exec_portfolio_health` (touched 9) both confirmed drifted. |

### Top-touched functions (5+ migrations)

```
9  exec_portfolio_health           ← drift CONFIRMED
8  curate_item                     ← already known to have ADR-0011 drift (p38 backlog)
7  check_schema_invariants
7  get_attendance_grid
7  sign_volunteer_agreement
6  _can_sign_gate
6  create_event
6  exec_tribe_dashboard
6  get_admin_dashboard
6  move_board_item
5  admin_anonymize_member
5  detect_operational_alerts
5  get_board
5  get_events_with_attendance
5  get_member_attendance_hours
```

### Confirmed drift sample

**`public.exec_portfolio_health(text)`**
- Live `prosrc` length: 4366 chars
- Latest migration body (`20260320100006_fix_kpi_round_decimals.sql`): 5419 chars
- Normalized-whitespace hash: live `2f7b0570…` vs migration `be7df82d…` — divergent
- Body tails are identical (`RETURN v_result; END;`) → drift is mid-body, not catastrophic, but the function deployed today does not match what re-running migrations would produce.

### Orphan breakdown by category

90 orphans exist in production with no migration capture. Distribution:

- **31 readers** (`get_*`): annual KPIs, application interviews, board tags/timeline, partner CRUD readers, selection cycles/rankings/committee, sustainability projections, cron status, governance stats, blog likes, my-* readers (selection result, tasks, PII access log).
- **23 writers** (mutation surfaces): `add_partner_attachment/interaction`, `delete_cost_entry/revenue_entry/partner_attachment/my_personal_data`, `update_publication_submission/cpmai_progress/kpi_target/my_profile/sustainability_kpi`, `submit_cpmai_mock_score`, `enroll_in_cpmai_course`, `enrich_applications_from_csv`, `complete_onboarding_step`, `recalculate_cycle_rankings`, `publish_comms_metrics_batch`, `set_progress`, `toggle_blog_like`, `add_publication_submission_author`, `remove_publication_submission_author`. **Highest concern** — these mutate state under SECDEF; no migration reviewed/captured.
- **5 admin readers/writers**: `admin_force_tribe_selection`, `admin_generate_volunteer_term`, `admin_get_tribe_allocations`, `admin_manage_board_member`, `admin_remove_tribe_selection`.
- **30 other**: triggers (`auto_*`, `trg_set_updated_at`), authority cache helpers (`compute_legacy_role[s]`, `current_member_tier_rank`, `can_manage_knowledge`), knowledge search RPCs (5), historical importers (`import_historical_evaluations/interviews`, `import_leader_evaluations`), privacy gates (`accept_privacy_consent`, `check_my_privacy_status/tcv_readiness`, `mark_my_data_reviewed`), `handle_new_user`, `issue_certificate`, `log_pii_access`, `mark_member_excused`, `preview_gate_eligibles`, `title_case`, `increment_blog_view`, exec dashboard helper (`exec_cert_timeline`), `compute_application_scores`, `calc_trail_completion_pct`.

A few have indirect references (e.g., `compute_legacy_role` is *referenced* from 5 migrations but *defined* in zero) — meaning later migrations call a function whose body lives only in DB.

## Risk assessment

**Why this matters:**

1. **Reproducibility:** A clean re-deploy from `supabase db reset --linked` (or onto a fresh project) would produce a database missing 90 functions and with bodies divergent from production for an unknown subset. Migration-driven re-deploy is currently unsafe.
2. **Code review:** Future edits to drifted functions can't be reasoned about by reading the latest migration — the migration reflects an obsolete body. p49's `import_vep_applications` fix only worked because we pulled `pg_get_functiondef` from live and rebuilt the migration around it.
3. **Audit trail:** Behavior changes shipped via direct DB edits (psql, Supabase dashboard, MCP `execute_sql`) leave no commit history. LGPD Art. 37 / Art. 18 controls assume change history is auditable.
4. **Confidence in test coverage:** Contract tests like `tests/contracts/rpc-v4-auth.test.mjs` parse migrations as the source of truth. A drifted function's new behavior is invisible to those tests.

**Why this happened:**

Most likely sources of out-of-band changes:
- Direct edits via Supabase dashboard SQL editor during incident response.
- `mcp__supabase__execute_sql` invocations of `CREATE OR REPLACE FUNCTION` that bypassed `apply_migration`.
- Pre-migration-discipline era (before V4 / ADR-0012) where ad-hoc `psql` patches were the norm.

## Recommended remediation (deferred — not p50 scope)

### Phase A — Orphan capture (~6-10h)

For each of the 90 orphans:

1. `pg_get_functiondef` to dump current body.
2. Group into thematic recovery migrations (e.g., `20260515010000_orphan_recovery_partner_writers.sql`, `20260515020000_orphan_recovery_get_readers.sql`, etc.) — 5-10 migrations total.
3. Add a header comment explaining the function is being captured-as-of-today and any review notes.
4. Run pre-commit: invariants + tests + smoke spot-check on 1-2 from each batch.
5. Mark applied via `supabase migration repair --status applied`.

Output: every public function has at least one migration that defines it; `db reset` produces production-equivalent schema.

### Phase B — Multi-migration drift diff (~12-20h, batch over 2-3 sessions)

For the 202 multi-migration functions, compute live-vs-latest-migration normalized-body hash. Functions with mismatch get either:

a. A drift-correction migration that supersedes prior CREATE OR REPLACE blocks with the live body (preserves production behavior, captures drift).
b. Or, if the live drift is itself a regression vs the migration, a fix migration that restores the migration intent (this is the rarer case; example: live state is missing a fix that was supposed to ship).

Each function diff requires 5-15 minutes of judgment call, plus migration write + apply + verify. Realistic batch: 20-30 functions/session.

### Phase C — Drift prevention (~2-4h)

1. Add a contract test that fails if any public function in `pg_proc` has zero `CREATE [OR REPLACE] FUNCTION` matches in `supabase/migrations/*.sql`. Catches future orphans at PR time.
2. Optionally add a CI step that hashes live function bodies against latest-migration bodies and warns on divergence (heavyweight; might wait until Phase A+B settle).
3. Update `.claude/rules/database.md` to prohibit `execute_sql` for DDL — only `apply_migration` writes that auto-create migration files.
4. Audit existing `mcp__supabase__execute_sql` callsites in scripts/ for anything that could leak DDL.

## Decisions surfaced (PM input needed)

1. **Scope timing for Phase A**: dedicated session in p51, or interleave with feature work? Recommendation: dedicated, because the recovery migrations are mechanical and 6-10h benefits from continuous focus.
2. **Phase B prioritization**: do the 20 high-touch functions first (5+ migrations each, where drift is likeliest), or do all 202 chronologically? Recommendation: high-touch first, then sample the rest until the drift rate drops below ~10% to call it.
3. **Phase C contract test**: add now (before remediation) to prevent regression while orphan list is stable, or after Phase A so the test can pass cleanly? Recommendation: add now in **warn mode** (failing assertion that's expected to fail until A+B complete), flip to hard-fail after.

## Files touched in p50 Track Q

None in production. This is a discovery-only session. Audit data lives in:
- `docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md` (this doc)
- `/tmp/p50_func_list.txt` (605 project function names — ephemeral)
- `/tmp/p50_coverage.tsv` (per-function migration count — ephemeral)
- `/tmp/p50_orphans.txt` (90 orphan names — ephemeral)
