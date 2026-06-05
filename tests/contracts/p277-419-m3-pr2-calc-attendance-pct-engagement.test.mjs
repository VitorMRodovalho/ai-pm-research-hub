/**
 * Contract: p277 / #419 (ADR-0100) metric 3 — PR2: calc_attendance_pct → canonical engagement.
 *
 * calc_attendance_pct() (platform-average attendance %, feeds get_annual_kpis → admin/portfolio +
 * ChapterDashboard) was a buggy hybrid: hardcoded '2026-01-01', counted 1on1, included guests, used the
 * LEGACY members.tribe_id, expected-events denominator. Live 64.4%. Now DELEGATES to the canonical
 * get_attendance_engagement_summary('global') (PR1 foundation) → 76.2%. No inline rate re-impl (PR10 gate).
 *
 * ANTES→DEPOIS: 64.4% (buggy) → 76.2% (canonical engagement). Same 0-arg signature.
 *
 * Migration: supabase/migrations/20260805000067_p277_419_m3_pr2_calc_attendance_pct_to_engagement.sql
 * Cross-ref: SPEC_419_M3_ATTENDANCE_TWO_METRIC.md surface [1] · ADR-0100.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000067_p277_419_m3_pr2_calc_attendance_pct_to_engagement.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const code = body.replace(/--[^\n]*/g, '');

test('m3 PR2: calc_attendance_pct delegates to the canonical engagement summary, same 0-arg signature', () => {
  assert.ok(existsSync(MIG));
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.calc_attendance_pct\(\)\s*\n\s*RETURNS numeric/i);
  assert.ok(!/DROP FUNCTION/i.test(body), 'same signature → no DROP');
  assert.match(body, /\(public\.get_attendance_engagement_summary\('global'\) ->> 'avg_rate'\)::numeric \* 100/i, 'delegates to engagement summary');
  assert.match(body, /NOTIFY\s+pgrst/i);
});

test('m3 PR2 forward-defense: the old buggy hybrid is gone (no 2026-01-01 literal, no 1on1, no legacy tribe_id, no inline rate)', () => {
  assert.ok(!/'2026-01-01'/.test(code), 'hardcoded window literal removed');
  assert.ok(!/'1on1'/.test(code), 'no 1on1 counting');
  assert.ok(!/m\.tribe_id/i.test(code), 'no legacy members.tribe_id (V4 get_member_tribe via the canonical primitive)');
  assert.ok(!/count\(\*\)\s+FROM\s+attendance/i.test(code), 'no inline attendance rate re-implementation (delegation only)');
});

// ── DB-gated ──────────────────────────────────────────────────────────────────
test('m3 PR2 DB: calc_attendance_pct == canonical engagement global, and is no longer the 64.4 hybrid', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const calc = await sb.rpc('calc_attendance_pct');
  assert.ok(!calc.error, calc.error?.message);
  const eng = await sb.rpc('get_attendance_engagement_summary', { p_scope: 'global' });
  assert.ok(!eng.error, eng.error?.message);
  const calcPct = Number(calc.data);
  const engPct = Math.round(Number(eng.data.avg_rate) * 100 * 10) / 10;
  assert.equal(calcPct, engPct, 'calc_attendance_pct must equal engagement avg_rate × 100 (delegation)');
  assert.ok(calcPct >= 0 && calcPct <= 100, `must be a 0..100 percentage, got ${calcPct}`);
});
