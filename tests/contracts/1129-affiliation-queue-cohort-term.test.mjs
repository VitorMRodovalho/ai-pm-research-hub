/**
 * #1129 — get_affiliation_verification_queue cohort view + volunteer-term validity
 *
 * Migration 20260805000348 extends the queue RPC (body-only CREATE OR REPLACE, jsonb return) with,
 * per row: cohort_class (current_selection|carryover|non_selection), cohort_cycle_code, cohort_role,
 * term_end_date, term_status (valid|expiring|expired|none). This locks:
 *   - cohort is DERIVED from engagement/selection → cycle, NEVER members.cycles (the unreliable field);
 *   - the current selection cycle is resolved DYNAMICALLY (tied to cycles.is_current) with NO hardcoded
 *     cycle_code literal, so it survives the C4→C5 turn;
 *   - the three cohort buckets + the term_status buckets are emitted;
 *   - the #659/#996 authority/LGPD/grant/pmi_profile invariants are PRESERVED.
 *
 * Source-contract assertions run offline; the fail-closed path (auth.uid()=NULL → Forbidden) is
 * covered behaviourally when DB env is present (mirrors 659).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const MIG = readFileSync(
  fileURLToPath(new URL('../../supabase/migrations/20260805000348_1129_affiliation_queue_cohort_term.sql', import.meta.url)),
  'utf8',
);
// Comment-stripped view — the "must NOT appear" assertions target executable SQL, not the header/
// inline comments (which legitimately name the anti-patterns being avoided, e.g. members.cycles).
const CODE = MIG.replace(/--.*$/gm, '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

async function rpc(fn, args) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` },
    body: JSON.stringify(args),
  });
  if (!res.ok) throw new Error(`rpc ${fn} HTTP ${res.status}: ${await res.text()}`);
  return res.json();
}

// ── Source contract (offline) ───────────────────────────────────────────────
test('1129: cohort + term fields are emitted', () => {
  assert.match(MIG, /'cohort_class'/, 'cohort_class key');
  assert.match(MIG, /'cohort_cycle_code'/, 'cohort_cycle_code key');
  assert.match(MIG, /'cohort_role'/, 'cohort_role key');
  assert.match(MIG, /'term_end_date'/, 'term_end_date key');
  assert.match(MIG, /'term_status'/, 'term_status key');
});

test('1129: three cohort buckets + four term buckets', () => {
  assert.match(MIG, /'non_selection'/, 'non_selection bucket');
  assert.match(MIG, /'current_selection'/, 'current_selection bucket');
  assert.match(MIG, /'carryover'/, 'carryover bucket');
  assert.match(MIG, /'expired'/, 'term expired bucket');
  assert.match(MIG, /'expiring'/, 'term expiring bucket');
  assert.match(MIG, /'valid'/, 'term valid bucket');
  assert.match(MIG, /'none'/, 'term none bucket');
});

test('1129: cohort is derived from selection/engagement → cycle, NOT members.cycles', () => {
  // The reliable derivation joins selection_applications → selection_cycles by cycle_id.
  assert.match(MIG, /selection_applications a[\s\S]*JOIN public\.selection_cycles sc ON sc\.id = a\.cycle_id/, 'selection→cycle join');
  assert.match(MIG, /a\.status IN \('approved','converted'\)/, 'only approved/converted applications count');
  // Term boundary from the active requires_agreement engagement.
  assert.match(MIG, /ek\.requires_agreement = true/, 'term = active agreement-requiring engagement');
  // Hard guard: the unreliable members.cycles field must NOT be the cohort source (executable SQL only).
  assert.doesNotMatch(CODE, /\bm\.cycles\b/, 'must not read members.cycles (unreliable — 50/89 empty)');
});

test('1129: current selection cycle resolved DYNAMICALLY (no hardcoded cycle_code; survives C4→C5)', () => {
  assert.match(MIG, /FROM public\.cycles c WHERE c\.is_current/, 'ties current cycle to cycles.is_current');
  // No literal selection cycle_code baked into executable SQL — that would rot at the next turn.
  assert.doesNotMatch(CODE, /cycle\d+-20\d\d/, 'no hardcoded selection cycle_code literal');
});

test('1129: term validity compares an engagement end_date to CURRENT_DATE with a soon window', () => {
  assert.match(MIG, /c\.term_end_date < CURRENT_DATE/, 'expired = end_date before today');
  assert.match(MIG, /v_term_soon_days/, 'configurable soon window');
  assert.match(MIG, /CURRENT_DATE \+ \(v_term_soon_days \|\| ' days'\)::interval/, 'expiring = within the soon window');
});

test('1129: #659/#996 authority gate PRESERVED (function-anchored, read==write audience)', () => {
  assert.match(MIG, /'filiacao_director' = ANY\(COALESCE\(v_caller_designations/, 'filiacao_director designation gate');
  assert.match(MIG, /can_by_member\(v_caller_id, 'manage_member'\)/, 'platform manager authority');
  assert.doesNotMatch(CODE, /view_internal_analytics/, 'read audience must not exceed the write gate');
  assert.match(MIG, /RAISE EXCEPTION 'Forbidden: authentication required'/, 'unauthenticated → fail-closed');
});

test('1129: #996 pmi_profile + LGPD trail + hardened grants PRESERVED', () => {
  assert.match(MIG, /'pmi_profile'/, 'pmi_profile panel still emitted');
  assert.match(MIG, /log_pii_access_batch\(/, 'nominal read still logged');
  assert.match(MIG, /'membership_dates'/, 'LGPD field list preserved');
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.get_affiliation_verification_queue\(\) FROM public, anon/, 'revoke public/anon');
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.get_affiliation_verification_queue\(\) TO authenticated, service_role/, 'grant authenticated/service_role');
});

// ── Behavioural (DB) ────────────────────────────────────────────────────────
test(canRun ? '1129: unauthenticated caller (auth.uid NULL) is denied (function exists + fail-closed)' : skipMsg, { skip: !canRun }, async () => {
  await assert.rejects(
    () => rpc('get_affiliation_verification_queue', {}),
    /Forbidden: authentication required/,
    'service-role call has auth.uid()=NULL → must fail-closed (and proves the function exists + gate fires)',
  );
});
