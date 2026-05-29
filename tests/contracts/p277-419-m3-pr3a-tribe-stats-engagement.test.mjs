/**
 * Contract: p277 / #419 (ADR-0100) metric 3 — PR3a: get_tribe_stats.attendance_rate → engagement.
 *
 * The tribe gamification-tab attendance_rate used a members×events denominator over non-excused recorded
 * rows (present+absent). Now the headline rate delegates to get_attendance_engagement_summary('tribe',
 * p_tribe_id) (PR1). No inline rate re-impl. ANTES→DEPOIS (live): tribe2 ~99%→51.8, tribe5→92.7, tribe1→90.8.
 * top_contributors + impact_hours unchanged (separate concerns).
 *
 * Migration: supabase/migrations/20260805000068_p277_419_m3_pr3a_tribe_stats_engagement.sql
 * Cross-ref: SPEC_419_M3_ATTENDANCE_TWO_METRIC.md surface [4] · ADR-0100.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000068_p277_419_m3_pr3a_tribe_stats_engagement.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

test('m3 PR3a: get_tribe_stats.attendance_rate delegates to engagement(tribe), same signature', () => {
  assert.ok(existsSync(MIG));
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_tribe_stats\(p_tribe_id integer\)/i);
  assert.ok(!/DROP FUNCTION/i.test(body), 'same signature → no DROP');
  assert.match(body, /'attendance_rate', ROUND\(\(public\.get_attendance_engagement_summary\('tribe', p_tribe_id\) ->> 'avg_rate'\)::numeric \* 100, 1\)/i, 'attendance_rate delegates to engagement summary');
  assert.match(body, /NOTIFY\s+pgrst/i);
});

test('m3 PR3a forward-defense: the members×events denominator is gone from attendance_rate', () => {
  // the inflated denominator (tribe_members count × tribe_events count) was unique to the old attendance_rate
  assert.ok(!/FROM tribe_members\)\s*\*\s*\(SELECT count\(\*\) FROM tribe_events/i.test(body), 'no members×events product denominator');
});

// ── DB-gated ──────────────────────────────────────────────────────────────────
test('m3 PR3a DB: every tribe attendance_rate == its engagement(tribe) avg_rate × 100', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: tribes, error } = await sb.from('tribes').select('id').eq('is_active', true);
  assert.ok(!error, error?.message);
  for (const t of tribes) {
    const stats = await sb.rpc('get_tribe_stats', { p_tribe_id: t.id });
    assert.ok(!stats.error, stats.error?.message);
    const eng = await sb.rpc('get_attendance_engagement_summary', { p_scope: 'tribe', p_scope_id: t.id });
    assert.ok(!eng.error, eng.error?.message);
    const rate = stats.data.attendance_rate;
    const expected = eng.data.avg_rate == null ? null : Math.round(Number(eng.data.avg_rate) * 100 * 10) / 10;
    assert.equal(rate == null ? null : Number(rate), expected, `tribe ${t.id}: attendance_rate must equal engagement avg_rate × 100`);
  }
});
