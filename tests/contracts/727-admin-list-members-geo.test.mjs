/**
 * #727 (#625 follow-up) — admin_list_members surfaces member geo (country + state) so the
 * /admin/members list can offer client-side estado/país + affiliation-status filters.
 *
 * Migration 20260805000329 is a body-only CREATE OR REPLACE (jsonb return, 7-param signature
 * unchanged). This locks:
 *   - the two geo keys are emitted, read straight from members.country / members.state;
 *   - it is body-only (no DROP FUNCTION → signature/grants untouched, no PostgREST break);
 *   - the admin gate is PRESERVED (can_by_member(view_internal_analytics), fail-closed);
 *   - the affiliation farol is NOT re-derived in SQL — the affiliation_* fields stay surfaced
 *     as-is and the client keeps the single source of the farol thresholds (SSOT, no divergence).
 *
 * Source-contract assertions run offline (no DB env needed).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const MIG = readFileSync(
  fileURLToPath(new URL('../../supabase/migrations/20260805000329_727_admin_list_members_geo.sql', import.meta.url)),
  'utf8',
);

test('727: geo keys (country + state) emitted from members.country/state', () => {
  assert.match(MIG, /'country',\s*m\.country/, 'country key surfaced');
  assert.match(MIG, /'state',\s*m\.state/, 'state key surfaced');
});

test('727: body-only CREATE OR REPLACE — signature unchanged, no DROP', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.admin_list_members\(/, 'CREATE OR REPLACE');
  assert.doesNotMatch(MIG, /DROP FUNCTION/, 'no DROP → signature/grants untouched');
  assert.match(
    MIG,
    /admin_list_members\(p_search text[^)]*p_tier text[^)]*p_tribe_id integer[^)]*p_status text[^)]*p_initiative_id uuid[^)]*p_chapter text[^)]*p_cycle text/,
    'the 7-param signature is preserved verbatim',
  );
  assert.match(MIG, /RETURNS jsonb/, 'jsonb return preserved');
});

test('727: admin gate PRESERVED (view_internal_analytics, fail-closed)', () => {
  assert.match(MIG, /can_by_member\(v_caller_id, 'view_internal_analytics'\)/, 'admin gate');
  assert.match(MIG, /RAISE EXCEPTION 'Forbidden: authentication required'/, 'unauthenticated → fail-closed');
});

test('727: affiliation farol NOT re-derived in SQL (SSOT stays client-side)', () => {
  // The affiliation_* fields must still be surfaced raw (the client derives the farol from them).
  assert.match(MIG, /'affiliation_active',\s*aff\.membership_active/, 'affiliation_active surfaced raw');
  assert.match(MIG, /'affiliation_expires_on',\s*aff\.membership_expires_on/, 'affiliation_expires_on surfaced raw');
  // No affiliation-status color bucket computed in SQL (would fork the farol thresholds).
  assert.doesNotMatch(MIG, /'affiliation_status'/, 'no affiliation_status bucket derived in SQL');
});
