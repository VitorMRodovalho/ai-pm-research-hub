/**
 * Contract: #1104 — admin_roll_cycle_membership is the governed roll-forward of
 * member_cycle_history at cycle turnover (ends the hand-written INSERT migrations).
 *
 * Migration: supabase/migrations/20260805000401_1104_admin_roll_cycle_membership.sql
 * Precedent replaced: 20260805000343_c4_roll_forward_member_cycle_history.sql (manual C3->C4).
 *
 * Invariants under test (static, always) + a DB-gated self-gate proof:
 *  - SECURITY DEFINER, gated on manage_platform via public.can.
 *  - dry_run defaults TRUE (a read-only preview by default).
 *  - cohort date comes from the `cycles` dimension (v_to_start), NOT a hardcoded literal.
 *  - idempotent: NOT EXISTS(member, to_cycle) guard on both cohort and insert.
 *  - grants: revoked from PUBLIC/anon, granted to authenticated + service_role.
 *  - by design it does NOT append to members.cycles[] (selection namespace, maintained
 *    elsewhere; ratified 2026-07-10) — member_cycle_history stays the period SSOT.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000401_1104_admin_roll_cycle_membership.sql');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1104: migration defines admin_roll_cycle_membership(text, text, boolean DEFAULT true)', () => {
  assert.ok(existsSync(MIG), 'migration file present');
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.admin_roll_cycle_membership\(/);
  assert.match(mig, /p_from_cycle text/);
  assert.match(mig, /p_to_cycle text/);
  assert.match(mig, /p_dry_run boolean DEFAULT true/, 'dry_run must default to a read-only preview');
});

test('#1104: SECURITY DEFINER and gated on manage_platform via public.can', () => {
  assert.match(mig, /SECURITY DEFINER/);
  assert.match(mig, /IF NOT public\.can\(v_person_id, 'manage_platform'\) THEN/);
});

test('#1104: cohort cutoff derives from the cycles dimension (no hardcoded date)', () => {
  // reads the period dimension for the new cycle's start/label
  assert.match(mig, /FROM public\.cycles WHERE cycle_code = p_to_cycle/);
  // engagement "vigente" cutoff uses the resolved v_to_start, not a DATE literal
  assert.match(mig, /e\.end_date IS NULL OR e\.end_date >= v_to_start/);
  // no hardcoded cohort date literal in the function logic (smart-code rule)
  assert.ok(!/>=\s*DATE\s*'20\d\d-/.test(mig), 'no hardcoded >= DATE literal in the cohort filter');
});

test('#1104: idempotent — NOT EXISTS(member, to_cycle) guard on cohort and insert', () => {
  const guards = mig.match(/NOT EXISTS \(\s*SELECT 1 FROM public\.member_cycle_history/g) || [];
  assert.ok(guards.length >= 2, `expected a NOT EXISTS guard on both cohort and insert (found ${guards.length})`);
});

test('#1104: grants — revoked from PUBLIC/anon, granted to authenticated + service_role', () => {
  assert.match(mig, /REVOKE EXECUTE ON FUNCTION public\.admin_roll_cycle_membership\(text, text, boolean\) FROM PUBLIC, anon;/);
  assert.match(mig, /GRANT  ?EXECUTE ON FUNCTION public\.admin_roll_cycle_membership\(text, text, boolean\) TO authenticated, service_role;/);
});

test('#1104: by design does NOT append to members.cycles[] (period SSOT, no namespace mixing)', () => {
  assert.ok(!/UPDATE public\.members\b/.test(mig), 'RPC must not UPDATE members');
  assert.ok(!/array_append\([^)]*cycles/i.test(mig), 'RPC must not append to members.cycles');
  assert.match(mig, /does NOT append to members\.cycles/i, 'the design decision must be documented in the migration');
});

// ── DB-gated: self-gate proof — a service-role call (no auth.uid) is refused, i.e. the
//    manage_platform gate is actually wired (an ungated function would return a cohort). ──
test('#1104 DB: self-gates — unauthenticated (service-role, no auth.uid) call is refused', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('admin_roll_cycle_membership', {
    p_from_cycle: 'cycle_3', p_to_cycle: 'cycle_4', p_dry_run: true,
  });
  assert.ok(!error, `RPC should return a JSON error object, not throw: ${error?.message}`);
  assert.equal(data?.error, 'Not authenticated', `expected self-gate refusal, got: ${JSON.stringify(data)}`);
});
