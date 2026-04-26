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
4. Classify per matrix above.
5. Run privilege expansion safety check if adding gate.
6. Apply migration (REVOKE + optional gate). If only verification
   needed, docs-only commit.
7. Verify post-state via ACL + body recheck.

**Batch plan**:
- Batch 1 (p55, done): 21 fns hardened (PII crypto + cron + EF webhook + dead admin).
- Batch 2 (p56, done): 13 public-by-design readers verified safe (docs-only).
- Batch 3a (in progress p57+): admin-shape readers, 30-40 fns total. Sub-batches of 6-10.
- Batch 3b (TBD): 27 internal helpers REVOKE (defense-in-depth).

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

### Phase Q-D running tally (post batches 1+2+3a.1+3a.3a+3a.3b+3a.4+3a.5+3a.6+3a.7 + batch 1 amendment)

- **87 functions hardened** (21 batch 1 + 3 batch 3a.1 + 4 batch 3a.3a
  + 18 batch 3a.3b + 9 batch 3a.4 + 11 batch 3a.5 + 9 batch 3a.6 +
  12 batch 3a.7 + amendment-only 1 (`comms_check_token_expiry`)).
- **15 functions verified public-safe** (13 batch 2 + 1 batch 3a.3b
  excluded — `list_meeting_artifacts` + 1 batch 3a.7 excluded —
  `exec_portfolio_health`).
- **9 functions already V4-compliant** (1 batch 3a.3 + 8 batch 3a.6
  excluded).
- 3 functions deferred for PM tier clarification (batch 3a.1).
- 11 functions documented as out-of-scope (3 V3 batch 3a.5 helpers
  + 3 V3 batch 3a.6 admin fns + 4 V3 batch 3a.7 writers + 1 trigger).
- ≈9 remaining orphan-no-gate readers in legacy/utility bucket (3a.8)
  + ≈24 internal helpers (3b) + 3 PM-deferred = ~36 still in pipeline.
- **Net: 114 fns triaged total** vs original p55 estimate of 109.
  The +5 surplus reflects V4 fns hidden by p55 detection regex
  (which matched `can_by_member` but missed `can(person_id, ...)`
  without `public.` prefix); per-fn body review in batches 3a.3 +
  3a.6 surfaced 9 such fns. **Effectively: scope p55 = 100%
  triaged; sweep continues into legacy/utility (3a.8) + internal
  helpers (3b) buckets which were not in the original 109.**
- Pattern proven: REVOKE-only migration is non-disruptive when
  callsites are verified; REVOKE-from-public + internal gate works
  for admin frontend callers; REVOKE-from-anon (keep authenticated)
  works for member-tier readers with verified bail-on-no-member
  client guards; docs-only verification works for public-safe fns;
  per-fn body review surfaces false positives (already-V4-gated
  readers); dead-matrix uniformly applies full lock-down regardless
  of pre-existing partial revocations; **per-fn callsite verification
  catches batch 1 regressions** (p58 surfaced
  `comms_check_token_expiry` admin caller missed in p55).

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
- Legacy/utility readers: `get_changelog`, `get_gp_whatsapp`,
  `get_help_journeys`, `list_admin_links`, `list_radar_global`,
  `tribe_impact_ranking`, `count_tribe_slots`, `broadcast_history`,
  `get_recent_events`, `get_event_audience`, `get_event_tags*`,
  `get_events_with_attendance`, `get_global_research_pipeline`,
  `get_card_timeline`, `get_publication_*` (4 fns), `get_section_change_history`,
  `get_webinar_lifecycle`, `get_wiki_page`, `get_revenue_entries`,
  `get_cost_entries`, `get_communication_template`, `get_item_*` (2 fns),
  `get_manual_*` (2 fns), `get_member_cycle_xp`, `get_mirror_target_boards`,
  `get_near_events`, `get_platform_setting`, `get_previous_locked_version`,
  `search_*` (3 fns), `list_cycles`, `get_tags`, `list_initiative_meeting_artifacts`,
  `list_initiative_deliverables`, `list_webinars_v2`.
- Misc utility: `verify_certificate`, `why_denied`, `log_mcp_usage`.

Action plan: per-fn triage checking (1) caller surface (frontend/EF/MCP),
(2) data sensitivity (PII / member identity / cycle data), (3) public
intent. Each batch ~10-20 fns w/ verification.

### Phase Q-D vs Phase B' — when to use which

| Pattern | Symptom | Treatment | Track |
|---|---|---|---|
| V3 gate present, V4 missing | `is_superadmin OR operational_role IN (...)` | Replace gate with `can_by_member()` | Phase B' |
| No gate at all + intended for human admin | SECDEF + zero auth check, called from admin UI | Add `can_by_member()` gate | Drift signal pattern (#7 #8) |
| No gate at all + intended for cron/EF/dead | SECDEF + zero auth check, no human caller | REVOKE FROM anon, authenticated | Phase Q-D |
| Custom path-aware gate (interviewer-id, committee-membership, chain helper) | RPC-specific auth that doesn't map to V4 actions | Leave V3 + skip filter, escalate to Phase B'' if expanding | Phase B'' |
