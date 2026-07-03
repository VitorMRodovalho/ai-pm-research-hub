/**
 * #996 — get_affiliation_verification_queue PMI identity panel (SPEC_996_FILIACAO_JOURNEY.md §4.1)
 *
 * Migration 20260805000328 extends the queue RPC (body-only CREATE OR REPLACE, jsonb return) with a
 * per-row `pmi_profile` sub-object (PMI ID, member since/until, service history count, last VEP sync)
 * from the SAME VEP-enriched application LATERAL — no N+1, no new endpoint. This locks:
 *   - the pmi_profile object + its five fields are emitted;
 *   - the extra source columns are pulled from the existing VEP LATERAL (not a new join);
 *   - the #659 authority/LGPD/grant invariants are PRESERVED (gate, log_pii_access_batch, grants);
 *   - the LGPD field-list names the newly-surfaced membership dates (honest Art.37 trail).
 *
 * Source-contract assertions run offline; the behavioural fail-closed path (auth.uid()=NULL) is
 * covered by 659-affiliation-queue.test.mjs and unchanged here.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const MIG = readFileSync(
  fileURLToPath(new URL('../../supabase/migrations/20260805000328_996_affiliation_queue_pmi_profile.sql', import.meta.url)),
  'utf8',
);

test('996: pmi_profile object with the five identity fields is emitted', () => {
  assert.match(MIG, /'pmi_profile'/, 'pmi_profile key must be surfaced');
  assert.match(MIG, /'pmi_id',\s*c\.pmi_id/, 'PMI ID');
  assert.match(MIG, /'member_since',\s*c\.service_first_start_date/, 'member since = service_first_start_date');
  assert.match(MIG, /'member_until',\s*c\.service_latest_end_date/, 'member until = service_latest_end_date');
  assert.match(MIG, /'volunteer_count',\s*c\.service_history_count/, 'volunteer count = service_history_count');
  assert.match(MIG, /'last_sync',\s*c\.pmi_data_fetched_at/, 'last sync = pmi_data_fetched_at');
});

test('996: null pmi_profile when no enriched application (all identity fields absent)', () => {
  assert.match(MIG, /WHEN c\.pmi_id IS NULL AND c\.service_first_start_date IS NULL/, 'guard collapses to NULL when nothing enriched');
});

test('996: identity fields come from the existing VEP LATERAL, not a new join', () => {
  assert.match(
    MIG,
    /SELECT a\.vep_status_raw, a\.vep_last_seen_at, a\.pmi_memberships,\s*\n\s*a\.pmi_id, a\.service_first_start_date, a\.service_latest_end_date,\s*\n\s*a\.service_history_count, a\.pmi_data_fetched_at/,
    'the VEP LATERAL must also select the identity columns (single source, no N+1)',
  );
});

test('996: #659 authority gate PRESERVED (function-anchored, read==write audience)', () => {
  assert.match(MIG, /'filiacao_director' = ANY\(COALESCE\(v_caller_designations/, 'filiacao_director designation gate');
  assert.match(MIG, /can_by_member\(v_caller_id, 'manage_member'\)/, 'platform manager authority');
  assert.doesNotMatch(MIG, /view_internal_analytics/, 'read audience must not exceed the write gate');
  assert.match(MIG, /RAISE EXCEPTION 'Forbidden: authentication required'/, 'unauthenticated → fail-closed');
});

test('996: LGPD Art.37 trail PRESERVED + names the newly-surfaced membership dates', () => {
  assert.match(MIG, /log_pii_access_batch\(/, 'nominal read still logged');
  assert.match(MIG, /'affiliation_verification_queue'/, 'distinct audit context');
  assert.match(MIG, /'membership_dates'/, 'member since/until surfaced → named in the pii field list');
});

test('996: hardened grants PRESERVED (no public/anon; authenticated + service_role only)', () => {
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.get_affiliation_verification_queue\(\) FROM public, anon/, 'revoke public/anon');
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.get_affiliation_verification_queue\(\) TO authenticated, service_role/, 'grant authenticated/service_role');
});
