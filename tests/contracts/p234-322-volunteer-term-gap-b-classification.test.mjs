/**
 * Forward-defense: p234 #322 / Gap B of #230 reframe —
 *   volunteer_term classification leftovers + forward guard + offboarding extension.
 *
 * Origin: p230 audit (2026-05-23) of #230 reframe surfaced Gap B:
 *   4 active + 4 inactive members had pending onboarding_progress.volunteer_term
 *   with no matching cert AND no active requires_agreement engagement. Their
 *   step was mis-seeded — the universal Path A loop in
 *   approve_selection_application seeds volunteer_term unconditionally, but
 *   the member's actual engagement kind does not require an agreement.
 *
 * Post-#321 baseline: 8 total pending vol_term rows (cohort A — 30 phantoms
 * with matching cert — was closed by #321 trigger + backfill).
 *
 * Migration: supabase/migrations/20260805000019_p234_322_volunteer_term_gap_b_classification_and_guards.sql
 *
 * Asserts:
 *   - Static (16): migration file present + backfill scope (no cert + no
 *     active requires_agreement) + backfill metadata fields + backfill audit
 *     action + approve_selection_application body has forward guard +
 *     approve_selection_application SECDEF + pinned search_path preserved +
 *     admin_offboard_member body has offboarding extension UPDATE + extension
 *     metadata reason + extension audit action + admin_offboard_member SECDEF
 *     + pinned search_path preserved + get_my_onboarding completed_steps
 *     harmonized + get_my_onboarding all_complete harmonized + sanity DO
 *     RAISE EXCEPTION on goal metric > 0 + NOTIFY pgrst.
 *   - DB-gated (1): live goal metric = 0 (0 active members with pending
 *     volunteer_term and no active requires_agreement engagement).
 *
 * PM directives (2026-05-23):
 *   - Status='skipped' (not 'completed'). Reason metadata required.
 *   - Do NOT mint Herlon term.
 *   - Goal metric: 0 active members with pending volunteer_term AND no
 *     active requires_agreement engagement post-apply.
 *
 * Cross-ref:
 *   - GH #322 (this issue)
 *   - GH #321 (Gap A — closed p233 via 20260805000018; the cohort A 30
 *     phantoms were backfilled there; #322 covers cohort B no-cert leftovers)
 *   - GH #323 (Gap C — catalog config for study_group_*)
 *   - GH #230 (parent umbrella, reframed 2026-05-23)
 *   - approve_selection_application + admin_offboard_member + get_my_onboarding
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATION_FILE = resolve(
  ROOT,
  'supabase/migrations/20260805000019_p234_322_volunteer_term_gap_b_classification_and_guards.sql'
);
const CLOSE_REVIEW_FILE = resolve(
  ROOT,
  'supabase/migrations/20260805000020_p234_322_close_review_get_my_onboarding_guard.sql'
);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ===================================================================
// STATIC migration body assertions (always run — forward-defense)
// ===================================================================

test('p234 #322: migration file present at canonical path', () => {
  const dir = resolve(ROOT, 'supabase/migrations');
  const files = readdirSync(dir).filter(f => f.startsWith('20260805000019_'));
  assert.equal(files.length, 1,
    'Exactly one migration file must exist for version 20260805000019 (p234 #322 Gap B)');
  assert.match(files[0], /^20260805000019_p234_322_volunteer_term_gap_b_classification_and_guards\.sql$/,
    'Migration filename must follow `<timestamp>_<descriptive_name>.sql` per CLAUDE.md GC-097');
});

test('p234 #322: backfill scope filters on no cert AND no active requires_agreement engagement', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  // Backfill CTE must scope to vol_term + pending
  assert.match(body, /WHERE op\.step_key\s*=\s*'volunteer_term'[\s\S]{0,200}AND op\.status\s*=\s*'pending'/i,
    'Backfill CTE must filter step_key=volunteer_term + status=pending');
  // No issued vol_agreement cert (defensive, post-#321 should be empty)
  assert.match(body, /NOT EXISTS \(\s*SELECT 1 FROM public\.certificates c[\s\S]{0,200}c\.type\s*=\s*'volunteer_agreement'[\s\S]{0,100}AND c\.status\s*=\s*'issued'/i,
    'Backfill CTE must exclude rows whose member has an issued vol_agreement cert (post-#321 defense)');
  // Core Gap B condition: no ACTIVE requires_agreement engagement
  assert.match(body, /NOT EXISTS \(\s*SELECT 1 FROM public\.engagements e\s*JOIN public\.engagement_kinds ek ON ek\.slug\s*=\s*e\.kind[\s\S]{0,200}AND e\.status\s*=\s*'active'[\s\S]{0,100}AND ek\.requires_agreement\s*=\s*true/i,
    'Backfill CTE must include only rows where the member has NO active requires_agreement engagement (Gap B condition)');
});

test('p234 #322: backfill writes status=skipped with metadata reason=no_requires_agreement_engagement', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  // UPDATE op SET status='skipped'
  assert.match(body, /UPDATE public\.onboarding_progress op\s*SET[\s\S]{0,500}status\s*=\s*'skipped'/i,
    'Backfill must UPDATE onboarding_progress SET status=skipped (PM directive 2026-05-23 — NOT completed)');
  // Metadata enrichment
  assert.match(body, /'completed_via',\s*'p234_322_backfill_no_agreement_path'/i,
    'metadata.completed_via must mark backfill origin (allows targeted rollback)');
  assert.match(body, /'reason',\s*'no_requires_agreement_engagement'/i,
    'metadata.reason must be no_requires_agreement_engagement (Gap B semantic)');
  assert.match(body, /'migration',\s*'20260805000019'/i,
    'metadata.migration must reference this migration version (allows targeted rollback)');
  // Preserve existing metadata via ||
  assert.match(body, /metadata\s*=\s*COALESCE\(op\.metadata,\s*'\{\}'::jsonb\)\s*\|\|\s*jsonb_build_object/i,
    'metadata must be merged via COALESCE() || jsonb_build_object (preserves existing keys)');
});

test('p234 #322: backfill audit action is p234_322_backfill_volunteer_term_no_agreement', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /INSERT INTO public\.admin_audit_log[\s\S]{0,500}'p234_322_backfill_volunteer_term_no_agreement'/i,
    'Backfill audit action must be canonical p234_322_backfill_volunteer_term_no_agreement (matches admin_audit_log CHECK regex)');
  assert.match(body, /'target_type'[\s\S]{0,200}|'onboarding_progress'/i,
    'Backfill audit target_type must be onboarding_progress');
});

test('p234 #322: approve_selection_application has volunteer_term forward guard in Path A INSERT', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.approve_selection_application\(p_application_id uuid,\s*p_decision jsonb/i,
    'Migration must CREATE OR REPLACE approve_selection_application(uuid, jsonb)');
  // The guard: skip volunteer_term when v_requires_agreement is false
  assert.match(body, /AND NOT \(s\.id\s*=\s*'volunteer_term'\s*AND NOT COALESCE\(v_requires_agreement,\s*FALSE\)\)/i,
    'Path A SELECT must include guard `AND NOT (s.id = \'volunteer_term\' AND NOT COALESCE(v_requires_agreement, FALSE))` — forward-defense per #322');
  // Verify the guard is inside the FROM onboarding_steps loop (not the per-cycle one)
  assert.match(body, /FROM public\.onboarding_steps s[\s\S]{0,300}WHERE s\.is_required\s*=\s*true[\s\S]{0,300}AND NOT \(s\.id\s*=\s*'volunteer_term'/i,
    'Guard must be in the Path A onboarding_steps catalog INSERT (not the per-cycle Path B)');
});

test('p234 #322: approve_selection_application preserves SECDEF + pinned search_path', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  // Locate the approve function block specifically (avoid matching admin_offboard or get_my_onboarding header)
  const fnStart = body.indexOf('FUNCTION public.approve_selection_application');
  const fnEnd = body.indexOf("'#322 (p234 / Gap B of #230 reframe): adds forward guard");
  assert.ok(fnStart >= 0 && fnEnd > fnStart,
    'approve_selection_application function block must be parseable');
  const fnBlock = body.slice(fnStart, fnEnd);
  assert.match(fnBlock, /SECURITY DEFINER/i,
    'approve_selection_application must remain SECURITY DEFINER');
  assert.match(fnBlock, /SET search_path TO 'public', 'pg_temp'/i,
    'approve_selection_application must remain pinned to public + pg_temp');
});

test('p234 #322: admin_offboard_member has offboarding extension UPDATE on volunteer_term', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.admin_offboard_member\(p_member_id uuid,\s*p_new_status text,\s*p_reason_category text,\s*p_reason_detail text DEFAULT NULL::text,\s*p_reassign_to uuid/i,
    'Migration must CREATE OR REPLACE admin_offboard_member(uuid, text, text, text, uuid)');
  // The offboarding extension UPDATE
  assert.match(body, /UPDATE public\.onboarding_progress\s*SET[\s\S]{0,500}status\s*=\s*'skipped'[\s\S]{0,500}WHERE member_id\s*=\s*p_member_id\s*AND step_key\s*=\s*'volunteer_term'\s*AND status\s*=\s*'pending'/i,
    'admin_offboard_member must UPDATE volunteer_term pending rows to skipped (idempotent via status=pending filter)');
  // Capture ROW_COUNT
  assert.match(body, /GET DIAGNOSTICS v_vol_terms_skipped\s*=\s*ROW_COUNT/i,
    'admin_offboard_member must capture ROW_COUNT for conditional audit');
});

test('p234 #322: offboarding extension metadata.reason = offboarded_pre_signing', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /'completed_via',\s*'p234_322_offboarding_extension'/i,
    'Offboarding extension metadata.completed_via must mark origin');
  assert.match(body, /'reason',\s*'offboarded_pre_signing'/i,
    'Offboarding extension metadata.reason must be offboarded_pre_signing (semantic distinction from Gap B backfill)');
  assert.match(body, /'offboarded_to_status',\s*p_new_status/i,
    'Offboarding extension metadata must capture target status for forensic traceability');
});

test('p234 #322: offboarding extension audit only when rows_affected > 0', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /IF v_vol_terms_skipped > 0 THEN[\s\S]{0,500}INSERT INTO public\.admin_audit_log/i,
    'Offboarding extension audit INSERT must be inside IF v_vol_terms_skipped > 0 block (no-op no audit)');
  assert.match(body, /'onboarding\.volunteer_term_skipped_on_offboard'/i,
    'Offboarding extension audit action must be canonical onboarding.volunteer_term_skipped_on_offboard');
});

test('p234 #322: admin_offboard_member preserves SECDEF + pinned search_path + ARM-9 G3 alumni cert', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  // Locate the admin_offboard_member function block specifically
  const fnStart = body.indexOf('FUNCTION public.admin_offboard_member');
  const fnEnd = body.indexOf("'#322 (p234 / Gap B of #230 reframe): auto-skips any open volunteer_term");
  assert.ok(fnStart >= 0 && fnEnd > fnStart,
    'admin_offboard_member function block must be parseable');
  const fnBlock = body.slice(fnStart, fnEnd);
  assert.match(fnBlock, /SECURITY DEFINER/i,
    'admin_offboard_member must remain SECURITY DEFINER');
  assert.match(fnBlock, /SET search_path TO 'public', 'pg_temp'/i,
    'admin_offboard_member must remain pinned to public + pg_temp');
  // Preserve ARM-9 G3 logic
  assert.match(fnBlock, /-- ARM-9 G3: auto-emit alumni_recognition certificate/i,
    'ARM-9 G3 alumni_recognition cert emission must be preserved');
  assert.match(fnBlock, /'arm9_g3_auto_emit'/i,
    'ARM-9 G3 source tag must remain in cert INSERT');
});

test('p234 #322: get_my_onboarding completed_steps treats skipped as terminal', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_my_onboarding\(\)/i,
    'Migration must CREATE OR REPLACE get_my_onboarding()');
  // completed_steps clause uses IN ('completed', 'skipped')
  assert.match(body, /'completed_steps',\s*\(SELECT count\(\*\) FROM onboarding_progress WHERE member_id\s*=\s*v_member_id\s*AND status IN \('completed',\s*'skipped'\)/i,
    'get_my_onboarding.completed_steps must use status IN (\'completed\', \'skipped\') — mirrors get_onboarding_status');
});

test('p234 #322: get_my_onboarding all_complete treats skipped as terminal', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  // all_complete clause uses NOT IN ('completed', 'skipped')
  assert.match(body, /'all_complete',\s*\(NOT EXISTS \([\s\S]{0,500}WHERE s\.is_required\s*AND op\.status NOT IN \('completed',\s*'skipped'\)/i,
    'get_my_onboarding.all_complete must use status NOT IN (\'completed\', \'skipped\') — mirrors get_onboarding_status');
});

test('p234 #322: get_my_onboarding preserves SECDEF + pinned search_path + step rendering', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  // Locate the get_my_onboarding function block specifically
  const fnStart = body.indexOf('FUNCTION public.get_my_onboarding');
  const fnEnd = body.indexOf("'#322 (p234 / Gap B of #230 reframe): treats status=skipped as terminal");
  assert.ok(fnStart >= 0 && fnEnd > fnStart,
    'get_my_onboarding function block must be parseable');
  const fnBlock = body.slice(fnStart, fnEnd);
  assert.match(fnBlock, /SECURITY DEFINER/i,
    'get_my_onboarding must remain SECURITY DEFINER');
  assert.match(fnBlock, /SET search_path TO 'public', 'pg_temp'/i,
    'get_my_onboarding must remain pinned to public + pg_temp');
  // Step rendering: COALESCE(op.status, 'pending') preserved verbatim (UI can render skipped distinctly)
  assert.match(fnBlock, /COALESCE\(op\.status,\s*'pending'\) AS status/i,
    'Per-step status rendering must preserve raw value (UI may distinguish skipped from completed)');
});

test('p234 #322: sanity DO block RAISES EXCEPTION on remaining Gap B violations', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /RAISE EXCEPTION '#322 sanity FAIL/i,
    'Sanity DO block must RAISE EXCEPTION (fails loud at apply time, not runtime)');
  assert.match(body, /v_violation_count int/i,
    'Sanity block must declare v_violation_count variable for the assertion');
  // Goal metric: 0 active members with pending volunteer_term AND no active requires_agreement engagement
  assert.match(body, /FROM public\.onboarding_progress op\s*JOIN public\.members m ON m\.id\s*=\s*op\.member_id\s*WHERE op\.step_key\s*=\s*'volunteer_term'\s*AND op\.status\s*=\s*'pending'\s*AND COALESCE\(m\.is_active,\s*FALSE\) IS TRUE\s*AND NOT EXISTS \(\s*SELECT 1 FROM public\.engagements e\s*JOIN public\.engagement_kinds ek ON ek\.slug\s*=\s*e\.kind\s*WHERE e\.person_id\s*=\s*m\.person_id\s*AND e\.status\s*=\s*'active'\s*AND ek\.requires_agreement\s*=\s*true/i,
    'Sanity query must match the goal metric: 0 active members with pending vol_term AND no active requires_agreement engagement');
});

test('p234 #322: migration reloads PostgREST schema cache', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /NOTIFY pgrst,\s*'reload schema'/i,
    'Migration must NOTIFY pgrst reload schema (CLAUDE.md GC-097)');
});

// ===================================================================
// CLOSE-REVIEW PATCH (20260805000020) — get_my_onboarding auto-seed guard
// PM curator review of PR #327 (2026-05-23) caught that get_my_onboarding()
// universally auto-seeds onboarding_steps catalog on first call, which
// reintroduced Gap B for any future member whose first hit lands here.
// This sibling migration mirrors the approve_selection_application guard.
// ===================================================================

test('p234 #322 close-review: migration 20260805000020 present at canonical path', () => {
  const dir = resolve(ROOT, 'supabase/migrations');
  const files = readdirSync(dir).filter(f => f.startsWith('20260805000020_'));
  assert.equal(files.length, 1,
    'Exactly one migration file must exist for version 20260805000020 (p234 #322 close-review patch)');
  assert.match(files[0], /^20260805000020_p234_322_close_review_get_my_onboarding_guard\.sql$/,
    'Migration filename must follow `<timestamp>_<descriptive_name>.sql` per CLAUDE.md GC-097');
});

test('p234 #322 close-review: get_my_onboarding declares v_has_req_agreement_engagement and computes via EXISTS', () => {
  const body = readFileSync(CLOSE_REVIEW_FILE, 'utf8');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_my_onboarding\(\)/i,
    'Close-review migration must CREATE OR REPLACE get_my_onboarding()');
  // Variable declaration
  assert.match(body, /v_has_req_agreement_engagement boolean/i,
    'get_my_onboarding must declare v_has_req_agreement_engagement boolean');
  // EXISTS query reads engagements + engagement_kinds + status=active + requires_agreement=true
  assert.match(body, /SELECT EXISTS \(\s*SELECT 1 FROM public\.engagements e\s*JOIN public\.members m ON m\.id\s*=\s*v_member_id\s*JOIN public\.engagement_kinds ek ON ek\.slug\s*=\s*e\.kind\s*WHERE e\.person_id\s*=\s*m\.person_id\s*AND e\.status\s*=\s*'active'\s*AND ek\.requires_agreement\s*=\s*true\s*\)\s*INTO v_has_req_agreement_engagement/i,
    'EXISTS query must join engagements + members + engagement_kinds and filter status=active + requires_agreement=true');
});

test('p234 #322 close-review: get_my_onboarding auto-seed INSERT skips volunteer_term when v_has_req_agreement_engagement is false', () => {
  const body = readFileSync(CLOSE_REVIEW_FILE, 'utf8');
  // The auto-seed INSERT must include the guard alongside the NOT EXISTS dedup
  assert.match(body, /INSERT INTO onboarding_progress \(member_id, step_key, status\)\s*SELECT v_member_id, s\.id, 'pending'\s*FROM onboarding_steps s\s*WHERE NOT EXISTS \(SELECT 1 FROM onboarding_progress op WHERE op\.member_id\s*=\s*v_member_id AND op\.step_key\s*=\s*s\.id\)\s*AND NOT \(s\.id\s*=\s*'volunteer_term'\s*AND NOT v_has_req_agreement_engagement\)/i,
    'Auto-seed INSERT must include `AND NOT (s.id = \'volunteer_term\' AND NOT v_has_req_agreement_engagement)` — mirrors approve_selection_application forward guard');
});

test('p234 #322 close-review: get_my_onboarding preserves skipped≡completed harmonization + SECDEF + pinned search_path', () => {
  const body = readFileSync(CLOSE_REVIEW_FILE, 'utf8');
  // Preservation: skipped≡completed harmonization from 20260805000019 must remain
  assert.match(body, /'completed_steps',\s*\(SELECT count\(\*\) FROM onboarding_progress WHERE member_id\s*=\s*v_member_id\s*AND status IN \('completed',\s*'skipped'\)/i,
    'completed_steps must continue to treat status IN (\'completed\', \'skipped\') as terminal');
  assert.match(body, /'all_complete',\s*\(NOT EXISTS \([\s\S]{0,500}WHERE s\.is_required\s*AND op\.status NOT IN \('completed',\s*'skipped'\)/i,
    'all_complete must continue to treat status NOT IN (\'completed\', \'skipped\') as terminal-blocking');
  // SECDEF + search_path preserved
  assert.match(body, /SECURITY DEFINER/i,
    'get_my_onboarding must remain SECURITY DEFINER');
  assert.match(body, /SET search_path TO 'public', 'pg_temp'/i,
    'get_my_onboarding must remain pinned to public + pg_temp');
  // Per-step rendering verbatim
  assert.match(body, /COALESCE\(op\.status,\s*'pending'\) AS status/i,
    'Per-step status rendering preserved verbatim — UI may render skipped distinctly');
  // NOTIFY pgrst
  assert.match(body, /NOTIFY pgrst,\s*'reload schema'/i,
    'Close-review migration must NOTIFY pgrst reload schema');
});

// ===================================================================
// DB-GATED assertion (require SUPABASE_URL + SERVICE_ROLE_KEY)
// ===================================================================

function makeClient() {
  return createClient(SUPABASE_URL, SUPABASE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

test('p234 #322 (live): goal metric = 0 active members with pending vol_term AND no active requires_agreement engagement',
  { skip: !dbGated && skipMsg },
  async () => {
    const sb = makeClient();
    // Replicates the sanity DO block in the migration: count active members
    // with pending volunteer_term AND no active requires_agreement engagement.
    // Must be 0 post-apply (and stay 0 going forward thanks to forward guard
    // + offboarding extension).
    const { data: pending, error: e1 } = await sb
      .from('onboarding_progress')
      .select('member_id')
      .eq('step_key', 'volunteer_term')
      .eq('status', 'pending');
    assert.ok(!e1, `onboarding_progress query failed: ${e1?.message}`);

    if (!pending || pending.length === 0) {
      return; // trivially 0 violations
    }

    const memberIds = [...new Set(pending.map(r => r.member_id).filter(Boolean))];
    if (memberIds.length === 0) {
      return;
    }

    // Get active members among those pending
    const { data: members, error: e2 } = await sb
      .from('members')
      .select('id, is_active, person_id')
      .in('id', memberIds);
    assert.ok(!e2, `members query failed: ${e2?.message}`);

    const activeMembers = (members || []).filter(m => m.is_active === true);
    if (activeMembers.length === 0) {
      return; // no active members in cohort
    }

    const personIds = activeMembers.map(m => m.person_id).filter(Boolean);
    if (personIds.length === 0) {
      // Active members with NULL person_id is a separate invariant (S);
      // not Gap B territory.
      return;
    }

    // Get active requires_agreement engagements
    const { data: engagements, error: e3 } = await sb
      .from('engagements')
      .select('person_id, kind')
      .eq('status', 'active')
      .in('person_id', personIds);
    assert.ok(!e3, `engagements query failed: ${e3?.message}`);

    const { data: kinds, error: e4 } = await sb
      .from('engagement_kinds')
      .select('slug, requires_agreement');
    assert.ok(!e4, `engagement_kinds query failed: ${e4?.message}`);

    const reqAgreementKinds = new Set(
      (kinds || []).filter(k => k.requires_agreement === true).map(k => k.slug)
    );

    const personsWithReqAgreement = new Set(
      (engagements || [])
        .filter(e => reqAgreementKinds.has(e.kind))
        .map(e => e.person_id)
    );

    const violations = activeMembers.filter(
      m => m.person_id && !personsWithReqAgreement.has(m.person_id)
    );

    assert.strictEqual(
      violations.length,
      0,
      `Expected 0 active members with pending volunteer_term AND no active requires_agreement engagement (post-backfill + forward guard); got ${violations.length}. ` +
      `Migration 20260805000019 sanity block should have caught this at apply time.`
    );
  }
);
