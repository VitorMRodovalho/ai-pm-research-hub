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
   evaluator UUIDs (Vitor + Fabricio). Verified p53 — picture more nuanced
   than the "archive vs parameterize" framing suggested:
   - There IS a currently open cycle (`cycle3-2026-b2`, closes 2026-05-31).
   - But the importers are FORMAT-COUPLED: they expect specific keys in the
     input jsonb (`fabricio_scores_conv`, `vitor_scores_conv`,
     `interview_scores_conv`), and the structure assumes exactly 2
     objective evaluators + 1 interview lead.
   - Parameterizing cycle_code alone is trivial; parameterizing evaluator
     UUIDs is also tractable. But the structural coupling to "Fabricio +
     Vitor are the evaluators" means these importers won't generalize to
     a cycle with different evaluators or different input format.
   - Realistic options: (a) leave as-is (cycle3-2026 done, cycle3-2026-b2
     uses live `submit_*_scores` flow not import), (b) parameterize cycle
     + evaluator UUIDs but accept format coupling, (c) refactor to a
     generic eval-import shape (≥3-4h work). NEEDS PM CALL on which path
     to take.
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
7. ✅ **FIXED p54 (migration `20260426000422`)** —
   **`admin_inactivate_member`** is SECDEF but had NO caller authorization
   gate at all. The function deactivates an arbitrary member by id;
   exposure was implicit via the `/admin/member/[id].astro` UI gate, but
   any authenticated PostgREST caller could invoke the RPC directly.
   Surfaced during Phase B' batch 4 triage (looking at admin writers'
   gates for V3→V4 mapping). Added `can_by_member('manage_member')`.
   This is the first documented case in the audit of a SECDEF capture
   with zero auth — should expect more from the same era.
8. ✅ **FIXED p54 (migration `20260426000422`)** —
   **`import_vep_applications`** is SECDEF but had NO caller authorization
   gate. The function bulk-inserts selection applications from VEP CSV.
   Exposure was implicit via the `/admin/selection.astro` UI gate, but
   any authenticated PostgREST caller could invoke it directly. Adding
   `can_by_member('manage_platform')` matches the page-level intent.
9. **V3 authority gates** — many captured functions use legacy
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

### Phase B' — V4 auth migration of captures (in progress p53)

Many captured functions (Q-A + Q-B) use legacy V3 authority gates
(operational_role IN, is_superadmin, designations) without a
`can_by_member()` call. The `Q_AUDIT_CAPTURE_FILE_RE` skip filter
exempts these from `tests/contracts/rpc-v4-auth.test.mjs` because they
are capture-only (verbatim production state). The cleanup work is
Phase B' — migrate each to V4 authority.

**Status (p53)**: 2/~50 migrated in batch 1 (`20260425224208`,
`phase_bp_admin_governance_v4_auth_batch1`). Estimate remaining:
~5-9h for the remaining captures.

#### V4 action ladders (canonical reference, verified 2026-04-25)

Each action's authorized (kind, role) pairs from
`engagement_kind_permissions`. `is_superadmin = true` is a global
fast-path always honored by `can_by_member()` regardless of action.

| Action | Authorized (kind:role) ladder |
|---|---|
| `manage_platform` | volunteer:manager + volunteer:deputy_manager + volunteer:co_gp |
| `promote` | volunteer:manager + volunteer:deputy_manager + volunteer:co_gp |
| `manage_partner` | volunteer:manager + volunteer:deputy_manager + volunteer:co_gp + sponsor:sponsor + chapter_board:liaison |
| `manage_member` | volunteer:manager + volunteer:deputy_manager + volunteer:co_gp + workgroup_member:leader + study_group_owner:leader + study_group_owner:owner + committee_member:leader |
| `manage_event` | volunteer:manager + volunteer:deputy_manager + volunteer:co_gp + volunteer:leader + volunteer:comms_leader + workgroup_member:leader + study_group_owner:leader + study_group_owner:owner + committee_member:leader |
| `view_pii` | volunteer:manager + volunteer:deputy_manager + volunteer:co_gp + volunteer:leader + workgroup_member:leader + study_group_owner:leader + study_group_owner:owner + committee_member:leader + workgroup_coordinator:coordinator + committee_coordinator:coordinator + chapter_board:board_member |
| `write` | manage_member ladder + volunteer:leader + volunteer:comms_leader + workgroup_coordinator:coordinator + committee_coordinator:coordinator |
| `write_board` | broadest — adds curator/communicator/facilitator/researcher/board participants |

#### Mapping rules from V3 patterns

For each captured function, classify the legacy gate pattern then
choose the narrowest V4 action whose ladder is a SUPERSET of the
legacy authorized roles.

| Legacy V3 pattern | Recommended V4 action | Net expansion (today) |
|---|---|---|
| `is_superadmin OR operational_role IN ('manager','deputy_manager')` | `manage_platform` | +co_gp (no active engagements 2026-04-25 — zero impact) |
| Above + `'co_gp' = ANY(designations)` | `manage_platform` | none — already includes co_gp |
| Above + `tribe_leader` | needs new V4 action OR keep V3 | tribe_leader not in any V4 ladder; expansion to volunteer:leader (manage_event/view_pii) is broader |
| `manage_partner` legacy roles (chapter_liaison, sponsor) | `manage_partner` | matches |
| Pure `is_superadmin = true` | keep V3 + add `can_by_member(_, 'manage_platform')` as additional gate (NEVER replace SA-only with V4 — would expand) | — |
| `'curator' = ANY(designations)` (board curation) | `write_board` (closest) — but check kind:role ladder match | varies, audit per-function |

#### Privilege expansion safety check (mandatory before each migration)

Before applying a Phase B' migration:

```sql
-- Replace LEGACY_GATE_EXPR and TARGET_V4_ACTION
WITH legacy AS (
  SELECT m.id, m.name FROM members m
  WHERE m.is_active = true AND (LEGACY_GATE_EXPR)
),
v4 AS (
  SELECT m.id, m.name FROM members m
  WHERE m.is_active = true AND can_by_member(m.id, 'TARGET_V4_ACTION')
)
SELECT
  (SELECT array_agg(name ORDER BY name) FROM legacy) AS legacy_authorized,
  (SELECT array_agg(name ORDER BY name) FROM v4) AS v4_authorized,
  (SELECT array_agg(name ORDER BY name) FROM v4 WHERE id NOT IN (SELECT id FROM legacy)) AS would_gain;
```

Rule: if `would_gain` is non-empty AND any of those gains expose
cross-chapter visibility OR PII OR sensitive operations → DO NOT
migrate; create a narrower V4 action OR keep V3 with skip filter.

#### Autonomous-safe migration criteria

A captured function is safe for autonomous Phase B' migration if all hold:
1. Legacy gate matches a V4 action ladder cleanly (per mapping table).
2. `would_gain` from safety check returns empty array OR only roles
   whose authority semantics align with the function's purpose.
3. Function does NOT expose PII or cross-chapter data when called by
   a `would_gain` role (manual code review).
4. Function has no callers that depend on the legacy V3 behavior
   (e.g., expecting `is_superadmin = true` specifically).

If any criterion fails → escalate to PM-supervised batch.

#### Batch 1 closure (p53, `20260425224208`)

Migrated:
- `admin_generate_volunteer_term` → `manage_platform`
- `admin_manage_board_member` → `manage_platform`

Privilege expansion: zero in current production (no active deputy_manager
or co_gp engagements). Co_gp is reserved for co-General Project leaders
whose admin authority is consistent with these functions.

#### Batch 2 closure (p53, `20260425230700`)

Migrated:
- `get_governance_stats` → `manage_platform`
- `get_member_transitions` → `manage_platform` (self-read branch preserved)
- `get_cron_status` → `manage_platform`
- `get_platform_usage` → `manage_platform`
- `get_cpmai_admin_dashboard` → `manage_platform`

Privilege expansion: zero (same safety check as batch 1, legacy_count=2,
v4_count=2, would_gain=null, would_lose=null).

Phase B'' candidate (NOT migrated):
- `get_application_score_breakdown` — has curator branch
  (`designations && ARRAY['curator']`). `manage_platform` does not include
  curator role; migrating would TIGHTEN authority. Either need a new V4
  action that includes curator OR keep V3 with skip filter.

#### Batch 3 closure (p53, `20260425233231`)

Migrated:
- `get_pii_access_log_admin` → `manage_platform`
- `recalculate_cycle_rankings` → `manage_platform`

Privilege expansion: zero (same safety check pattern).

Phase B'' candidates discovered while filtering batch 3:
- `publish_comms_metrics_batch` — uses `can_manage_comms_metrics()`
  helper. Helper itself is V3-style. Migration requires also refactoring
  the helper or replacing helper call with `can_by_member()`. Phase B''.
- `mark_member_excused` — has tribe_leader path with members.tribe_id.
  Phase 5 ADR-0015 territory (drift signal #2).

#### Batch 4 closure (p54, `20260426000422`)

Mixed scope: 2 V3→V4 conversions + 2 security hole fixes (drift signals
#7 and #8 surfaced during triage).

V3→V4 migrated:
- `get_ghost_visitors` → `manage_platform` (ghost visitor admin reader,
  V3 pattern was `is_superadmin OR manager OR deputy_manager`).
- `admin_send_campaign` → `manage_platform` (campaign sender with
  rate limits preserved; V3 pattern was same).

Security hole fixes (NEW V4 gate where there was NONE):
- `admin_inactivate_member` → `manage_member` (was wide-open SECDEF;
  drift signal #7).
- `import_vep_applications` → `manage_platform` (was wide-open SECDEF;
  drift signal #8).

Privilege expansion (V3→V4 candidates): zero (same safety check pattern
as batches 1-3). For security hole fixes the migration TIGHTENS authority
from "any authenticated caller" to manage_member/manage_platform ladder.

Phase B'' candidates discovered while filtering batch 4 (NOT migrated):
- `admin_change_tribe_leader`, `admin_deactivate_member` — SA-only by
  design. Migrating to manage_platform would EXPAND to deputy_manager
  + co_gp; intentional SA-only scoping should be preserved.
- `admin_list_members`, `get_diversity_dashboard`, `get_member_detail`
  — gate includes sponsor + chapter_liaison (cross-chapter PII
  visibility). Need new V4 action like `view_chapter_roster` or keep V3.
- `get_selection_dashboard`, `get_selection_rankings`,
  `get_application_score_breakdown` — curator branch (same root cause
  as batch 2 deferral). Need `view_selection_scores` action.
- `submit_curation_review`, `issue_certificate` — manager + deputy_manager
  + curator. Same curator branch problem.
- `upsert_publication_submission_event` — manager + deputy_manager +
  communicator (operational_role) + curator + co_gp + comms_leader +
  comms_member (designations). Wide multi-role; needs Phase B''.
- `submit_interview_scores` — interviewer-id-based gate (custom). Not
  generic V4 fit.
- `mark_member_present`, `register_own_presence` — tribe_leader path;
  Phase 5 territory.
- `finalize_decisions`, `get_evaluation_form`, `get_pending_countersign`
  — committee-membership / chapter_board designation paths. Custom V4
  needed.

Triggers / utilities passed over (no auth gate by design):
- `auto_comms_card_on_publish`, `notify_webinar_status_change`,
  `log_webinar_created`, `set_curation_due_date`,
  `sync_operational_role_cache` — triggers running on row change events.
- `compute_legacy_role`, `current_member_tier_rank`, `try_auto_link_ghost`,
  `broadcast_count_today`, `calc_trail_completion_pct` — internal helpers.

Already V4 (no work needed):
- `admin_link_communication_boards`, `admin_update_member_audited`,
  `manage_initiative_engagement`.

#### Phase B' running tally (post batch 4)

- 13/~50 captured V3-gated functions migrated to V4 (batches 1-4).
- 2 security holes (NO auth → V4 auth) fixed in batch 4 — newly tracked
  as drift signals #7 + #8.
- All V3→V4 migrations: zero authorization change in current production.
- Pattern proven scalable: same gate template + same V4 action +
  same safety check workflow.
- Phase B' clean-case backlog effectively exhausted for the
  qa_orphan_recovery + qb_drift_correction captures (most remaining
  candidates need new V4 actions = Phase B'').

#### Open Phase B'' / new V4 action candidates

Functions whose legacy gate doesn't map cleanly to existing V4 actions:
- ✅ **CLOSED p59**: 8 of 11 documented V3-gated fns converted via 3 ADRs
  (ADR-0025 manage_finance + ADR-0026 manage_comms + ADR-0027 governance
  readers Opção B reuse). See "Phase B'' p59 closure" section below.
- `get_application_score_breakdown` — needs `manage_platform OR curator`
  semantics. Either a new V4 action (e.g., `view_selection_scores` with
  ladder = manage_platform + write_board curator) OR keep V3.
- Partner subsystem (5 fns) — `manage_partner` ladder expands
  cross-chapter to sponsor/chapter_liaison; preserved in V3 by p53
  drift signal #5 #6 work. Phase B'' could introduce
  `manage_partner_global` (manager+deputy+co_gp only) for cross-chapter
  reads.
- Functions with `tribe_leader` in legacy gate — no V4 action covers
  tribe_leader. Wait for ADR-0015 Phase 5 (tribe_id deprecation) which
  will likely introduce a `manage_tribe` action.

### Phase B'' p59 closure — 8 fns converted via 3 ADRs

**ADR-0025 manage_finance (4 fns)** — migration `20260426165847`:
- `delete_cost_entry`, `delete_revenue_entry`, `update_kpi_target`,
  `update_sustainability_kpi`
- New action `manage_finance` granted to: volunteer × {co_gp, manager,
  deputy_manager} + sponsor × sponsor (Q1 ratify SIM)
- Privilege expansion: 5 sponsors gained access (intentional per Q1)
- Zero would_lose

**ADR-0026 manage_comms (1 fn)** — migration `20260426170038`:
- `admin_manage_comms_channel`
- New action `manage_comms` granted to: volunteer × {co_gp, manager,
  deputy_manager, comms_leader}
- Privilege drift surfaced: Mayanna Duarte lost access (V3 designation
  comms_leader sem V4 engagement volunteer×comms_leader). Documented
  per ADR Q1 — drift correction, not regression. PM may create
  engagement post-fact if she's a real comms operator.

**ADR-0027 governance readers (3 fns) — Opção B reuse**:
- migration `20260426170149`
- `get_change_requests`, `get_governance_dashboard`,
  `get_governance_documents`
- Pattern: outer `rls_is_member()` + inner `can_by_member('manage_platform')`
  for admin-shape filtering
- Zero new actions added (Opção B reuse — most economical option)
- Behavior change: V3 observers lost access (V4 observers no longer
  have authoritative engagement). Per ADR Q2 ratify: accepted as drift
  correction (observers don't use governance UI in practice).

**Phase B'' running tally post-p59**:
- **Q-D-surfaced V3 fns subset**: 11 documented during Q-D triage as
  out-of-scope V3 (the "obvious" candidates surfaced during batch
  3a.5/3a.6/3a.7 + earlier B' work).
  - **8/11 closed** via ADRs 0025+0026+0027 (this session).
  - **3 remaining** edge cases TBD (likely partner subsystem +
    `get_application_score_breakdown` per audit doc Open Phase B''
    section).
- **Total platform V3 surface (DISCOVERED p59 cleanup)**: **246
  SECDEF fns** matching `is_superadmin|operational_role` regex
  (excluding triggers, extensions, internal helpers).
  - 81 are `admin_*` shape (admin operations)
  - 3 are `_*` internal helpers
  - 162 other (member-tier writers, mixed)
- **Phase B' (p52-p54) closed**: 13 V3→V4 conversions of "clean case"
  fns (no new action needed)
- **Cumulative V3→V4 conversion rate**: ~21 of 246 (~9%)
- **New V4 actions added p59**: 2 (`manage_finance`, `manage_comms`)
- **Existing V4 actions reused**: 1 (`manage_platform` for governance
  readers per ADR-0027 Opção B)

**Reframe (important)**: most of the 246 remaining V3 fns are NOT
security holes — they have V3 gates that work correctly (admin-shape
narrow). They simply don't follow V4 engagement-derived authority
pattern. Phase B'' is therefore a **platform V3→V4 modernization
track**, not a security incident response. Closing it improves
auditability (explicit kind/role/action mapping) and consistency
but isn't urgent.

**Sponsor briefing impact**: when reporting to Ivan, distinguish:
- ✅ Phase Q-D security sweep: 100% closed (8/8 buckets)
- ✅ Track R schema exposure: 85% closed (152 REVOKEs)
- 🟡 Phase B'' V3→V4 modernization: 9% closed (21/246) — ongoing track,
  not security-critical

Members impacted by p59 ADR conversions:
- **Gained access**: 5 sponsors via manage_finance (intentional Q1)
- **Drift correction**: Mayanna Duarte lost comms access (V3 designation
  never used in audit log — confirmed pure drift, no engagement needed)
- **Drift correction**: V3 observers lost governance reader access (not
  actually used by observers per usage analysis)

### Phase B'' Pacote D + Pacote E easy-convert (p59 + p60)

Two batches of "easy-convert" admin_* fns where:
1. Existing V3 gate is `is_superadmin OR manager/deputy_manager [OR co_gp]`
2. Existing V4 `manage_platform` action grant set is **identical** (no
   new action needed; reuses existing engagement_kind_permissions rows)
3. Privilege expansion check returns `would_gain=[]` and `would_lose=[]`

These are pure modernization conversions — body unchanged, V3 top-gate
swapped for `can_by_member(v_caller_id, 'manage_platform')`, search_path
hardened from `'public, pg_temp'` → `''` (already-qualified bodies),
PUBLIC + anon EXECUTE REVOKE'd.

**Pacote D (p59) — migration `20260426172305`** — 5 admin_* fns:
- `admin_bulk_allocate_tribe`, `admin_bulk_set_status` → `manage_member`
- `admin_get_tribe_allocations` → `manage_platform` (TODO future view_pii)
- `admin_set_tribe_active`, `admin_deactivate_tribe` → `manage_platform`

**Pacote E (p60) — migration `20260426173951`** — 12 admin_* fns
(all → `manage_platform`):
- `admin_ensure_communication_tribe`
- `admin_finalize_ingestion_batch`
- `admin_link_board_to_legacy_tribe`
- `admin_link_member_to_legacy_tribe`
- `admin_map_notion_item_to_board`
- `admin_run_retention_cleanup` (V3 was tighter — no co_gp; V4 grant set
  still equals 2; zero gain)
- `admin_set_ingestion_source_policy`
- `admin_start_ingestion_batch`
- `admin_upsert_legacy_tribe`
- `admin_upsert_tribe`
- `admin_upsert_tribe_continuity_override`
- `admin_upsert_tribe_lineage`

**Test impact (p60)**: `tests/contracts/security-lgpd.test.mjs:199`
(`admin_run_retention_cleanup requires admin`) updated to accept V4
`can_by_member(..., manage_platform)` in addition to V3 patterns
(same fix style as `create_event` AUTH_FIXED_RPCS update 2026-04-17).
No other test changes needed; presence-checks in
`tests/ui-stabilization.test.mjs` read OLD migration files which still
contain the original `create or replace function public.admin_X(`
strings (DROP+CREATE in NEW migrations doesn't break those checks).

**Pacote F (p60) — migration `20260426174923`** — 3 admin member-ops fns
(all → `manage_member`, V3 was tighter superadmin-only):
- `admin_change_tribe_leader`
- `admin_deactivate_member`
- `admin_move_member_tribe`

Discovered post-Pacote-E by querying for `admin_*` SECDEF fns still
using `get_my_member_record()` V3 gate without service_role bypass and
without `can_by_member`. 7 fns surfaced; 3 here are clean conversions
(V3 superadmin-only ≡ V4 manage_member set = 2). Privilege expansion
check: would_gain=[]/would_lose=[].

**4 deferred from same surface (PM ratify needed)**:
- `admin_archive_project_board(uuid, text, boolean)` — V3 includes
  4th clause `tribe_leader AND tribe_id = v_board_tribe_id`. Converting
  to `manage_platform` would REMOVE tribe_leader's ability to archive
  their own board. Needs V4 `scope='tribe'` permission OR per-tribe
  delegation strategy decision.
- `admin_restore_project_board(uuid, text)` — Same V3 pattern as
  archive. Same defer reason.
- `admin_list_tribes(boolean)` — V3 includes `tribe_leader` in addition
  to superadmin/manager/co_gp. Tribe leaders read all tribes for cross-
  tribe coordination. Converting to `manage_platform` would CONTRACT
  privileges (contraction = drift correction or regression?). Needs PM
  read-tier classification — possibly new `view_tribes_admin` action OR
  promote to public read since "tribe basic info" is non-sensitive.
- `admin_list_tribe_lineage(boolean)` — Same V3 pattern as
  admin_list_tribes. Same defer reason.

**Pacote G (p60) — migration `20260426190314`** — 1 read-only fn:
- `exec_skills_radar()` → `manage_platform`
- Discovered post-Pacote-F by querying non-`admin_*` SECDEF fns
- Special semantic preserved: returns empty JSON ('{}') on unauthorized
  (NOT raise exception — fail-safe silent pattern)

**Pacote H (p60) — migration `20260426190940`** — 8 admin/exec fns:
- `admin_detect_board_taxonomy_drift()` → `manage_platform` (search_path hardened)
- `admin_detect_data_anomalies(boolean)` → `manage_platform` (search_path hardened)
- `admin_get_anomaly_report()` → `manage_platform` (search_path KEPT — body has
  unqualified refs; full-qualify refactor out of scope)
- `admin_resolve_anomaly(uuid, text)` → `manage_platform` (search_path hardened)
- `admin_run_portfolio_data_sanity()` → `manage_platform` (search_path hardened)
- `admin_update_application(uuid, jsonb)` → `manage_platform` (search_path KEPT)
- `admin_manage_cycle(...)` → `manage_platform` (search_path hardened)
- `exec_chapter_comparison()` → `manage_platform` (search_path KEPT)

Discovered post-Pacote-G by categorizing the 105-fn wider V3 surface.
17 admin/exec candidates surfaced; 8 clean (this batch) + 9 deferred
(extra designations like comms_team/sponsor/chapter_liaison, OR
tribe_leader scope clauses needing V4 scope='tribe'). Privilege
expansion check: would_gain=[]/would_lose=[] for all 8 (V3 broad/tight
admin set = V4 manage_platform = 2).

**search_path partial hardening pattern sedimented p60**: 5/8 fns
hardened to `''` (bodies fully-qualified pre-existing); 3/8 kept as
`'public, pg_temp'` (bodies have unqualified refs OR call unqualified
helpers like `check_pre_onboarding_auto_steps`). Deferring full-qualify
refactor to keep this batch scope tight; documented per-fn in COMMENT.

**9 deferred from Pacote H discovery (PM ratify needed)**:
- `admin_get_campaign_stats(uuid)` + `admin_preview_campaign(...)` —
  V3 includes `comms_team` designation; needs `manage_comms` action
  extension OR new view-tier action.
- `admin_manage_partner_entity(...)` + `admin_update_partner_status(...)`
  — V3 includes `sponsor`/`chapter_liaison` designations; needs new
  `manage_partner` action with multi-grant.
- `admin_list_members(...)` — V3 includes `sponsor`/`chapter_liaison`
  read access AND returns PII (email). Needs `view_members` action
  + log_pii_access decision.
- `admin_list_archived_board_items(...)` — V3 includes `co_gp`
  designation broadly; needs broader audit (truncated body).
- `admin_update_board_columns(...)` + `admin_bulk_mark_attendance(...)`
  — V3 has tribe_leader scope clause; needs V4 `scope='tribe'`
  permission OR delegation pattern.
- `exec_chapter_dashboard(text)` — V3 has chapter-self scope (any
  member of own chapter can view); needs V4 scope='chapter' permission.

**Pacote I (p63) — migration `20260426212845`** — 6 misc admin fns
(5 names + 1 overload, all → `manage_platform`):
- `delete_pilot(uuid)`, `delete_tag(uuid)` (V3 tight)
- `get_site_config()`, `platform_activity_summary()` (V3 broad incl co_gp)
- `set_site_config(text, text)` (V3 tight) + `set_site_config(text, jsonb)`
  overload (was V3 superadmin-only — drift fix; both overloads now
  consistent at `manage_platform`)

Discovered post-Pacote-H by 75-fn surface audit. Sub-categorization
of `A_admin_broad` (25 non-admin/exec fns) identified 5 sub-types;
A0 (clean — no extra designations, no scope clause) = 5 fns + 1
overload. All zero-expansion verified (V3 tight = V3 broad = V3
superadmin = V4 manage_platform = 2).

### 75-fn misc surface audit (p63 — full categorization)

Surface mapped: 90 fns total (estimate p60 was 75; refined here).
SECDEF + is_superadmin pattern + no can_by_member + no service_role +
non-admin_*/exec_*/trg_*/_audit_* prefix.

| Category | Count | Pattern | Pacote candidate |
|---|---|---|---|
| **A_admin_broad** | 25 | `is_superadmin OR mgr/dmr [OR co_gp]` | sub-divided below |
|   ↳ A0 clean | 5+1 ovrl | No extra designations or scope | ✅ **Pacote I** (p63 — done) |
|   ↳ A2 partner_designations | 8 | sponsor + chapter_liaison | needs `manage_partner` ADR |
|   ↳ A4 other_designations | 7 | curator/founder/ambassador/etc | needs new V4 actions per domain |
|   ↳ A5 tribe_leader_no_scope | 5 | tribe_leader without scope clause | per-fn inspection (likely Pacote J after audit) |
| B_caller_target | 1 | self-ownership (caller=target) | leave-as-is (`mark_member_present` — caller is member acting on self) |
| C_helper_bool | 4 | `boolean` helper called by other fns | careful — used by many; needs caller graph audit |
| D_member_tier_role | 26 | `is_superadmin` w/o mgr/dmr clause | mostly NOT admin gates; many are member-self ops misclassified by regex |
| F_other | 34 | mixed patterns | per-fn audit needed; many are member-tier writers |

**Pacote I-J-K pipeline**:
- I (done p63): A0 clean = 6 fns (5 names + 1 overload)
- **J (audit done p64 — ALL 5 DEFERRED)**:
  - `create_tag(semantic tier)` — broad INTENTIONAL (tags são globais);
    conversion would CONTRACT semantic tag privilege to non-leaders.
    Needs separate `create_semantic_tag` action OR keep V3.
  - `register_attendance_batch`, `submit_for_curation`,
    `unassign_member_from_item`, `update_event_duration` — broad
    LIKELY missing scope (tribe_leader should be scoped to own tribe's
    events/items). Conversion would CONTRACT. Needs V4 `scope='tribe'`
    permission OR validation refactor.
- **K (audit done p64 — split into 4 sub-pacotes)**: A2 (8 fns)
  identified post-audit as needing 4 distinct V4 actions, not 1:
  - K1 `view_chapter_admin_data` (3 fns: get_chapter_dashboard,
    get_chapter_needs, get_member_detail) — chapter visibility for
    sponsor/chapter_liaison. **1 of 3 has PII** (get_member_detail
    returns email).
  - K2 `view_partner_data` (3 fns: get_partner_entity_attachments,
    get_partner_interaction_attachments, get_partner_pipeline) —
    partner ops visibility. **1 of 3 has PII** (get_partner_pipeline
    returns contact info).
  - K3 `view_volunteer_agreement_admin` (1 fn:
    get_volunteer_agreement_status) — admin volunteer audit.
    **HAS PII** (returns email).
  - K4 `detect_and_notify_detractors_cron` — cron-only op; user-facing
    gate is dead code. Can convert to `manage_platform` directly OR
    DROP user-facing gate.
- **L (audit done p64 — split into 2 sub-pacotes)**: A4 (7 fns) all
  involve `curator` designation; 4 with curator-only, 3 with curator+co_gp:
  - L1 `manage_partner_attachment` (4 fns: add_partner_attachment,
    delete_partner_attachment, assign_member_to_item, get_board_members) —
    curator visibility on partner data + board members. No PII.
  - L2 `manage_curation` (3 fns: assign_curation_reviewer,
    publish_board_item_from_curation, submit_curation_review) — curation
    workflow. No PII.

**C helpers caller graph (p64 partial audit)**:
- `can_manage_comms_metrics` → 1 caller in pg_proc (`publish_comms_metrics_batch`)
- `has_min_tier` → 1 caller in pg_proc (`exec_cert_timeline`)
- `can_manage_knowledge` → 0 callers in pg_proc (likely RLS policies or
  frontend/EF — needs grep beyond pg_proc)
- `rls_is_superadmin` → 0 callers in pg_proc (used by RLS policies)

**Verdict C**: pg_proc-only scan incomplete. Needs RLS policy + frontend
grep before touching. **DEFER** until full caller surface mapped.

**Security finding (p64): detect_and_notify_detractors_cron** was
misclassified A2 (regex matched body line `m.operational_role NOT IN
('sponsor', 'chapter_liaison')` — exclusion filter, not designation
grant). Per-fn audit revealed no top-level auth gate AND PUBLIC EXECUTE
grant. Fixed via REVOKE PUBLIC + anon (migration `20260426214032`).
Full V4 gate deferred to service-role-bypass adapter pattern ADR.

**C helpers** require caller graph audit — they're called by many
other fns, so converting them changes downstream behavior platform-wide:
- `can_manage_comms_metrics()` — referenced in metrics RPCs
- `can_manage_knowledge()` — referenced in wiki/docs RPCs
- `has_min_tier(int)` — tier rank ladder, used by ~10 fns
- `rls_is_superadmin()` — RLS policy helper, hot path

**D + F (60 fns total)** mostly NOT admin gates. Initial regex
classification mislabeled them. Spot check:
- `get_my_member_record()` — D, but trivially returns own record (auth context)
- `select_tribe(int)` — F, member self-action (caller=target)
- `register_own_presence(uuid)` — F, member self-action
- `sign_volunteer_agreement(text)` — F, member self-action
- `submit_change_request(...)` — F, any-member writer
- `mark_interview_status(...)` — D, but interviewer-targeted

These are NOT in scope for "Phase B'' V3→V4 modernization" — they're
already correctly gated to caller=target or specific role; just don't
use `can_by_member()` because action mapping doesn't apply (member-self
operations don't need an action — they need ownership check).

**Effective Phase B'' addressable surface (post-p63 audit)**: ~25
remaining easy-convert candidates after Pacote J + K (A5 + A2 + A4).
The 60 D/F fns are mostly "leave-as-is, not admin gates".

**Phase B'' running tally post-p67 (+ ADR-0037 chapter_needs + org_chart)**:
- Phase B' (p52-p54): 13 V3→V4 conversions (clean case, no new action)
- Phase B'' p59 ADRs 0025/0026/0027: 8 fns (3 new V4 actions)
- Phase B'' p59 Pacote D easy-convert: 5 fns
- Phase B'' p60 Pacote E easy-convert: 12 fns
- Phase B'' p60 Pacote F easy-convert: 3 fns
- Phase B'' p60 Pacote G easy-convert: 1 fn
- Phase B'' p60 Pacote H easy-convert: 8 fns
- Phase B'' p63 Pacote I easy-convert: 6 fns (5 names + 1 overload)
- **Phase B'' p66 ADR-0026 extension: 2 fns (admin_get_campaign_stats, admin_preview_campaign — manage_comms reuse)**
- **Phase B'' p66 ADR-0030 view_internal_analytics: 2 fns + 1 helper (exec_chapter_dashboard, exec_role_transitions, can_read_internal_analytics — new V4 action)**
- **Phase B'' p66 ADR-0031 admin_list_members: 1 fn (Opção B reuse view_internal_analytics, +Roberto chapter_board×liaison gain)**
- **Phase B'' p66 ADR-0032 board admin: 4 fns (3 writers via new manage_board_admin resource-scoped + 1 reader via Opção B reuse view_internal_analytics, Path A drift Sarah/Mayanna)**
- **Phase B'' p66 ADR-0033 Phase 1 partner subsystem: 4 fns (3 via Opção B reuse manage_partner + 1 via manage_platform reuse, drift loss João chapter_liaison)**
- **Phase B'' p66 ADR-0034 Phase 2 partner attachments: 4 fns (Path A writers + Path D readers, drift signals #5 #6 CLOSED, drift loss Sarah curator + 6 tribe_leaders)**
- **Phase B'' p66 ADR-0035 analytics + no-gate hardening: 4 fns (2 V3→V4 reuse view_internal_analytics + 2 no-gate hardening get_annual_kpis/get_cycle_report)**
- **Phase B'' p66 ADR-0036 get_member_detail: 1 fn (Opção B reuse view_internal_analytics, ADR-0031 ladder precedent)**
- **Phase B'' p67 ADR-0037 get_chapter_needs + get_org_chart: 2 fns (Opção B reuse view_internal_analytics + manage_platform; Path Y formalized for chapter_board sub-role preservation; drift loss João chapter_liaison + 6 tribe_leaders + Sarah curator — precedented)**
- **Phase B'' p67 ADR-0037 ext submit_chapter_need: 1 fn (closes chapter_needs subsystem 100% V4 — V4 expansion 12→13 with Vitor + Fabricio gain via org-tier leadership engagement, drift loss João — same precedent)**
- **Cumulative: 82 of 246 fns (~33.3%)** — up from p66 79/246 (32.1%)
- **New V4 actions cumulative**: 5 (manage_finance, manage_comms, view_internal_analytics, manage_board_admin + 3 Opção B reuses: governance readers + member directory + archived board listing + partner subsystem 100%)
- **First p66 use of resource-scoped `can_by_member(_, action, 'initiative', id)`** — precedent established para ADRs futuras com per-resource gates (pattern já existia em V4 core mas pouco usado em Phase B'' até este ponto).
- **Partner subsystem 100% V4** — Phase 1 (ADR-0033) + Phase 2 (ADR-0034) = 8/8 fns convertidas.
- **Drift signals #5 #6 CLOSED** (audit doc Phase B' track) — V3 chapter_match using operational_role-based check removed entirely; V4 manage_partner is single source of truth.
- Easy-convert backlog (true zero-expansion clean cases for any
  prefix): **0 known after Pacote I** — exhaustive 90-fn surface audit
  exhausted clean candidates with admin-broad gate.
- Remaining V3 surface (~190 fns) split per p63 categorization:
  - **5 A5 candidates** (tribe_leader_no_scope) — Pacote J after per-fn
    inspection; if intentional broad, ~5 more easy-converts
  - **15 A2+A4** (partner/curator/etc designations) — needs ADRs:
    `manage_partner` (8) + per-domain (7)
  - **9 deferred** from Pacote F+H (board scope + extra designations)
  - **4 helpers** (C_helper_bool) — caller graph audit needed
  - **60 D+F** — mostly member-self ops, NOT admin gates (leave-as-is
    likely correct verdict; case-by-case audit confirms)
  - **29 service-role-bypass `admin_*`** — adapter pattern needed
  - **~75 other** (curation, finance, certificates, etc.) — per-domain

## Phase Q-D — SECDEF security hardening sweep (started p55, 2026-04-25)

### Track charter

**Scope**: All SECDEF functions in `public` schema that lack an
authorization gate AND grant EXECUTE to PUBLIC / anon / authenticated
by default. Discovery (p55) identified 566 SECDEF total; 109 fall in
this "orphan-no-gate external-callable" bucket.

**Authorization**: Implementation of existing policy (no new ADR).
Track Q-D enforces:
- ADR-0011 (V4 authority) — `can_by_member()` is the canonical gate.
- ADR-0007 (`can()` as source of truth) — engagement-derived authority.
- LGPD Art. 5/6/46 (data minimization + adequate technical measures).
- `database.md` GC-162 — RLS + SECDEF discipline.

PMI accountability rationale: SECDEF functions executing as definer
bypass RLS; without explicit auth gate, any PostgREST caller (anon
key + JWT) reaches the function body. Closing this gap is required
for CBGPL audit-readiness (data stewardship standards).

**Treatment matrix** (mirrors decision matrix at end of doc):

| Caller surface | Treatment | Gate |
|---|---|---|
| No callers in `src/` or `supabase/functions/` (dead) | REVOKE FROM PUBLIC, anon, authenticated | None needed |
| pg_cron only (postgres role) | REVOKE FROM PUBLIC, anon, authenticated | None needed |
| EF only (service_role) | REVOKE FROM PUBLIC, anon, authenticated | None needed |
| Admin frontend caller (PII output) | REVOKE FROM PUBLIC, anon (keep `authenticated`) + ADD `can_by_member()` gate inside body | manage_platform / manage_member as fits |
| Mixed-tier frontend caller (homepage / member view) | DEFER for PM tier clarification | TBD |
| Public-by-design reader verified | No change (docs-only) | None — intentional public exposure |

**Methodology** (per batch):
1. Pull body via `pg_proc.prosrc` to confirm what's returned.
2. Pull ACL via `pg_proc.proacl` to confirm exposure.
3. Grep `src/` + `supabase/functions/` for callsites.
4. **(MANDATORY p64+) Scan `pg_policy.polqual` + `polwithcheck` for
   direct refs.** RLS policies call functions in the **caller's role
   context** — REVOKE EXECUTE FROM authenticated breaks RLS evaluation
   regardless of SECDEF status. Use word-boundary regex to avoid
   substring false-positives:
   ```sql
   SELECT schemaname, tablename, policyname, cmd
   FROM pg_policies
   WHERE schemaname = 'public'
     AND (qual ~* '\m(public\.)?<fn_name>\(' OR with_check ~* '\m(public\.)?<fn_name>\(')
   ORDER BY tablename, policyname;
   ```
   `\m` is the word-boundary anchor — without it, `can(` matches
   `rls_can(` and `can_by_member(`, producing false alarms (and the
   inverse: a loose regex on a fn that IS in policies could miss it
   if surrounded by punctuation). If any result is non-empty, the
   function is on a hot path inside RLS — REVOKE candidate must keep
   `authenticated` GRANT, OR the policy must be refactored to call a
   SECDEF wrapper (e.g., `rls_can()`, `can_by_member()`) that itself
   retains authenticated grant.
5. Classify per matrix above.
6. Run privilege expansion safety check if adding gate.
7. Apply migration (REVOKE + optional gate). If only verification
   needed, docs-only commit.
8. Verify post-state via ACL + body recheck.

**Batch plan**:
- Batch 1 (p55, done): 21 fns hardened (PII crypto + cron + EF webhook + dead admin).
- Batch 2 (p56, done): 13 public-by-design readers verified safe (docs-only).
- Batch 3a (in progress p57+): admin-shape readers, 30-40 fns total. Sub-batches of 6-10.
- Batch 3b (TBD): 27 internal helpers REVOKE (defense-in-depth).

### Charter amendment — pg_policy precondition (added p65, 2026-04-26 post-incident)

**Trigger**: Production incident on 2026-04-26 14:56 UTC. Migration
`20260426145632_track_q_d_internal_helpers_batch3b.sql` REVOKE'd
EXECUTE on `auth_org()` and `can_by_member()` from authenticated,
justified by "internal helpers called only by other SECDEF fns or
service_role EFs — REVOKE from authenticated is defense-in-depth
without behavioral change."

The audit chain at the time checked four caller surfaces (frontend
`.rpc('<fn>')` grep, EF source `<fn>` references, `pg_proc.prosrc`
SECDEF caller chain, migration history) but **missed the
`pg_policy.polqual` / `polwithcheck` reference scan**.

**Blast radius**: 48 RLS policies (every `*_v4_org_scope`) call
`auth_org()` directly in their USING clause; 13 RLS policies call
`can_by_member()` directly. RLS evaluates in the caller's role context,
so PostgreSQL requires EXECUTE on the function regardless of SECDEF
status. ALL authenticated PostgREST table reads triggering members RLS
failed silently for ~8 hours — `.single()` returned null, `.select()`
returned `[]`, frontend pages depending on direct table reads broke.

**Curator-tier collateral**: Sarah (curator) attempted to read Adendo
IP doc via `/governance/ip-agreement` flow. `get_pending_ratifications`
(SECDEF RPC) worked; clicking through to read content called
`sb.from('document_versions')` directly → RLS chained to
`can_by_member()` → permission denied → `versionRes.data = null` →
page rendered "(conteúdo indisponível)". Member then accidentally
clicked Sign without reading content. Signoff was reverted per
`incident(p64): revert Sarah's accidental signoff per PM Opção A`
(commit `5891746`).

**Hotfix migrations** (commit `a995d3f`):
- `20260426232108_hotfix_p64_restore_auth_org_grant_authenticated.sql`
- `20260426232200_hotfix_p64_restore_can_by_member_grant_authenticated.sql`

Both functions had their authenticated + anon GRANT restored. The
COMMENT on each function now documents the lesson:

> "Revoking from authenticated breaks PostgREST table reads — see
> hotfix migration ... + p64 incident. Track Q-D internal-helper
> REVOKE charter must check `pg_policy.polqual` references before
> applying."

**p65 retro-scan**: With the corrected word-boundary regex `\m can\(`,
the only function from batch 3b still REVOKE'd from authenticated AND
referenced in any RLS policy is `public.can(uuid, text, text, uuid)` —
**zero policy references**. All 73 substring matches in p65's initial
loose-regex scan were false-positives from `rls_can(` and
`can_by_member(`. No further hotfix needed.

**Sediment** (forward commitment for any Q-D batch — Batch 3b residue,
future batches, AND Phase B' / B'' migrations that touch SECDEF
function GRANTs):

1. The `pg_policy` scan (step 4 above) is **mandatory**, not
   optional. Use word-boundary regex `\m`.
2. Functions surfaced by the scan keep `authenticated` GRANT
   regardless of "internal helper" classification — the helper IS
   user-reachable via RLS evaluation.
3. Preferred refactor pattern for new authority gates: define a SECDEF
   wrapper (like `rls_can(text)` or `can_by_member(uuid, text, text,
   uuid)`) that retains authenticated grant. RLS policies call the
   wrapper, never the underlying core (`can(...)`). Then the core can
   stay REVOKE'd without breaking RLS — the wrapper resolves the
   call inside the SECDEF chain (postgres role).
4. When in doubt, leave the GRANT and add a body-level gate (`auth.uid()
   IS NULL` short-circuit, or explicit `can_by_member(...)` check).
   Defense-in-depth via REVOKE only makes sense when the function is
   PROVABLY unreachable from authenticated callers — which means the
   `pg_policy` scan must be empty AND the SECDEF caller chain
   inventory must be complete AND no future-RLS-policy plan exists.

**Audit trail**: Every Q-D commit references this doc; this doc
references every Q-D migration. Single source of truth for the
remediation track. PMI sponsor (Ivan Lourenço) to be notified at
next quarterly touchpoint that Q-D is in progress and closing this
sprint (per accountability-advisor 2026-04-25 governance memo).

---

### Original framing (preserved for context)

Phase B' fixes V3 → V4 conversions. Phase Q-D is the orthogonal track:
SECDEF functions with NO auth gate at all + PUBLIC EXECUTE granted by
default. This is the same pattern that surfaced drift signals #7 #8 in
p54 (admin_inactivate_member, import_vep_applications) — except that
those two were addressed by ADDING a V4 gate. Phase Q-D uses the
REVOKE pattern instead (when no auth gate is needed) or REVOKE +
internal `can_by_member()` gate (when the function has legitimate
authenticated callers but should restrict to admin tier).

### Discovery summary (p55)

Of 566 SECDEF functions in `public` schema (extension-owned excluded):
- 106 (18.7%) have V4 gate (`can_by_member` or `can()`)
- 194 (34.3%) have V3-only gate (Phase B' backlog)
- 88 (15.5%) reference `auth.uid()` w/o `can_*()` (custom auth — needs per-fn audit)
- 21 (3.7%) are triggers (legitimately no auth)
- **157 (27.7%) suspicious "no gate at all"**

Of those 157, classified by intended caller:
- 27 internal helpers (called by other gated fns; lower urgency)
- 21 triggers (legitimately no gate)
- 109 orphan-no-gate external-callable (highest priority)

### Batch 1 closure (p55, `20260426001848`)

Migration: `track_q_d_secdef_public_revoke_batch1.sql`. Pattern: REVOKE
EXECUTE FROM PUBLIC, anon, authenticated. Postgres + service_role
preserved (cron + EF still work).

21 functions hardened by category:

(a) PII crypto (CRITICAL):
- `encrypt_sensitive(text)` — pgp_sym_encrypt wrapper
- `decrypt_sensitive(bytea)` — pgp_sym_decrypt wrapper. Public exposure
  meant any authenticated caller could decrypt arbitrary PII bytea.

(b) EF webhook receiver:
- `process_email_webhook(text, text, jsonb)` — Resend webhook handler.

(c) Cron-only (9 fns):
- `auto_archive_done_cards`, `auto_detect_onboarding_completions`,
  `comms_check_token_expiry`, `detect_mcp_anomalies`,
  `generate_weekly_card_digest_cron`, `send_attendance_reminders_cron`,
  `v4_expire_engagements`, `v4_expire_engagements_shadow`,
  `v4_notify_expiring_engagements`.

> **⚠ Amendment p58 (`20260426131249`)** — `comms_check_token_expiry`
> was misclassified as "cron-only" in p55. Per-fn callsite verification
> in p55 missed the admin frontend caller
> `src/pages/admin/comms.astro:669` (`loadTokenAlerts()` flow). The
> function is hybrid (writer side effect + reader): it INSERTs alerts
> idempotently AND returns active unacknowledged alerts. After p55
> REVOKE, the admin call failed silently (try/catch wrapped, console
> warn).
>
> Per Q-D matrix correct classification: **"cron + admin reader"**
> pattern. Treatment: REVOKE-from-anon (already done by batch 1) +
> restore `authenticated` GRANT (this amendment). Page admin tier
> gate is the primary defense; non-admin authenticated direct
> callers can trigger idempotent detection logic + read alerts
> (channel names + expiry status, no PII) — acceptable risk per
> 3a.3b/3a.4 pattern.
>
> Post-amendment ACL: `postgres + authenticated + service_role`.
> Surfaced and resolved in p58 batch 3a.5 regression note.

(d) Dead-code admin writers (8 fns):
- `compute_application_scores`, `create_initiative`, `update_initiative`,
  `seed_pre_onboarding_steps`, `enrich_applications_from_csv`,
  `import_historical_evaluations`, `import_historical_interviews`,
  `import_leader_evaluations`. Last three are the cycle3-2026 importers
  that drift signal #4 covered (PM-blocked on archive vs parameterize;
  REVOKE non-controversial since no app callers).

(e) Admin metadata helper:
- `_audit_list_public_functions()` — created in p51 Q-C as contract-test
  helper; should be service_role-only.

Verified post-REVOKE: each fn now shows only `postgres + service_role`
ACL.

### Batch 2 closure — public-by-design readers verification (p56, docs-only)

13 SECDEF readers verified as legitimately public. No REVOKE, no gate,
no migration needed. Per-fn audit findings:

| Function | Returns | PII verdict |
|---|---|---|
| `list_taxonomy_tags()` | active taxonomy_tags rows | Reference data — none |
| `increment_blog_view(text)` | UPDATE only (no read-back) | None — idempotent counter |
| `get_current_release()` | release version/title/date | Public — release info |
| `get_changelog()` | full release history + multilingual items | Public — release notes |
| `get_help_journeys()` | persona-keyed help nav (filtered by `is_visible_to_visitors`) | Public — onboarding nav |
| `get_homepage_stats()` | aggregate counts (members, tribes, chapters, hours) | Aggregates only |
| `get_public_platform_stats()` | aggregate counts incl. retention rate | Aggregates only |
| `get_public_impact_data()` | aggregates + tribe leader names + chapter sponsors + recognitions + timeline | Intentional public exposure of leadership roles + impact metrics |
| `list_active_boards()` | board id/name/scope + item counts | Board metadata only (no card content) |
| `get_public_publications(...)` | published article metadata + authors | Authors are public-by-definition (publication credit) |
| `get_public_leaderboard(int)` | rank + member name + chapter + tribe + XP + level | Intentional gamified ranking (per ADR-0024 accepted risk on `gamification_leaderboard` view; same pattern) |
| `get_public_trail_ranking()` | name + photo + course completion stats | Intentional public trail ranking |
| `verify_certificate(text)` | cert details + member name + signers (gated by `verification_code`) | Verification by security token = intentional PII linkage; standard cert verification flow |

All 13 have `search_path` configured (`public, pg_temp` or `public`).
ACLs preserved: anon + authenticated grant intentional.

**Conclusion**: no batch 2 migration produced. Phase Q-D batch 2 is
closed as docs-only verification. The 13 fns are formally documented
as "verified public-safe" in this audit, providing a reference for
future audits.

### Batch 3a.1 closure — admin selection readers (p57, `20260426005822`)

Council-validated reshape from original 6-fn proposal. After
platform-guardian + security-engineer callsite review (2026-04-25):

**Migrated** (3 of 6):

(a) Dead-code REVOKE-only:
- `get_executive_kpis()` → REVOKE FROM PUBLIC, anon, authenticated.
  No callers in src/ or supabase/functions/. Aggregate-only output
  (active members, retention %, multi-cycle counts, etc.) but
  admin-shape per security-engineer (not public-by-design per
  ADR-0024).

(b) PII gate + REVOKE-from-public (keep `authenticated` for admin UI):
- `get_application_interviews(uuid)` → ADD internal
  `can_by_member('manage_platform')` gate + REVOKE FROM PUBLIC, anon.
  CRITICAL per security-engineer: returns interview notes +
  interviewer_ids per applicant (LGPD Art. 5/6 PII). Caller:
  `/admin/selection.astro:1553`.
- `get_application_onboarding_pct(uuid)` → ADD internal
  `can_by_member('manage_platform')` gate + REVOKE FROM PUBLIC, anon.
  Returns onboarding completion % per application. Caller:
  `/admin/selection.astro:443`. Converted from SQL to PL/pgSQL to
  accommodate gate.

Privilege expansion safety check: legacy_count=2 (Vitor SA, Fabricio SA),
v4_count=2, would_gain=null. Zero authorization change in production.

**Deferred** (3 of 6 — PM tier clarification needed):
- `get_attendance_panel(date, date)` — called from
  `HomepageHero.astro:298` (homepage, mixed-tier),
  `AttendanceDashboard.tsx:73`, `attendance.astro:2020`,
  MCP tool `index.ts:790`. Tier question: any-member or admin-only?
  Homepage caller forces decision.
- `get_meeting_notes_compliance()` — called from `MeetingsPage.tsx:155`.
  Tier question: any-member meetings page or admin compliance audit?
- `count_tribe_slots()` — called from `TribesSection.astro:291`. Tier
  question: public homepage tribe section or member-only?

Documented as open in audit doc; PM should specify tier per fn before
treatment.

**log_pii_access integration deferred**: `log_pii_access` expects
`p_target_member_id` but `selection_applications.id` ≠ `members.id`
(applicants are pre-member). Future improvement: extend
`log_pii_access` to support application-id targets, then retrofit
gates with audit calls. Tracked as Phase Q-D enhancement backlog item.

### Batch 3a.3a closure — initiative/board readers, dead+internal REVOKE-only (p58, `20260426120532`)

Migration: `track_q_d_initiative_board_readers_batch3a3a.sql`. Atomic
REVOKE-only treatment for 4 fns identified as dead (zero callers anywhere
in `src/`, `supabase/functions/`, `tests/`) or internal-only (called only
from another SECDEF fn via SECDEF chain).

**Discovery surfaced reshape**: audit doc estimated "13 fns" for the
initiative/board readers bucket; per-fn pg_proc enumeration found 23
candidates (matching `get_board_*`, `get_initiative_*`, `list_board_*`,
`list_initiative_*`, `list_meeting_artifacts`, `list_tribe_deliverables`,
`search_*board_items`). Per-fn body review + callsite grep classified:

- **3a.3a (this commit)**: 4 fns — 3 dead + 1 internal-only.
- **3a.3b (next batch, awaiting PM ratify)**: 18 fns are member-tier
  readers (initiative pages, board components, profile, presentations).
  Treatment proposal: REVOKE FROM PUBLIC + anon, KEEP authenticated.
  Per-page tier verification needed before applying (see "Open Phase
  Q-D batches" section).
- **Excluded from Q-D entirely**: `get_initiative_member_contacts`
  is **already V4-compliant** — body has
  `can(person_id, 'view_pii', 'initiative', initiative_id)` gate +
  `log_pii_access_batch` call. Discovered during 3a.3 triage by
  body review (the candidate-detection regex looked for
  `can_by_member` / `public.can(` / `is_superadmin` patterns;
  `can(...)` without `public.` prefix wasn't initially flagged as
  V4-gated). Documented as reference compliant pattern: when a
  reader RPC uses `can(person_id, action, scope, resource_id)` it
  IS V4 — we don't need to migrate it.

**Migrated** (4 of 4):

(a) Dead-code REVOKE-only (3 fns):
- `get_board_timeline(uuid)` — board timeline reader. Body uses
  `members.tribe_id` (legacy column path; ADR-0015 Phase 5 backlog).
  Currently live in pg_proc but unreachable from any caller (no
  `.rpc('get_board_timeline'...)` anywhere; only typed in
  `src/lib/database.gen.ts` which is auto-generated from `pg_proc`).
- `get_initiative_board_summary(uuid)` — count-by-status summary for
  initiative's board. Zero callers.
- `list_initiative_meeting_artifacts(integer, uuid)` — meeting
  artifacts filtered by initiative. Zero callers (initiative pages
  use `list_meeting_artifacts` which is initiative-id-aware via
  `resolve_tribe_id`; this fn was redundant from day 1).

(b) Internal helper REVOKE-only (1 fn):
- `search_board_items(text, integer)` — board search. Only callsite
  is `public.search_initiative_board_items` (also SECDEF, postgres-
  owned). REVOKE from PUBLIC/anon/authenticated; SECDEF chain
  preserves access via postgres role
  (`search_initiative_board_items` runs as definer when called by
  authenticated user → can call REVOKE'd fn through superuser
  implicit privileges).

Verified post-REVOKE: each fn now shows only `postgres + service_role`
ACL.

**Risk: zero**. No frontend or EF callsite is broken. Static analysis
contract test (`tests/contracts/initiative-primitive.test.mjs`)
verifies the original GRANT in v4_phase2 migration file — REVOKE in
this NEW file is independent and doesn't affect the static migration
content check.

### Batch 3a.3b closure — initiative/board member-tier readers REVOKE-from-anon (p58, `20260426123542`)

Migration: `track_q_d_initiative_board_readers_batch3a3b.sql`. Atomic
treatment for 18 member-tier readers via REVOKE EXECUTE FROM PUBLIC, anon
(KEEP authenticated, postgres, service_role).

**Per-page tier verification** (this commit, all caller files audited):
- `initiative/[id].astro`, `tribe/[id].astro`, `profile.astro` —
  `currentMember = navGetMember()` pattern, member-tier.
- `initiatives.astro` — `if (!sb || !member) return;`, member-tier.
- `admin/portfolio.astro` — `if (!member) return false;`, admin-tier
  (still member-required).
- `PresentationLayer.astro` — `if (!member) return;`, member-tier.
- `TribeKanbanIsland.tsx`, `PublicationsBoardIsland.tsx` —
  `if (!member) return false;`, member-tier.
- `TribeAttendanceTab.tsx`, `TribeGamificationTab.tsx` — use
  `navGetMember()` for context, member-tier.
- React island components (`BoardActivitiesView`, `CardDetail`,
  `InitiativeBoardWrapper`) only render when parent page has loaded
  a member; effectively member-tier.
- `search_initiative_board_items` only callsite is MCP tool (runs as
  authenticated user via OAuth2.1 → JWT → PostgREST authenticated role).

**Migrated** (18 fns):

(a) Get-readers (11 entries, 12 fns counting both `get_board_activities`
overloads):
- `get_board(uuid)`
- `get_board_activities(uuid, integer)` overload 1
- `get_board_activities(uuid, uuid, text, text)` overload 2
- `get_board_by_domain(text, integer, uuid)`
- `get_board_tags(uuid)`
- `get_initiative_attendance_grid(uuid, text)`
- `get_initiative_detail(uuid)`
- `get_initiative_events_timeline(uuid, integer, integer)`
- `get_initiative_gamification(uuid)`
- `get_initiative_members(uuid)`
- `get_initiative_stats(uuid)`

(b) List/search-readers (6 fns):
- `list_board_items(uuid, text)`
- `list_initiative_boards(uuid)`
- `list_initiative_deliverables(uuid, text)`
- `list_initiatives(text, text)`
- `list_project_boards(integer)`
- `list_tribe_deliverables(integer, text)`
- `search_initiative_board_items(text, uuid)`

(c) Excluded — verified public-by-design (kept unchanged):
- `list_meeting_artifacts(integer, integer)` — published meeting
  recordings/artifacts. Caller `presentations.astro` only checks
  `!sb` (NOT `!member`), matching the public showcase pattern of
  `/presentations` URL. Returns `ma.*` from `meeting_artifacts`
  table filtered by `is_published=true`. Columns audited (this
  commit): id, event_id, title, meeting_date, recording_url,
  agenda_items, page_data_snapshot, cycle_code, created_by,
  is_published, deliberations, organization_id, initiative_id.
  No PII columns (no email/phone/auth_id leaks). Documented as
  verified public-by-design (Q-D batch 2 verified-public pattern
  extended).

Verified post-REVOKE: each of 18 fns now shows ACL =
`postgres + authenticated + service_role`. Anon explicitly removed.
`list_meeting_artifacts` ACL preserved (`anon + authenticated +
service_role + postgres + PUBLIC`).

**Risk: low**. Frontend pages do client-side member checks BEFORE
calling these RPCs, so legitimate auth flow unaffected. Direct
anon-key PostgREST callers will hit permission denied — this is the
security improvement (closes the gap that Q-D was chartered to address).

### Batch 3a.4 closure — knowledge/wiki readers (p58, `20260426124716`)

Migration: `track_q_d_knowledge_wiki_readers_batch3a4.sql`. 9 SECDEF
readers in knowledge/wiki bucket triaged via per-fn callsite analysis:

**Live with authenticated callers — REVOKE-from-anon (4 fns)**:
- `get_wiki_page(text)` — wiki page reader. Caller: MCP tool
  `get_wiki_page` (nucleo-mcp/index.ts:1444). MCP runs authenticated
  via OAuth2.1 → JWT. Returns wiki_pages.* including content (which
  per `wiki_health_report` PII scanning — confirms members may paste
  email/phone/CPF into wiki content). Closing anon access prevents
  direct PostgREST exfiltration.
- `search_knowledge(text)` — Global Search RPC. Caller:
  `src/pages/api/search.ts:46` (W90 command palette). API route
  requires `Authorization Bearer` + valid session (returns 401 if
  absent). REVOKE FROM anon enforces the API tier at DB layer.
- `search_wiki_pages(text, integer, text, text)` — wiki FTS search.
  Caller: MCP tool `search_wiki` (nucleo-mcp/index.ts:1433).
- `wiki_health_report()` — health check report (stale pages, PII
  warnings, missing metadata). Caller: MCP tool `wiki_health_report`
  (nucleo-mcp/index.ts:1471).

**Dead — REVOKE-only full lock-down (5 fns)**:
- `knowledge_assets_latest(text, integer)` — 0 callers.
- `knowledge_search(vector, integer, text)` — vector embedding
  semantic search. 0 callers (likely future MCP integration —
  re-grant when wired).
- `knowledge_insights_backlog_candidates(text, integer)` — 0 callers.
  Already anon-clean pre-migration; tightened authenticated also for
  Q-D dead-matrix consistency.
- `knowledge_insights_overview(text, integer)` — 0 callers. Same
  pre-state as backlog_candidates.
- `knowledge_search_text(text, text, integer)` — 0 callers. Same
  pre-state.

Verified post-REVOKE (this commit):
- 4 REVOKE-from-anon fns: ACL = `postgres + authenticated +
  service_role`.
- 5 dead fns: ACL = `postgres + service_role` (full lock-down).

**Risk: zero**. No frontend, EF, scripts, or test callsite broken.
Test references to `knowledge_*` strings are unrelated (gamification
`knowledge_ai_pm` badge category, `knowledge_insights_ingestion_log`
table in log-retention test). MCP authenticated callers retain access
for the 4 live fns. Dead fns become un-callable externally; postgres
+ service_role retained for cron/EF future use if any.

### Batch 3a.5 closure — comms readers (p58, `20260426130254`)

Migration: `track_q_d_comms_readers_batch3a5.sql`. 11 SECDEF readers
in comms bucket triaged via per-fn callsite analysis:

**Live with authenticated callers — REVOKE-from-anon (9 fns)**:
- `broadcast_history(integer, integer)` — caller `admin/comms-ops.astro:256`.
- `comms_acknowledge_alert(uuid)` — caller `admin/comms.astro:681`.
  Uses `auth.uid()` but no V4 gate (admin-shape; surfaced as
  Phase B'' candidate for `manage_comms` action).
- `comms_channel_status()` — caller `admin/comms.astro:587, 692`.
- `comms_metrics_latest_by_channel(integer)` — caller
  `admin/comms.astro` (multiple) + MCP. Pre-state already lacked
  PUBLIC.
- `comms_top_media(text, integer, integer)` — caller
  `admin/comms.astro:534`.
- `get_comms_dashboard_metrics()` — caller
  `CommsDashboard.tsx:49` + MCP.
- `get_webinar_lifecycle(uuid)` — caller `admin/webinars.astro:604`
  + presence verified in `tests/ui-stabilization.test.mjs:101`.
- `list_webinars_v2(text, text, integer)` — caller `webinars.astro:19`
  (member tier, navGetMember bail), `admin/webinars.astro:691`
  (admin), MCP.
- `webinars_pending_comms()` — caller `admin/comms-ops.astro:216`
  + MCP.

**Dead — REVOKE-only full lock-down (2 fns)**:
- `comms_executive_kpis()` — executive aggregate metrics
  (audience, reach, engagement, growth %). 0 callers.
- `publish_comms_metrics_batch(text, date)` — writer (UPDATE
  comms_metrics_daily); has internal V3 gate
  (`can_manage_comms_metrics`) but 0 external callers. Pre-state
  ACL had anon grant. Treatment per Q-D dead-matrix consistency:
  full lock-down (V3 gate becomes moot but preserved in body).

**Out-of-scope (4 fns documented for follow-up)**:
- `admin_manage_comms_channel` — V3-gated admin writer
  (is_superadmin + operational_role + designations). Phase B''
  candidate.
- `auto_comms_card_on_publish` — trigger function. Internal
  helper batch 3b.
- `can_manage_comms_metrics` — V3 helper fn used by
  publish_comms_metrics_batch. Internal helper batch 3b.
- **`comms_check_token_expiry`** — REGRESSION ✅ **RESOLVED p58**
  via Option 1a: restored `authenticated` GRANT
  (`20260426131249_track_q_d_batch1_amend_comms_check_token_expiry_grant`).
  Reclassified from "cron-only" → "cron + admin reader" pattern in
  batch 1 closure section above. Post-amendment ACL: `postgres +
  authenticated + service_role`. Admin/comms.astro:669
  `loadTokenAlerts()` flow restored. Page-level admin tier gate
  remains primary defense; non-admin authenticated direct callers
  trigger idempotent detection + read alerts (channel names +
  expiry status, no PII) — acceptable per 3a.3b/3a.4 pattern.
  *Original regression discovery context preserved below for
  audit trail*:
  > Per-fn callsite verification in p55 batch 1 missed this admin
  > frontend caller; post-batch-1 the call failed silently
  > (try/catch wrapped, console.warn). Reclassification + GRANT
  > restoration applied p58.

Verified post-REVOKE (this commit):
- 9 REVOKE-from-anon fns: ACL = `postgres + authenticated +
  service_role`.
- 2 dead fns: ACL = `postgres + service_role` (full lock-down).

**Risk: low**. Authenticated callers via admin pages and MCP
preserved on the 9 live fns. Dead fns become un-callable
externally; postgres + service_role retained.

### Batch 3a.6 closure — curation/governance readers (p58, `20260426132442`)

Migration: `track_q_d_curation_governance_readers_batch3a6.sql`. 22
SECDEF readers/helpers in curation/governance bucket triaged via
per-fn body + callsite analysis:

**Live with authenticated callers — REVOKE-from-anon (9 fns)**:
- `get_chain_workflow_detail(uuid)` — approval chain workflow detail.
  Caller: ReviewChainIsland.tsx + admin/governance/documents.astro.
- `get_cr_approval_status(uuid)` — CR approval status + sponsor list.
  Caller: GovernanceApprovalTab.tsx.
- `get_decision_log(text)` — wiki ADR catalog reader. Caller: MCP.
- `get_document_detail(uuid)` — full governance document detail.
  Caller: MCP. Hard auth check (RAISE EXCEPTION).
- `get_pending_ratifications()` — IP-2 ratification queue. Caller:
  governance/ip-agreement.astro + admin + MCP. Soft auth.
- `get_version_diff(uuid, uuid, boolean)` — version diff. Caller: MCP.
  Hard auth check.
- `list_curation_board(text)` — hub_resources curation board. Caller:
  CuratorshipBoardIsland.tsx.
- `list_document_comments(uuid, boolean)` — version comments with
  visibility filter. Caller: ClauseCommentDrawer.tsx + MCP. Soft
  auth + curator/manager designation filter.
- `list_document_versions(uuid)` — version list. Caller: MCP. Soft
  auth.

**Dead — REVOKE-only full lock-down (2 fns)**:
- `get_curation_cross_board()` — cross-board curation aggregator.
  0 callers.
- `get_governance_preview()` — change_requests aggregates +
  manual_structure preview. 0 callers (likely superseded by
  get_governance_dashboard).

**Out-of-scope — Phase B'' V3 admin gate candidates (3 fns)**:
- `get_change_requests(text, text)` — V3 gate (is_sa + op_role +
  designations).
- `get_governance_dashboard()` — V3 gate.
- `get_governance_documents(text)` — V3 gate.

**Excluded — already V4-compliant via `can_by_member` (8 fns)**:
- `get_chain_audit_report(uuid)`, `get_chain_for_pdf(uuid)`,
  `get_curation_dashboard()`, `get_governance_change_log(...)`,
  `get_governance_stats()`, `get_ratification_reminder_targets(uuid)`,
  `list_curation_pending_board_items()`, `list_pending_curation(text)`.

Verified post-REVOKE (this commit):
- 9 REVOKE-from-anon fns: ACL = `postgres + authenticated +
  service_role`.
- 2 dead fns: ACL = `postgres + service_role` (full lock-down).

**Risk: low**. Authenticated callers via admin pages, member
components, and MCP preserved. Dead fns become un-callable externally;
postgres + service_role retained.

### Batch 3a.7 closure — sustainability/KPI readers (p58, `20260426133716`)

Migration: `track_q_d_sustainability_kpi_readers_batch3a7.sql`. 17
SECDEF readers/writers in sustainability/KPI bucket triaged via
per-fn body + callsite analysis:

**Live with authenticated callers — REVOKE-from-anon (12 fns)**:
- `exec_portfolio_board_summary(boolean)` — caller admin/portfolio.astro.
- `get_annual_kpis(integer, integer)` — annual KPI dashboard. Caller
  admin/portfolio.astro + MCP. Body uses operational_role for
  member filtering (display, not gate).
- `get_cost_entries(...)` — caller admin/sustainability.astro.
- `get_cycle_evolution()` — caller admin/cycle-report.astro.
- `get_cycle_report(integer)` — caller ReportPage.tsx. Body uses
  operational_role for by_role aggregation (display, not gate).
- `get_kpi_dashboard(date, date)` — caller workspace/KpiDashboard.tsx.
- `get_pilot_metrics(uuid)` — caller usePilots.ts + admin/pilots.astro.
- `get_pilots_summary()` — caller usePilots.ts + admin/pilots.astro.
- `get_portfolio_dashboard(integer)` — caller usePortfolio.ts + MCP.
- `get_revenue_entries(...)` — caller admin/sustainability.astro.
- `get_sustainability_dashboard(integer)` — caller
  admin/sustainability.astro.
- `get_sustainability_projections(integer)` — caller
  admin/sustainability.astro.

**Verified public-by-design — no change (1 fn)**:
- `exec_portfolio_health(text)` — annual KPI portfolio health metrics
  (chapters_participating, partner_entities, certification_trail %,
  cpmai_certified, articles_published, webinars_completed,
  ia_pilots, meeting_hours, impact_hours + quarter targets).
  Body returns aggregate counts/percentages/sums only — NO PII.
  Callers: `src/components/sections/TrailSection.astro:214` +
  `src/components/sections/KpiSection.astro:84`. Both sections
  imported by `src/pages/index.astro` (and en/, es/) — homepage
  public pages. Both call via `getSupabase()` (anon key) without
  any `!member` bail check. Documented as verified public-by-design
  (Q-D batch 2 pattern extended).

**Out-of-scope — Phase B'' V3 admin writers (4 fns documented)**:
- `delete_cost_entry(uuid)` — V3 gate (is_sa + op_role).
- `delete_revenue_entry(uuid)` — V3 gate.
- `update_kpi_target(...)` — V3 gate.
- `update_sustainability_kpi(...)` — V3 gate.

Verified post-REVOKE (this commit):
- 12 REVOKE-from-anon fns: ACL = `postgres + authenticated +
  service_role`.
- `exec_portfolio_health` ACL preserved (5-grantee public).

**Risk: low**. Authenticated callers via admin pages and MCP
preserved. exec_portfolio_health stays public-by-design (homepage
hydration). Postgres + service_role retained.

### Batch 3a.8 closure — legacy/utility readers (p59, `20260426143952`)

Migration: `track_q_d_legacy_utility_readers_batch3a8.sql`. Per-fn body
+ callsite review against the legacy/utility orphan-no-gate bucket
surfaced 32 fns (vs handoff p58 estimate of 9). Discovery wider than
expected because earlier batches focused on themed surfaces
(initiative/board, comms, sustainability, etc.) leaving the residual
catch-all larger.

**Dead readers (9 fns, 0 callers in src/ or supabase/functions/) —
full lock-down**:
- `get_communication_template(text, jsonb)` — comm template renderer.
- `get_event_audience(uuid)` — event audience rules + invited members.
- `get_manual_diff()` — manual versioning diff helper.
- `get_platform_setting(text)` — platform setting reader.
- `get_publication_detail(uuid)` — single publication reader (incl.
  view counter UPDATE side effect — caller page never built).
- `get_section_change_history(uuid)` — manual section CR history.
- `list_admin_links()` — admin nav links.
- `tribe_impact_ranking()` — tribe-level impact aggregate.
- `why_denied(uuid, text, text, uuid)` — V4 authority debug helper.

**Service-role-only callers (MCP EF only — calls via service_role)
— full lock-down (2 fns)**:
- `log_mcp_usage(uuid, uuid, text, boolean, text, integer, text)` — MCP
  usage logger called by every MCP tool.
- `search_partner_cards(text, text, text, integer)` — MCP cross-partner
  card search wrapper.

**Member-tier readers — REVOKE-from-anon (keep authenticated, 19 fns)**:
- `get_card_timeline(uuid)` — caller CardDetail.tsx + MCP tool.
- `get_event_tags(uuid)` / `get_event_tags_batch(uuid[])` — caller
  attendance.astro (member-tier with bail).
- `get_events_with_attendance(integer, integer)` — caller attendance.astro.
- `get_global_research_pipeline()` — caller ResearchPipelineWidget
  (admin-tier client guard) + MCP.
- `get_item_assignments(uuid)` / `get_item_curation_history(uuid)` —
  caller CardDetail.tsx (board UI member-tier).
- `get_member_cycle_xp(uuid)` — caller profile.astro + MCP.
- `get_mirror_target_boards(uuid)` — caller CardDetail.tsx.
- `get_near_events(uuid, integer)` — caller workspace.astro + MCP.
- `get_previous_locked_version(uuid)` — caller ReviewChainIsland
  (governance member-tier).
- `get_publication_pipeline_summary()` — caller admin/publications.astro
  (admin-tier).
- `get_publication_submission_detail(uuid)` — caller submissions/[id].astro
  + admin/publications.astro.
- `get_publication_submissions(submission_status, integer)` — caller
  publications.astro `loadMySubmissions()` (bails on `!member`) +
  workspace.astro + submissions.astro + admin/publications.astro.
- `get_recent_events(integer, integer)` — caller AttendanceForm.tsx.
- `get_tags(text)` — caller TagManagementIsland (admin) + attendance.astro.
- `list_cycles()` — caller `lib/cycles.ts loadCycles()` with
  `getFallbackCycles()` safety; loaded only by member/admin pages
  (profile, tribe, admin/analytics, admin/settings, admin/selection).
- `list_radar_global(integer, integer)` — caller tribe/[id].astro
  (member-tier with `canExploreTribes` gate).
- `search_hub_resources(text, text, integer)` — caller library.astro +
  MCP. Fn body has `auth.uid()` member check (returns empty for non-member).

**Verified public-by-design — no migration needed (2 fns, docs-only)**:
- `get_manual_sections(text)` — returns public regulamento sections.
  Caller: `governance.astro` (PUBLIC route — no `requireAuth`),
  `GovernancePage.tsx` (explicit dev comment "anon-safe RPC"),
  `ManualDocumentViewer.tsx`. Body returns manual_sections rows where
  `is_current=true`. NO PII. Intentional public exposure of governance
  documentation.
- `get_gp_whatsapp()` — returns the project manager's WhatsApp phone
  for help-page direct contact. Caller: `help.astro` (PUBLIC route).
  Body uses `members WHERE operational_role='manager'` to derive contact
  (filter, not gate — V3_legacy classification was regex false-positive).
  Phone is intentionally exposed to visitors via WhatsApp button per
  ADR-0024 pattern (similar to `get_public_impact_data` exposing
  leadership contact info).

Verified post-REVOKE (this commit):
- 11 dead/EF-only fns: ACL = `postgres + service_role`.
- 19 REVOKE-from-anon fns: ACL = `postgres + authenticated + service_role`.
- 2 verified-public fns: ACL preserved (5-grantee public).

**Risk: low**. All 19 member-tier callers verified to bail on `!member`
client-side OR sit behind admin-tier gate. Dead fns confirmed via
tight grep (`.rpc('<name>')` regex, not loose substring match).

### Batch 3b closure — internal helpers REVOKE (p59, `20260426145632`)

Migration: `track_q_d_internal_helpers_batch3b.sql`. Defense-in-depth
sweep on SECDEF functions called only by other SECDEF functions
(or by EF via service_role). The `authenticated`/PUBLIC grant on
these is unused attack surface; removing it is safe because:
* SECDEF caller chain runs as definer (postgres role) — chain still
  works since postgres retains EXECUTE.
* EF callers (MCP, sync-artia) connect as service_role — service_role
  retains EXECUTE.

20 fns triaged via:
1. tight `.rpc('<name>')` regex grep across `src/` + `supabase/functions/`
   → confirmed 0 frontend callers.
2. `pg_proc.prosrc` regex `\m<name>\s*\(` to count SECDEF callers in
   the live database → confirmed each is internally called.

**Hardened (REVOKE FROM PUBLIC, anon, authenticated, 20 fns)**:

| Bucket | Function | SECDEF callers | EF callers |
|---|---|---|---|
| Governance | `_enqueue_gate_notifications(uuid, text, text)` | lock_document_version, trg_approval_signoff_notify_fn | — |
| Analytics | `analytics_member_scope(text, integer, text)` | exec_certification_delta, exec_chapter_roi, exec_funnel_summary, exec_impact_hours_v2 | — |
| Analytics | `exec_analytics_v2_quality(text, integer, text)` | 0 (orchestrator-shaped, preserved pending PM review) | — |
| Analytics | `exec_certification_delta(text, integer, text)` | 0 (preserved pending PM review) | — |
| Analytics | `exec_chapter_roi(text, integer, text)` | exec_analytics_v2_quality | — |
| Analytics | `exec_funnel_summary(text, integer, text)` | exec_analytics_v2_quality | — |
| Analytics | `exec_impact_hours_v2(text, integer, text)` | exec_analytics_v2_quality | — |
| Adoption | `get_auth_provider_stats()` | get_adoption_dashboard | — |
| Adoption | `get_impact_hours_excluding_excused()` | get_admin_dashboard | sync-artia |
| Adoption | `get_mcp_adoption_stats()` | get_adoption_dashboard | nucleo-mcp |
| V4 authority | `can(uuid, text, text, uuid)` | activate_initiative, can_by_member, create_initiative_event, get_active_engagements, get_initiative_member_contacts, get_person, manage_initiative_engagement, rls_can | — |
| V4 authority | `can_by_member(uuid, text, text, uuid)` | 100 SECDEF V4 admin fns | nucleo-mcp (canV4 wrapper) |
| V4 authority | `assert_initiative_capability(uuid, text)` | list_initiative_boards, list_initiative_deliverables, list_initiative_meeting_artifacts, search_initiative_board_items | — |
| V4 authority | `auth_org()` | create_initiative, join_initiative, list_initiatives | — |
| Onboarding | `check_pre_onboarding_auto_steps(uuid)` | admin_update_application, finalize_decisions, get_candidate_onboarding_progress | — |
| Offboarding | `detect_orphan_assignees_from_offboards(uuid)` | notify_offboard_cascade | — |
| Members | `get_member_tribe(uuid)` | exec_tribe_dashboard, get_admin_dashboard, get_adoption_dashboard, get_attendance_grid, get_campaign_analytics, get_my_member_record, get_tribe_attendance_grid, sign_volunteer_agreement | — |
| Broadcast | `broadcast_count_today(integer)` | broadcast_count_today_v4 | — |
| Broadcast | `broadcast_count_today_v4(uuid)` | 0 (preserved pending PM review of broadcast pipeline) | — |
| Refresh | `refresh_cycle_tribe_dim()` | trigger_refresh_cycle_tribe_dim | — |

**3 fns flagged for PM review (preserved, REVOKE applied as
defense-in-depth)**:
- `broadcast_count_today_v4(uuid)` — V4 broadcast helper, 0 callers
  detected. May be cron-orchestrated or planned-but-unwired.
- `exec_analytics_v2_quality(text, integer, text)` — orchestrator that
  calls 3 sub-helpers. 0 callers detected; possibly cron or admin
  RPC integration.
- `exec_certification_delta(text, integer, text)` — analytics
  sub-query. 0 callers detected.

For all 3, REVOKE removes attack surface today; PM may either confirm
orchestrator/cron caller (no rollback needed since service_role
retained) or schedule for DROP if confirmed dead.

Verified post-REVOKE (this commit):
- All 20 fns: ACL = `postgres + service_role`.

**Risk: low**. SECDEF chains run as definer (postgres) → calls succeed.
EF callers connect as service_role → calls succeed. No frontend
`.rpc()` callers exist for any of the 20.

**Closes Phase Q-D internal-helper bucket**. Estimated 27 from p55
discovery → 20 captured here; residual ~7 are V3-gated helpers
(`current_member_tier_rank`, `can_manage_knowledge`,
`can_manage_comms_metrics`, `_can_sign_gate`, `_can_manage_event`,
etc.) which require Phase B'' V3→V4 migration before treatment.

### Phase Q-D running tally (post batches 1+2+3a.1+3a.3a+3a.3b+3a.4+3a.5+3a.6+3a.7+3a.8+3b + batch 1 amendment)

- **137 functions hardened** (21 batch 1 + 3 batch 3a.1 + 4 batch 3a.3a
  + 18 batch 3a.3b + 9 batch 3a.4 + 11 batch 3a.5 + 9 batch 3a.6 +
  12 batch 3a.7 + 30 batch 3a.8 + 20 batch 3b + amendment-only 1
  (`comms_check_token_expiry`)).
- **17 functions verified public-safe** (13 batch 2 + 1 batch 3a.3b
  excluded — `list_meeting_artifacts` + 1 batch 3a.7 excluded —
  `exec_portfolio_health` + 2 batch 3a.8 — `get_manual_sections`,
  `get_gp_whatsapp`).
- **9 functions already V4-compliant** (1 batch 3a.3 + 8 batch 3a.6
  excluded).
- 3 functions deferred for PM tier clarification (batch 3a.1).
- 11 functions documented as out-of-scope V3 (Phase B'') (3 batch 3a.5
  helpers + 3 batch 3a.6 admin fns + 4 batch 3a.7 writers + 1 trigger).
- **Net: 166 fns triaged total** vs original p55 estimate of 109.
  The +57 surplus reflects (a) V4 fns hidden by p55 detection regex
  (which matched `can_by_member` but missed `can(person_id, ...)`
  without `public.` prefix) — per-fn body review in batches 3a.3 +
  3a.6 surfaced 9 such fns; (b) the legacy/utility bucket (3a.8) and
  internal helpers bucket (3b) were not in the original 109 and added
  50 hardened + 2 verified-public.
- **Phase Q-D external-callable + internal-helper sweep effectively
  closed.** Residual: 3 PM-deferred (3a.1 selection readers) +
  11 V3-gated fns documented for Phase B'' ratify. No remaining
  orphan-no-gate fns with anon EXEC.
- Pattern proven: REVOKE-only migration is non-disruptive when
  callsites are verified; REVOKE-from-public + internal gate works
  for admin frontend callers; REVOKE-from-anon (keep authenticated)
  works for member-tier readers with verified bail-on-no-member
  client guards; docs-only verification works for public-safe fns;
  per-fn body review surfaces false positives (already-V4-gated
  readers); dead-matrix uniformly applies full lock-down regardless
  of pre-existing partial revocations; **per-fn callsite verification
  catches batch 1 regressions** (p58 surfaced
  `comms_check_token_expiry` admin caller missed in p55);
  **defense-in-depth REVOKE on internal helpers is safe** when SECDEF
  caller chain runs as definer (postgres) and EF callers connect as
  service_role (batch 3b proved on V4 authority core `can` /
  `can_by_member`).

### Open Phase Q-D batches (TBD)

Reader fns to triage for PII/sensitivity:
- Selection readers (admin-shape): `get_application_interviews`,
  `get_application_onboarding_pct`, `get_attendance_panel`,
  `get_diversity_dashboard` (already V3-gated → Phase B''),
  `get_meeting_notes_compliance`, `get_executive_kpis`, etc.
- ✅ **Public-by-design readers (verified p56, no migration needed)**:
  13 fns audited via per-fn body review. All return either aggregate
  counts, public publication metadata, gamified leaderboards (member
  name + chapter + tribe + XP — intentional public exposure per
  ADR-0024), public release notes, navigation help, taxonomy
  reference data, or certificate verification (PII linkage by
  verification_code is intentional — code is a security token printed
  on the cert document). All have `search_path` set. ACLs preserved
  (intentional anon + authenticated grant). Verified clean:
  `get_public_impact_data`, `get_public_leaderboard`,
  `get_public_platform_stats`, `get_public_publications`,
  `get_public_trail_ranking`, `verify_certificate`,
  `increment_blog_view`, `list_active_boards`, `get_homepage_stats`,
  `get_changelog`, `get_current_release`, `list_taxonomy_tags`,
  `get_help_journeys`. See "Phase Q-D batch 2 closure" section below.
- ✅ **Initiative/board readers — closure complete (p58)**:
  - **3a.3a closed (4 fns REVOKE-only)**: see "Batch 3a.3a closure"
    section below — `get_board_timeline`,
    `get_initiative_board_summary`, `list_initiative_meeting_artifacts`,
    `search_board_items`.
  - **3a.3b closed (18 fns REVOKE-from-anon)**: see "Batch 3a.3b
    closure" section below. Member-tier readers; per-page tier
    verification confirmed all callers bail on `!member` client-side.
    - **Get-readers (13)**: `get_board(uuid)`,
      `get_board_activities(uuid, integer)` overload 1,
      `get_board_activities(uuid, uuid, text, text)` overload 2,
      `get_board_by_domain(text, integer, uuid)`,
      `get_board_tags(uuid)`, `get_initiative_attendance_grid(uuid, text)`,
      `get_initiative_detail(uuid)`,
      `get_initiative_events_timeline(uuid, integer, integer)`,
      `get_initiative_gamification(uuid)`,
      `get_initiative_members(uuid)`,
      `get_initiative_stats(uuid)`,
      `list_initiative_boards(uuid)`,
      `list_initiative_deliverables(uuid, text)`.
    - **List/search-readers (5)**: `list_board_items(uuid, text)`,
      `list_initiatives(text, text)`,
      `list_meeting_artifacts(integer, integer)`,
      `list_project_boards(integer)`,
      `list_tribe_deliverables(integer, text)`,
      `search_initiative_board_items(text, uuid)`.
    - **Per-page tier verification still needed** for some pages
      before bulk REVOKE (e.g., `presentations.astro` should
      verify member-tier, not public-tier display flow).
  - **Excluded (already V4-compliant)**:
    `get_initiative_member_contacts(uuid)` — body has
    `can(person_id, 'view_pii', 'initiative', initiative_id)`
    gate + `log_pii_access_batch` call. Reference compliant pattern.
- ✅ **Knowledge / wiki readers — closure complete (p58 batch 3a.4)**:
  9 fns triaged via per-fn callsite analysis (4 live REVOKE-from-anon
  + 5 dead REVOKE-only full lock-down). See "Batch 3a.4 closure"
  section below.
- ✅ **Comms readers — closure complete (p58 batch 3a.5)**:
  11 fns triaged (9 live REVOKE-from-anon + 2 dead REVOKE-only).
  4 fns out-of-scope (1 V3 admin writer → Phase B'', 2 internal
  helpers → batch 3b, 1 batch 1 regression note → RESOLVED p58 via
  amendment migration). See "Batch 3a.5 closure" section below.
- ✅ **Curation / governance readers — closure complete (p58 batch 3a.6)**:
  22 fns triaged (9 live REVOKE-from-anon + 2 dead REVOKE-only +
  3 V3 → Phase B'' + 8 already-V4-compliant excluded). See "Batch
  3a.6 closure" section below.
- ✅ **Sustainability / KPI readers — closure complete (p58 batch 3a.7)**:
  17 fns triaged (12 live REVOKE-from-anon + 1 verified public-by-design
  `exec_portfolio_health` + 4 V3 → Phase B''). See "Batch 3a.7 closure"
  section below.
- ✅ **Legacy/utility readers — closure complete (p59 batch 3a.8)**:
  32 fns triaged (9 dead REVOKE-only + 2 EF-only REVOKE-only + 19 live
  REVOKE-from-anon + 2 verified public-by-design — `get_manual_sections`,
  `get_gp_whatsapp`). See "Batch 3a.8 closure" section below.
- ✅ **Internal helpers — closure complete (p59 batch 3b)**:
  20 fns REVOKE'd FROM PUBLIC, anon, authenticated as defense-in-depth.
  All 20 verified to have 0 frontend `.rpc()` calls and only SECDEF / EF
  service_role callers. Includes V4 authority core (`can` /
  `can_by_member`). See "Batch 3b closure" section below.

**Phase Q-D external-callable + internal-helper sweep is effectively
closed.** Residual work:
  * 3 PM-deferred selection readers (batch 3a.1): `get_attendance_panel`,
    `get_meeting_notes_compliance`, `count_tribe_slots`.
  * 11 V3-gated fns documented for Phase B'' (new V4 actions: `manage_comms`,
    `manage_finance`, etc. — each requires PM ratify per ADR).

### Phase Q-D vs Phase B' — when to use which

| Pattern | Symptom | Treatment | Track |
|---|---|---|---|
| V3 gate present, V4 missing | `is_superadmin OR operational_role IN (...)` | Replace gate with `can_by_member()` | Phase B' |
| No gate at all + intended for human admin | SECDEF + zero auth check, called from admin UI | Add `can_by_member()` gate | Drift signal pattern (#7 #8) |
| No gate at all + intended for cron/EF/dead | SECDEF + zero auth check, no human caller | REVOKE FROM anon, authenticated | Phase Q-D |
| Custom path-aware gate (interviewer-id, committee-membership, chain helper) | RPC-specific auth that doesn't map to V4 actions | Leave V3 + skip filter, escalate to Phase B'' if expanding | Phase B'' |
| Anon SELECT grant on table where RLS denies anon reads | pg_graphql exposes schema + unused attack surface | REVOKE SELECT FROM anon | Track R |
| Anon SELECT grant + RLS policy permits anon reads | Verify policy is correctly scoped (no PII leak) | Either tighten policy OR document intent | Track R Phase R2 |

---

## Track R — pg_graphql anon table exposure

### Trigger (p59)

Supabase advisor `pg_graphql_anon_table_exposed` lint surfaced 165
WARN entries in p59 (advisor count went from 1 ERROR + 5 WARN p58
baseline to 1 ERROR + 171 WARN p59). The lint warns that pg_graphql
extension is installed and the `anon` role has SELECT on a specific
table. Schema metadata (column names, types, comments) is exposed
via the GraphQL endpoint regardless of RLS row-level access.

### Methodology

1. **Discovery**: `pg_class.relacl` parsed for explicit `anon=` SELECT
   grants across `public.*` and `z_archive.*`. Cross-referenced with
   `pg_class.relrowsecurity` and `pg_policy.polroles` to determine
   whether the table also has an RLS policy permitting anon reads.

2. **Caller inventory**: tight `.from('<table>')` regex grep across
   `src/` to identify anon-tier callers. Tables with non-zero anon-
   tier callers must retain SELECT grant or homepage breaks.

3. **Categorization**:
   - `has_anon_select_policy=false` AND 0 anon-tier .from() callers
     → REVOKE-safe (defense-in-depth, no behavior change).
   - `has_anon_select_policy=true` (RLS permits anon reads) → Phase
     R2 per-policy review needed.
   - z_archive.* → all REVOKE-safe (archived, 0 callers).

### Batch 1 closure (p59, `20260426152751`)

Migration: `track_r_pg_graphql_anon_revoke_batch1.sql`. 102 objects
REVOKE'd:
- **25 z_archive.* tables**: archived legacy, 0 callers.
- **70 public.* tables**: RLS already blocks anon reads + 0 anon-tier
  .from() callers. Categories include admin/audit, LGPD/PII, V4
  authority, notifications, initiatives, board, comms, curation,
  knowledge, sustainability, selection, partner, publication,
  member-tier, misc.
- **7 views**: 0 anon-tier .from() callers.

**PRESERVED** (anon-tier .from() readers — REVOKE would break homepage):
- `public.hub_resources` (ResourcesSection.astro, library.astro)
- `public.site_config` (ChaptersSection, WeeklyScheduleSection,
  ReportPage)

**PRESERVED** (intentional public per ADR-0024 / ADR-0010):
- `public.public_members` (advisor ERROR — accepted risk per ADR-0024)
- `public.members_public_safe` (intentional public view)

**PRESERVED** (RLS policies permit anon reads — Phase R2 backlog,
70 tables): tables that already have selective anon RLS policies.
Each requires per-table policy review to confirm intent (public-by-
design vs accidental over-grant). Examples include `members`,
`attendance`, `gamification_points`, `board_*`, `blog_*`, `events`,
`webinars`, `chapters`, `cycles`, `pilots`, `releases`, etc.

**Verification**:
- `pg_class.relacl` post-state confirmed `anon=awdDxtm` (no SELECT)
  for all 102 objects.
- authenticated + service_role grants retained throughout (admin
  pages + EFs unaffected).

**Advisor reduction**:
- Before: 1 ERROR + 171 WARN
- After:  1 ERROR + **75 WARN**  (-96 / -56% reduction)
- pg_graphql_anon_table_exposed: 165 → 70 (-95 / -58%)

### Batch 2 closure (p59, `20260426155255`) — Phase R2 per-policy review

Migration: `track_r_pg_graphql_anon_revoke_batch2.sql`. 50 REVOKEs
applied to tables that retained anon SELECT after batch 1 (because
their RLS policies could permit anon reads). Per-policy classification:

**A. RLS USING `false` (rpc_only_deny_all) — 14 tables**:
RLS denies all anon reads regardless of grant. REVOKE-safe (defense-
in-depth, no behavior change).
- blog_likes, board_members, board_source_tribe_map,
  board_taxonomy_alerts, campaign_recipients,
  knowledge_insights_ingestion_log, onboarding_progress,
  partner_attachments, selection_applications, selection_committee,
  selection_cycles, selection_diversity_snapshots, selection_evaluations,
  selection_interviews

**B. RLS USING `auth.uid() = ...` (member-scoped) — 7 tables**:
anon's `auth.uid()` is NULL → policy fails → 0 rows.
- analysis_results, comparison_results, evm_analyses, risk_simulations,
  tia_analyses, user_profiles, campaign_sends

**C. RLS USING `rls_is_member()` or `auth.role() = 'authenticated'` — 2**:
- publication_series, tribe_deliverables

**D. V4 `org_id = auth_org() OR org_id IS NULL` — 21 tables**:
anon's `auth_org()` returns NULL after batch 3b REVOKE on `auth_org()`
→ policy denies (only org_id IS NULL rows would be visible, but no such
data exists in production for these tables). Cross-referenced with
`.from()` callers: only member/admin-tier flows; queries always use
`MEMBER.id` filter or admin context.
- annual_kpi_targets, attendance, board_items, board_lifecycle_events,
  board_sla_config, certificates, change_requests, chapters,
  comms_channel_config, curation_review_log, event_showcases,
  member_activity_sessions, member_cycle_history, members,
  meeting_artifacts, partner_entities, pilots, project_boards,
  project_memberships, publication_submissions, volunteer_applications
- + visitor_leads (REVOKE SELECT only — `Anyone can submit lead` INSERT
  policy preserved for ImpactPageIsland contact form)

**E. z_archive.* legacy — 4 tables**: archived, 0 callers.
- member_chapter_affiliations, portfolio_data_sanity_runs,
  publication_submission_events, presentations

**F. View — 1**: impact_hours_total (member-tier attendance.astro caller).

**Total**: 50 REVOKEs.

**PRESERVED — 20 intentional public objects** (pg_graphql exposure
by design):

Homepage / anon-tier .from() callers (8):
- announcements (AnnouncementBanner on all pages)
- blog_posts (blog public pages)
- events (HeroSection, HomepageHero)
- home_schedule (lib/schedule.ts)
- hub_resources (ResourcesSection, library)
- site_config (ChaptersSection, WeeklyScheduleSection, ReportPage)
- tribe_meeting_slots (homepage)
- tribes (TribesSection, HeroSection, HomepageHero)

Public reference data with explicit `USING true` policies (8):
- courses, cycles, help_journeys, ia_pilots,
  offboard_reason_categories, quadrants, release_items, releases

Public KPI / publication / certification (4):
- portfolio_kpi_quarterly_targets, portfolio_kpi_targets,
  public_publications, webinars

Intentional public views per ADR-0024 (2):
- public_members (advisor ERROR — accepted risk)
- members_public_safe

Plus gamification leaderboard data (anon-readable per
`gamification.astro` public leaderboard flow):
- gamification_points
- tribe_selections

### Track R final state (p59 close)

**Cumulative advisor reduction**:
- Pre-Track R: 1 ERROR + 171 WARN
- After batch 1: 1 ERROR + 75 WARN  (-56%)
- After batch 2: 1 ERROR + **25 WARN**  (-85% cumulative from 171)
- `pg_graphql_anon_table_exposed`: 165 → 70 → **20** (-88%)

The 20 remaining `pg_graphql_anon_table_exposed` lints are all
**intentional public exposures** documented above. They represent
either homepage data sources, public-by-design reference data,
public KPI dashboards, or ADR-0024 accepted risk views. No further
REVOKE work needed — these tables/views are correctly anon-readable
and the lint is informational rather than actionable.

**Phase R3 (optional, not urgent)**: per-table `COMMENT ON TABLE`
documentation to inline-justify each preserved anon grant per
ADR-0024 pattern. This would suppress the lint output for
`get_advisors` reviews. Effort: ~1h. Not blocking.

### Track R closure path — COMPLETE p59

Track R formally closes at p59 with 152 REVOKEs across 2 batches
(102 + 50). All non-intentional anon table exposures eliminated.
Remaining 20 `pg_graphql_anon_table_exposed` lints reflect
intentional public surface that the platform legitimately exposes
(homepage data + public reference + ADR-0024 views).
