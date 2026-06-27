/**
 * Contract: p277 triage data-integrity bundle (#420 siblings)
 *  (A) repair live-broken link_initiative_to_drive (record "v_existing" not assigned yet)
 *  (B) invariant R_approved_application_has_member honors member_emails (alternate) matches
 *
 * (A) The RPC did `SELECT id INTO v_existing.id` on an UNASSIGNED `record` → every call raised
 *     `record "v_existing" is not assigned yet` before the INSERT (folders never linked; surfaced
 *     by the nucleo-wiki session on initiative 6e9af7a8). Fixed with a scalar uuid.
 * (B) The VEP import can reset a reconciled application's email to the candidate's PMI email,
 *     which differs from the member's primary email → R (primary-only match) tripped for a real
 *     reconciled approved candidate (Paulo, app pejota81@gmail.com vs member paulo-junior@outlook.com).
 *     R's drift CTE now also accepts a member_emails (alternate) match. The pejota81 alternate was
 *     backfilled onto Paulo via the canonical member_add_alternate_email() RPC. All 22 other
 *     invariants preserved byte-identical (Phase-C md5 parity).
 *
 * Migrations: 20260805000076 (link fix), 20260805000077 (invariant R extension).
 * Cross-ref: #440 (board assignee), #441 (import 2-zeros), the import-clobbers-reconciled-email issue.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');
const LINK = read('supabase/migrations/20260805000076_p277_fix_link_initiative_to_drive_record_bug.sql');
const linkCode = LINK.replace(/--[^\n]*/g, '');   // strip header comment (it quotes the OLD buggy line)
const RMIG = read('supabase/migrations/20260805000077_p277_invariant_r_honors_alternate_email.sql');
const rCode = RMIG.replace(/--[^\n]*/g, '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── (A) link_initiative_to_drive record bug ────────────────────────────────────
test('link fix: uses scalar v_existing_id, not an unassigned record field', () => {
  assert.ok(LINK, 'link migration exists');
  assert.match(linkCode, /v_existing_id uuid;/);
  assert.match(linkCode, /SELECT id INTO v_existing_id FROM public\.initiative_drive_links/);
  assert.match(linkCode, /IF v_existing_id IS NOT NULL THEN/);
  assert.ok(!/v_existing\s+record;/.test(linkCode), 'must not declare v_existing as a record');
  assert.ok(!/INTO v_existing\.id/.test(linkCode), 'must not SELECT INTO a record field (the bug)');
});

// ── (B) invariant R honors alternate emails ────────────────────────────────────
test('R extension: drift CTE requires no-match on BOTH members(primary) AND member_emails(alternate)', () => {
  assert.ok(RMIG, 'R migration exists');
  // primary clause preserved (existing contract test depends on this)
  assert.match(rCode, /NOT EXISTS \(\s*SELECT 1 FROM public\.members m WHERE lower\(m\.email\) = lower\(a\.email\)\s*\)/);
  // new alternate clause
  assert.match(rCode, /NOT EXISTS \(\s*SELECT 1 FROM public\.member_emails me WHERE lower\(me\.email\) = lower\(a\.email\)\s*\)/);
  // R still scoped to approved-only (not converted)
  const rBlock = rCode.slice(rCode.lastIndexOf('WITH drift AS', rCode.indexOf("'R_approved_application_has_member'")), rCode.indexOf("'R_approved_application_has_member'"));
  assert.match(rBlock, /a\.status = 'approved'/);
  assert.ok(!/'converted'/.test(rBlock), 'R must not include converted');
});

test('R extension: all 23 invariants preserved (no regression dropped an invariant)', () => {
  const labels = (rCode.match(/'[A-Z][A-Za-z0-9_]*'::text,\s*$/gm) || []);
  // count the labelled invariant SELECTs (each invariant emits exactly one '<NAME>'::text label line)
  const names = [...rCode.matchAll(/SELECT '([A-Z][A-Za-z0-9_]+)'::text,/g)].map(m => m[1]);
  for (const req of ['A1_alumni_role_consistency','R_approved_application_has_member','S_approved_member_has_person_id','T_member_has_exactly_one_primary_email','W_content_product_source_integrity','X_blind_review_pareceres_session_product_match']) {
    assert.ok(names.includes(req), `invariant ${req} must be present`);
  }
  assert.strictEqual(names.length, 23, `expected 23 invariant labels, found ${names.length}`);
});

test('R extension: sanity DO asserts R=0 post-apply', () => {
  assert.match(RMIG, /RAISE EXCEPTION 'p277 invariant-R fix: R still reports/);
});

// ── DB-gated ───────────────────────────────────────────────────────────────────
test('DB: check_schema_invariants reports R=0 and 31 invariants, 0 total violations', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('check_schema_invariants');
  assert.ok(!error, error?.message);
  assert.ok(Array.isArray(data), 'returns rows');
  // 23 through p277; #481 (mig 094) added Y_chapter_pipeline_parity + Z_webinar_status_domain → 25; #483 (mig 119) added B2_current_cycle_active_terminal_status → 26; #740 Wave 3b-ii (mig 195) added U_active_person_has_primary_chapter_affiliation → 27; #766 (mig 200) added AA_volunteer_term_complete_when_cert_issued → 28; #766 PR2 (mig 202) added AB_term_signed_milestone_has_cert_ancestry → 29; #766 PR3 (mig 203) added AC_first_attendance_milestone_has_attendance + AD_first_deliverable_milestone_has_completed_deliverable → 31; #766 PR4 (mig 204) added NO invariant (promotion = mutable cache) → still 31; #766 PR5 (mig 205) added AE_profile_complete_milestone_has_profile_completed_at → 32; D4/D5 (mig 210) added AF_open_interview_is_newest_row → 33; Tribe Selection Híbrida PR1 (mig 216) added AG_tribe_engagement_has_tribe_id + AH_research_tribe_single_active_engagement → 35; D3 auto-rescue (mig 219) added AI_unbooked_rescue_cap_respected → 36; #785 PR-2 (mig 232) added AJ_confidential_visibility_gate_present → 37; #333 (mig 259) added AK_voice_biometric_consent_enforcement → 38.
  assert.strictEqual(data.length, 38, `expected 38 invariants, got ${data.length}`);
  const r = data.find(x => x.invariant_name === 'R_approved_application_has_member');
  assert.ok(r, 'R present');
  assert.strictEqual(r.violation_count, 0, 'R must have 0 violations (alternate-email match honored)');
  const offenders = data.filter(x => x.violation_count > 0).map(x => `${x.invariant_name}=${x.violation_count}`);
  assert.strictEqual(offenders.length, 0, `unexpected violations: ${offenders.join(', ')}`);
});

test('DB: link_initiative_to_drive executes without the record-assignment crash (service-role → graceful auth error)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // service-role has no member row → returns {error:'Not authenticated'} as jsonb, NOT a 500/raise.
  const { data, error } = await sb.rpc('link_initiative_to_drive', {
    p_initiative_id: '00000000-0000-0000-0000-000000000000',
    p_drive_folder_id: 'contract-test-noop',
    p_drive_folder_url: 'https://drive.google.com/contract-test-noop',
  });
  assert.ok(!error, `RPC must not throw: ${error?.message}`);
  assert.ok(data && typeof data === 'object', 'returns a jsonb object');
});
