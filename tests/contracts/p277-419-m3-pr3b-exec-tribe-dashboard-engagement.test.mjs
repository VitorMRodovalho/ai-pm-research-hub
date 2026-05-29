/**
 * Contract: p277 / #419 (ADR-0100) metric 3 — PR3b: exec_tribe_dashboard attendance → engagement.
 *
 * Three surgical changes to the 12.9KB tribe-KPI-tab dashboard (body otherwise byte-faithful, functionally
 * smoke-verified all 6 sections intact): (1) v_cycle_start kickoff-ILIKE/'2026-03-05' fork → cycles.is_current;
 * (2) per-member attendance_rate inline recorded + LEAST guard → get_attendance_engagement_rate(m.id);
 * (3) aggregate v_attendance_rate members×meetings + LEAST guard → get_attendance_engagement_summary('tribe').
 *
 * Live smoke (as Vitor): tribe 2 engagement.attendance_rate=0.5183 (==get_tribe_stats 51.8), all 6 sections
 * present, member list intact, per-member engagement fractions.
 *
 * Migration: supabase/migrations/20260805000069_p277_419_m3_pr3b_exec_tribe_dashboard_engagement.sql
 * Cross-ref: SPEC_419_M3_ATTENDANCE_TWO_METRIC.md surface [3] · ADR-0100.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000069_p277_419_m3_pr3b_exec_tribe_dashboard_engagement.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const code = body.replace(/--[^\n]*/g, '');

test('m3 PR3b: exec_tribe_dashboard same signature + the three engagement fixes', () => {
  assert.ok(existsSync(MIG));
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.exec_tribe_dashboard\(p_tribe_id integer, p_cycle text DEFAULT NULL::text\)/i);
  assert.ok(!/DROP FUNCTION/i.test(body), 'same signature → no DROP');
  assert.match(body, /v_cycle_start := \(SELECT cycle_start FROM public\.cycles WHERE is_current = true LIMIT 1\);/i, 'fix 1: window from cycles.is_current');
  assert.match(body, /'attendance_rate', COALESCE\(public\.get_attendance_engagement_rate\(m\.id\), 0\)/i, 'fix 2: per-member engagement');
  assert.match(body, /v_attendance_rate := COALESCE\(\(public\.get_attendance_engagement_summary\('tribe', p_tribe_id\) ->> 'avg_rate'\)::numeric, 0\)/i, 'fix 3: aggregate engagement');
  assert.match(body, /NOTIFY\s+pgrst/i);
});

test('m3 PR3b forward-defense: kickoff-ILIKE window + both LEAST guardrails gone', () => {
  assert.ok(!/ILIKE '%kick%off%'/i.test(code), 'kickoff-ILIKE v_cycle_start fork removed');
  assert.ok(!/LEAST\(COALESCE/i.test(code), 'per-member LEAST(COALESCE(...rate...),1.0) guard removed');
  assert.ok(!/v_members_active \* v_total_meetings/i.test(code), 'aggregate members×meetings denominator removed');
});

test('m3 PR3b: all six dashboard sections preserved (no body truncation)', () => {
  for (const section of ['tribe', 'members', 'production', 'engagement', 'gamification', 'trends']) {
    assert.match(body, new RegExp(`'${section}', jsonb_build_object`, 'i'), `${section} section preserved`);
  }
  assert.match(body, /RETURN v_result;/i);
});

// ── DB-gated ──────────────────────────────────────────────────────────────────
test('m3 PR3b DB: auth gate intact (unauthenticated service-role rejected)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { error } = await sb.rpc('exec_tribe_dashboard', { p_tribe_id: 2 });
  assert.ok(error, 'no-auth caller must be rejected (member not found)');
});
