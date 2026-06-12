/**
 * #659 — get_affiliation_verification_queue (Pasta Diretoria de Filiação, epic #660 step 2)
 *
 * Locks the cohort-read RPC contract (migration 20260805000155):
 *   - function-anchored gate: filiacao_director designation OR view_internal_analytics OR
 *     manage_member; fail-closed on auth.uid() NULL (unauthenticated → Forbidden);
 *   - the queue surfaces the federated-gate data (pmi_memberships) + the pre-onboarding flag,
 *     reusing the admin_list_members pre-onboarding LATERAL verbatim;
 *   - cohort = pre-onboarding OR unverified OR never-verified active members;
 *   - LGPD Art. 37 nominal-read trail via log_pii_access_batch;
 *   - hardened grants (REVOKE public/anon; GRANT authenticated/service_role).
 *
 * The RPC reads auth.uid() (no member param), so the service-role harness can only exercise the
 * unauthenticated path behaviourally (auth.uid()=NULL → Forbidden); the rest is locked by
 * source-contract assertions (mirrors p625-c0). Behavioural test needs SUPABASE_URL +
 * SUPABASE_SERVICE_ROLE_KEY; source tests run offline.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const MIG = readFileSync(
  fileURLToPath(new URL('../../supabase/migrations/20260805000155_659_affiliation_verification_queue.sql', import.meta.url)),
  'utf8',
);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

async function rpc(fn, args) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify(args),
  });
  if (!res.ok) throw new Error(`rpc ${fn} HTTP ${res.status}: ${await res.text()}`);
  return res.json();
}

// ── Source contract (offline) ───────────────────────────────────────────────
test('659: gate is function-anchored + read==write audience (filiacao_director OR manage_member)', () => {
  assert.match(MIG, /'filiacao_director' = ANY\(COALESCE\(v_caller_designations/, 'gate must check the filiacao_director designation');
  assert.match(MIG, /can_by_member\(v_caller_id, 'manage_member'\)/, 'platform manager authority');
  // M-1: a BULK cohort read must NOT be wider than the write gate — no view_internal_analytics arm.
  assert.doesNotMatch(MIG, /can_by_member\(v_caller_id, 'view_internal_analytics'\)/, 'read audience must not exceed the write gate');
  assert.match(MIG, /RAISE EXCEPTION 'Forbidden: authentication required'/, 'unauthenticated → fail-closed');
  assert.match(MIG, /RAISE EXCEPTION 'Forbidden: requires filiacao_director/, 'unauthorized → fail-closed');
});

test('659: surfaces pmi_memberships + pre-onboarding flag (reuses admin_list_members LATERAL verbatim)', () => {
  assert.match(MIG, /'pmi_memberships'/, 'federated-gate detail must be surfaced');
  assert.match(MIG, /'is_pre_onboarding'/, 'pre-onboarding flag must be surfaced');
  assert.match(MIG, /e\.person_id = m\.person_id AND e\.status = 'active'/, 'pre-onboarding LATERAL anchor (engagement)');
  assert.match(MIG, /ek\.requires_agreement IS NOT TRUE OR e\.agreement_certificate_id IS NOT NULL/, 'pre-onboarding LATERAL anchor (agreement)');
});

test('659: cohort predicate = pre-onboarding OR unverified OR never-verified', () => {
  assert.match(MIG, /COALESCE\(pre\.flag, false\)/, 'pre-onboarding branch');
  assert.match(MIG, /COALESCE\(m\.pmi_id_verified, false\) = false/, 'cache-unverified branch');
  assert.match(MIG, /SELECT 1 FROM public\.member_affiliation_verifications mv/, 'never-verified branch (alias mv, distinct from the latest-verification LATERAL alias mav)');
});

test('659: LGPD Art.37 nominal-read trail via log_pii_access_batch', () => {
  assert.match(MIG, /log_pii_access_batch\(/, 'must log the nominal read');
  assert.match(MIG, /'affiliation_verification_queue'/, 'distinct audit context');
});

test('659: hardened grants (no public/anon; authenticated + service_role only)', () => {
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.get_affiliation_verification_queue\(\) FROM public, anon/, 'revoke public/anon');
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.get_affiliation_verification_queue\(\) TO authenticated, service_role/, 'grant authenticated/service_role');
});

// ── Behavioural (DB) ────────────────────────────────────────────────────────
test(canRun ? '659: unauthenticated caller (auth.uid NULL) is denied (function exists + fail-closed)' : skipMsg, { skip: !canRun }, async () => {
  await assert.rejects(
    () => rpc('get_affiliation_verification_queue', {}),
    /Forbidden: authentication required/,
    'service-role call has auth.uid()=NULL → must fail-closed (and proves the function exists + gate fires)',
  );
});
