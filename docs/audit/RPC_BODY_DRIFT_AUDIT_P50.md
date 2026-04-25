# RPC body drift audit — p50 (Track Q)

**Date:** 2026-04-24 (corrected 2026-04-25 — p50 Track Q-C found the original audit had wrongly excluded `decrypt_sensitive`/`encrypt_sensitive` as extension-owned; they are project functions and are also orphans, bringing the true count from 90 to 92).
**Trigger:** p49 discovery that `import_vep_applications` live body had drifted from every migration file with no migration capturing the actual deployed state.
**Scope:** Phase 1 (orphan discovery) + sample drift confirmation. Phases 2-3 (full body diff + cleanup) deferred.

## Methodology

1. Enumerated all 642 functions in the `public` schema via `pg_proc`.
2. Filtered out 35 extension-provided functions via `pg_depend` join on `pg_extension` (deptype='e'). Earlier hardcoded filter incorrectly excluded `encrypt_sensitive`/`decrypt_sensitive`; corrected via dynamic dependency lookup.
3. Checked each remaining 607 project functions against `supabase/migrations/*.sql` for any line matching `CREATE [OR REPLACE] FUNCTION [public.]<name>(`.
4. Bucketed by migration-touch count: 0 (orphan) / 1 (single capture) / ≥2 (multi-touch — drift risk grows with count).
5. Sample-checked one top-touched function (`exec_portfolio_health`, 9 migrations) for actual body drift via normalized-prosrc hash comparison.

## Findings

### Coverage distribution (607 project functions, corrected)

| Bucket | Count | Risk |
|---|---|---|
| 0 migrations (orphan) | **92** (15.2%) | Highest — function exists in DB but no migration defines it. Cannot be reproduced from migrations alone. |
| 1 migration | 313 (51.6%) | Low — single canonical capture. |
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

92 orphans exist in production with no migration capture. Distribution:

- **31 readers** (`get_*`): annual KPIs, application interviews, board tags/timeline, partner CRUD readers, selection cycles/rankings/committee, sustainability projections, cron status, governance stats, blog likes, my-* readers (selection result, tasks, PII access log).
- **23 writers** (mutation surfaces): `add_partner_attachment/interaction`, `delete_cost_entry/revenue_entry/partner_attachment/my_personal_data`, `update_publication_submission/cpmai_progress/kpi_target/my_profile/sustainability_kpi`, `submit_cpmai_mock_score`, `enroll_in_cpmai_course`, `enrich_applications_from_csv`, `complete_onboarding_step`, `recalculate_cycle_rankings`, `publish_comms_metrics_batch`, `set_progress`, `toggle_blog_like`, `add_publication_submission_author`, `remove_publication_submission_author`. **Highest concern** — these mutate state under SECDEF; no migration reviewed/captured.
- **5 admin readers/writers**: `admin_force_tribe_selection`, `admin_generate_volunteer_term`, `admin_get_tribe_allocations`, `admin_manage_board_member`, `admin_remove_tribe_selection`.
- **2 PII crypto helpers**: `encrypt_sensitive(text)`, `decrypt_sensitive(bytea)`. Project-defined (no extension owner), not reproducible from migrations. **High concern** — wraps PII encryption.
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

## Phase A — completed in p52 (2026-04-25)

All 92 documented orphans were captured via 13 thematic recovery migrations
(`20260425142341..20260425143839`):

| Batch | Migration | Count | Theme |
|---|---|---|---|
| A | `20260425142341_qa_orphan_recovery_trigger_helpers.sql` | 5 | trigger/utility helpers |
| B | `20260425142413_qa_orphan_recovery_blog_endpoints.sql` | 4 | blog public endpoints |
| C | `20260425142422_qa_orphan_recovery_pii_crypto.sql` | 3 | PII crypto helpers |
| D | `20260425142603_qa_orphan_recovery_privacy_gates.sql` | 8 | privacy gates / my-* |
| E | `20260425142641_qa_orphan_recovery_knowledge_surface.sql` | 6 | knowledge search/insights |
| F | `20260425142756_qa_orphan_recovery_partner_crud.sql` | 7 | partner CRUD |
| G | `20260425142917_qa_orphan_recovery_sustainability_finance.sql` | 8 | finance/KPI |
| H | `20260425143237_qa_orphan_recovery_selection_application.sql` | 14 | selection/application |
| I | `20260425143411_qa_orphan_recovery_cpmai_certificates.sql` | 7 | CPMAI + certificates |
| J | `20260425143511_qa_orphan_recovery_triggers_legacy_compute.sql` | 9 | triggers + legacy compute |
| K | `20260425143634_qa_orphan_recovery_admin_governance.sql` | 8 | admin governance |
| L | `20260425143803_qa_orphan_recovery_misc_readers.sql` | 10 | misc readers |
| M | `20260425143839_qa_orphan_recovery_publication_submissions.sql` | 3 | publication submissions |
| **Total** | **13 migrations** | **92** | |

Bodies captured verbatim from `pg_get_functiondef`. CREATE OR REPLACE made the
operations idempotent on existing definitions; live `pg_proc` is unchanged.
The Q-C contract test allowlist is now empty
(`docs/audit/RPC_BODY_DRIFT_AUDIT_P50_ORPHAN_LIST.txt`) and
`ALLOWLIST_BASELINE_SIZE = 0` in
`tests/contracts/rpc-migration-coverage.test.mjs`.

### Phase B drift signals surfaced during Phase A capture

The capture process surfaced several pre-existing drift signals that Phase B
should reconcile (NOT in Q-A scope — captured verbatim):

1. ✅ **FIXED p52 (`7079c98`, migration `20260425205543`)** —
   **`admin_force_tribe_selection` + `admin_remove_tribe_selection`** gated on
   `members.role` (legacy column that no longer exists; column listing
   confirms only `operational_role`). Were broken in production; both dead
   code (no frontend / EF callsites; only typed in `database.gen.ts`).
   Migrated to V4 `can_by_member('manage_member')`.
2. **`admin_get_tribe_allocations` + `mark_member_excused`** reference
   `members.tribe_id` (post-ADR-0015 the canonical path is engagements).
   `members.tribe_id` column STILL EXISTS — not broken, but architectural
   debt waiting on ADR-0015 Phase 5 (deferred pós-CBGPL). Recommend defer
   until Phase 5 resumes — fixing in isolation duplicates work.
3. **Double aggregation path for `interview` eval type** (verified p53) —
   - `submit_interview_scores` (live): when all evaluators submit, computes
     PERT `(2*min + 4*avg + 2*max)/8` over the array of evaluator
     weighted_subtotals; stores the PERT score in
     `selection_applications.interview_score` and `final_score`.
   - `compute_application_scores` (backfill): AVGs weighted_subtotals per
     eval_type; uses that as `v_int_avg`; sets `research_score = obj_avg +
     int_avg`; does NOT touch `interview_score` column.
   - `import_historical_evaluations` / `import_leader_evaluations` apply
     PERT inline before storing weighted_subtotal in selection_evaluations
     (so weighted_subtotal IS PERT-consolidated for those backfill paths).
   - `compute_application_scores`'s comment claims weighted_subtotal is
     "already PERT-consolidated" — true for the historical importers, but
     `submit_interview_scores` stores the per-evaluator raw weighted sum
     (not PERT). This means in the live path, AVG of weighted_subtotals
     ≠ PERT of weighted_subtotals.
   - Currently disjoint cycles (live = current cycle, backfill = history),
     so no live bug — but the formula divergence is real. NEEDS PM CALL:
     canonize PERT or AVG, then reconcile the unused branch.
4. **One-shot importers hardcode** the cycle code `cycle3-2026` AND two
   evaluator UUIDs (Vitor + Fabricio). Phase B: archive vs parameterize.
   NEEDS PM CALL — cycle3-2026 is closed; archival likely safe, but
   parameterization preserves importer for future cycles.
5. ✅ **FIXED p53 (migration `20260425214708`)** —
   **`get_partner_interaction_attachments`** dereferenced
   `v_interaction.partner_entity_id` but `partner_interactions` has no such
   column (only `partner_id` FK → partner_entities.id). Function would
   error at runtime with `record v_interaction has no field
   partner_entity_id`. Currently dead code (no MCP tool, no frontend
   callsite, only `database.gen.ts` types). Fixed to use
   `v_interaction.partner_id`.
6. ✅ **FIXED p53 (migration `20260425214708`)** —
   **`get_partner_followups` 'stale' bucket** filter `NOT IN ('inactive',
   'churned', 'active')` defeated the bucket's purpose. Live data: 14
   stale-eligible partners total, 5 active recovered (was 9 visible).
   Aligned with overdue/upcoming buckets to `NOT IN ('inactive',
   'churned')`. Function exposed as MCP tool; Claude callers now see the
   complete stale set.
7. **V3 authority gates** — many captured functions use legacy
   `operational_role IN (...)` / `is_superadmin` / `designations` checks
   instead of V4 `can_by_member()`. Tracked separately in ADR-0011 backlog.
   These are explicitly skipped by `tests/contracts/rpc-v4-auth.test.mjs` via
   the `qa_orphan_recovery_` filename pattern (drift cleanup deferred).

### Q-C ratchet adjustments

- `tests/contracts/rpc-migration-coverage.test.mjs`:
  `ALLOWLIST_BASELINE_SIZE` reduced from 92 to 0; test name updated to
  reference "p52 baseline (empty after Q-A)".
- `tests/contracts/rpc-v4-auth.test.mjs`: added
  `Q_AUDIT_CAPTURE_FILE_RE` filter (matches both `qa_orphan_recovery_*`
  and `qb_drift_correction_*`) so capture-only migrations don't
  double-flag against ADR-0011.

## Phase B — in progress (p52, 2026-04-25, 3 of 4 batches done)

Methodology applied per bucket:
1. Enumerate functions per migration-touch count via Python regex over
   `supabase/migrations/*.sql`.
2. Pull live `pg_proc.prosrc` normalized-MD5 hash (collapse whitespace +
   strip).
3. Extract latest CREATE FUNCTION block from migration files; compute
   same hash over the inner body.
4. Diff hashes → drift candidates.
5. Pull live `pg_get_functiondef` for drifted functions.
6. Single drift-correction migration with all drifted CREATE OR REPLACE
   blocks, `$$`-quoted (re-quoted from `pg_get_functiondef`'s default
   `$function$` to keep `kpi-portfolio-health.test.mjs` regex happy).
7. Apply via MCP `apply_migration` → write local file at the same
   auto-timestamp.

### Batch 1 — top 15 high-touch (5+ migrations)

Migration: `supabase/migrations/20260425153438_qb_drift_correction_top6_high_touch.sql`
Commit: `931691a`

Drifted: `_can_sign_gate`, `check_schema_invariants`, `curate_item`,
`exec_portfolio_health` (already known from p50), `get_attendance_grid`,
`get_member_attendance_hours`. **6/15 = 40%**.

Clean: `admin_anonymize_member`, `create_event`, `detect_operational_alerts`,
`exec_tribe_dashboard`, `get_admin_dashboard`, `get_board`,
`get_events_with_attendance`, `move_board_item`, `sign_volunteer_agreement`.

### Batch 2 — 4-touch (34 fns)

Migration: `supabase/migrations/20260425184504_qb_drift_correction_4touch_batch2.sql`
Commit: `c7bed3c`

Drifted: `create_pilot`, `drop_event_instance`, `get_member_cycle_xp`,
`list_meeting_artifacts`, `list_tribe_deliverables`, `sign_ip_ratification`,
`sync_operational_role_cache`, `upsert_publication_submission_event`,
`upsert_tribe_deliverable`. **9/34 = 26.5%**.

### Batch 3 — 3-touch (53 fns)

Migration: `supabase/migrations/20260425193350_qb_drift_correction_3touch_batch3.sql`
Commit: `504036b`

Drifted (single-sig 17): `admin_change_tribe_leader`,
`admin_deactivate_member`, `admin_offboard_member`, `exec_funnel_summary`,
`export_audit_log_csv`, `export_my_data`, `get_board_members`,
`get_card_timeline`, `get_evaluation_form`,
`get_initiative_attendance_grid`, `get_pending_countersign`,
`get_pilots_summary`, `list_initiative_meeting_artifacts`,
`mark_member_present`, `notify_webinar_status_change`,
`process_email_webhook`, `update_event_instance`. **17/53 = 32%**.

Plus 3 `create_notification` overloads (name-based hash diff can't
differentiate; all 3 captured verbatim).

### Batch 4 — 2-touch sample (95 fns)

**Pending.** Will declare Phase B done if cumulative rate drops below
~10% in 2-touch.

### Cumulative drift state (batches 1+2+3)

| Bucket | Count | Drift | Drift rate |
|---|---|---|---|
| 5+ migrations | 15 | 6 | 40.0% |
| 4 migrations | 34 | 9 | 26.5% |
| 3 migrations | 53 | 17 | 32.1% |
| 2 migrations (pending) | 95 | — | — |
| **Cumulative** | **102** | **32** | **31.4%** |

### Drift rate non-monotonicity

Expected drift rate to monotonically decrease with touch count (more
touches = more divergence opportunity). Observed: 40% → 26.5% → 32%
(inversion at 3-touch). Likely 3-touch's bias toward older functions
that absorbed more semantic changes during V4 / ADR-0015 refactors,
while 4-touch may be skewed by recent additions with less drift
opportunity. The 2-touch bucket prediction is genuinely uncertain — if
it follows the older-fns-drift-more theory, it could have a high rate
similar to 3-touch.

### Phase B' — V4 auth migration of captures (NOT done)

Many captured functions (Q-A + Q-B) use legacy V3 authority gates
(operational_role IN, is_superadmin, designations) without a
`can_by_member()` call. The `Q_AUDIT_CAPTURE_FILE_RE` skip filter
exempts these from `tests/contracts/rpc-v4-auth.test.mjs` because they
are capture-only (verbatim production state). The cleanup work is
Phase B' — migrate each to V4 authority.

Estimate: ~6-10h to migrate the ~50+ flagged captures.
