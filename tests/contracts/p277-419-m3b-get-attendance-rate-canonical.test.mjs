/**
 * Contract: p277 / #419 (ADR-0100) metric 3 step 3b — canonical get_attendance_rate primitive (FOUNDATION).
 *
 * Per-member rate = present / (present + absent), excused excluded, current-cycle window
 * (cycles.is_current), fraction 0..1 ROUND 2, NULL when no eligible events. Cancelled + future events
 * excluded. ADDITIVE — nothing consumes it yet (0 live number changes); the ~21 attendance_rate surfaces
 * converge onto it in subsequent per-surface PRs (each with an antes→depois). Not anon/authenticated-
 * granted (LGPD): internal SECDEF callers + service_role only.
 *
 * Live smoke: 3 sample members rpc==manual; canonical global avg (AVG of per-member rates) = 99.1%
 * (recorded-status denominator — will differ from surfaces that use an "expected events" denominator).
 *
 * Migration: supabase/migrations/20260805000065_p277_419_m3b_get_attendance_rate_canonical.sql
 * Cross-ref: ADR-0100 §2.2/§2.3 · audit D6/D12 (the present-detection bugs fixed in 3a).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000065_p277_419_m3b_get_attendance_rate_canonical.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

test('m3b: get_attendance_rate canonical formula + signature', () => {
  assert.ok(existsSync(MIG));
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_attendance_rate\(p_member_id uuid, p_cycle_start date DEFAULT NULL\)/i);
  assert.match(body, /RETURNS numeric/i);
  assert.match(body, /count\(\*\) FILTER \(WHERE a\.present = true\)::numeric/i, 'numerator = present');
  assert.match(body, /NULLIF\(count\(\*\) FILTER \(WHERE a\.excused IS NOT TRUE\), 0\)/i, 'denominator = non-excused (present+absent), NULL-safe');
  assert.match(body, /ROUND\([\s\S]*?,\s*2\s*\)/i, 'fraction ROUND 2');
});

test('m3b: current-cycle window from cycles.is_current (no hardcoded cycle code), cancelled + future excluded', () => {
  assert.match(body, /COALESCE\(p_cycle_start, \(SELECT c\.cycle_start FROM public\.cycles c WHERE c\.is_current = true LIMIT 1\)/i, 'window from cycles.is_current');
  assert.match(body, /e\.date <= CURRENT_DATE/i, 'future events excluded');
  assert.match(body, /e\.status IS DISTINCT FROM 'cancelled'/i, 'cancelled events excluded');
});

test('m3b: STABLE + SECDEF + pinned search_path', () => {
  assert.match(body, /\bSTABLE\b/i);
  assert.match(body, /SECURITY DEFINER/i);
  assert.match(body, /SET search_path TO 'public', 'pg_temp'/i);
});

test('m3b: LGPD — not anon/authenticated granted, service_role only', () => {
  assert.match(body, /REVOKE ALL ON FUNCTION public\.get_attendance_rate\(uuid, date\) FROM PUBLIC, anon, authenticated/i);
  assert.match(body, /GRANT EXECUTE ON FUNCTION public\.get_attendance_rate\(uuid, date\) TO service_role/i);
  assert.match(body, /NOTIFY\s+pgrst/i);
});

test('m3b forward-defense: NOT the calc_attendance_pct expected-events denominator', () => {
  // the canonical denominator is recorded present/absent rows, NOT an "expected events" projection
  const code = body.replace(/--[^\n]*/g, '');
  assert.ok(!/expected/i.test(code), 'no expected-events denominator (that was the calc_attendance_pct fork)');
});

// ── DB-gated ──────────────────────────────────────────────────────────────────
test('m3b DB: rate is a 0..1 fraction; unknown member → NULL (NULL-safe)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const none = await sb.rpc('get_attendance_rate', { p_member_id: '00000000-0000-0000-0000-000000000000' });
  assert.ok(!none.error, none.error?.message);
  assert.equal(none.data, null, 'no eligible events → NULL (NULLIF denominator)');

  const { data: anyRow } = await sb.from('attendance').select('member_id').eq('present', true).limit(1).single();
  if (anyRow?.member_id) {
    const r = await sb.rpc('get_attendance_rate', { p_member_id: anyRow.member_id });
    assert.ok(!r.error, r.error?.message);
    if (r.data != null) {
      const v = Number(r.data);
      assert.ok(v >= 0 && v <= 1, `rate must be a 0..1 fraction, got ${r.data}`);
    }
  }
});
