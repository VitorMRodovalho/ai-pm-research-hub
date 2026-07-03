/**
 * #883 Onda A — get_comms_to_adoption_funnel security hygiene.
 *
 * Audit: docs/strategy/883_comms_audit_and_spec.md. Migration 20260805000331:
 *   A1. REVOKE anon (the body already fail-closes on auth.uid() NULL; the anon grant was noise).
 *   A2. Add can_view_comms_analytics() to the gate so the comms team sees its own funnel — the
 *       funnel is a card of /admin/comms yet gated stricter than every other reader on that page.
 *
 * Static source-contract assertions (offline).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const MIG = readFileSync(
  fileURLToPath(new URL('../../supabase/migrations/20260805000331_883_onda_a_comms_funnel_gate.sql', import.meta.url)),
  'utf8',
);

test('883-A1: anon EXECUTE is revoked from the funnel', () => {
  assert.match(MIG, /REVOKE EXECUTE ON FUNCTION public\.get_comms_to_adoption_funnel\(integer\) FROM anon/, 'anon revoked');
});

test('883-A2: funnel gate now includes can_view_comms_analytics (comms team sees the funnel)', () => {
  assert.match(MIG, /OR public\.can_view_comms_analytics\(\)\) THEN/, 'comms-analytics tier added to the OR gate');
  assert.match(MIG, /can_by_member\(v_caller_id, 'view_internal_analytics'\)/, 'existing internal-analytics tier preserved');
  assert.match(MIG, /can_by_member\(v_caller_id, 'view_aggregate_analytics'\)/, 'existing aggregate tier preserved');
});

test('883: anon still fail-closes in-body (defense-in-depth beyond the grant)', () => {
  assert.match(MIG, /IF v_caller_id IS NULL THEN\s*\n\s*RETURN jsonb_build_object\('error', 'Unauthorized'\)/, 'auth.uid() NULL → Unauthorized preserved');
});

test('883: body-only CREATE OR REPLACE (no DROP; signature preserved)', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.get_comms_to_adoption_funnel\(p_period_days integer DEFAULT 30\)/);
  assert.doesNotMatch(MIG, /DROP FUNCTION/);
  assert.match(MIG, /RETURNS jsonb/);
});
