/**
 * Contract: p277 / #419 (ADR-0100) metric 3 — PR4: exec_cross_initiative_comparison attendance → engagement.
 *
 * The admin cross-tribe comparison's per-initiative attendance_rate used a members×events recorded denominator
 * + a hardcoded '2026-03-01' window. Now: v_cycle_start → cycles.is_current; attendance_rate → for tribe-bridged
 * initiatives delegate to get_attendance_engagement_summary('tribe', t.id), native → NULL (N/A). Frontend
 * CrossTribeWidget drops the now-unneeded Math.min(.,100) clamp (engagement is 0..1 by construction).
 *
 * Live smoke (as Vitor): 8 initiatives; tribe 2 attendance_rate=0.5183 == engagement('tribe',2). md5 file==live.
 * NOTE: get_admin_dashboard + get_kpi_dashboard (SPEC PR4 surface list) compute NO attendance rate — corrected.
 *
 * Migration: supabase/migrations/20260805000070_p277_419_m3_pr4_cross_initiative_attendance_engagement.sql
 * Frontend: src/components/admin/CrossTribeWidget.tsx
 * Cross-ref: SPEC_419_M3_ATTENDANCE_TWO_METRIC.md surface [6] · ADR-0100.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000070_p277_419_m3_pr4_cross_initiative_attendance_engagement.sql');
const WIDGET = resolve(ROOT, 'src/components/admin/CrossTribeWidget.tsx');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const code = body.replace(/--[^\n]*/g, '');
const widget = existsSync(WIDGET) ? readFileSync(WIDGET, 'utf8') : '';

test('m3 PR4: exec_cross_initiative_comparison same signature + cycles.is_current window + engagement attendance', () => {
  assert.ok(existsSync(MIG));
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.exec_cross_initiative_comparison\(p_kind text DEFAULT 'research_tribe'::text, p_cycle text DEFAULT NULL::text\)/i);
  assert.ok(!/DROP FUNCTION/i.test(body), 'same signature → no DROP');
  assert.match(body, /v_cycle_start date := \(SELECT cycle_start FROM public\.cycles WHERE is_current = true LIMIT 1\);/i, 'window from cycles.is_current');
  assert.match(body, /'attendance_rate', CASE WHEN t\.id IS NOT NULL THEN COALESCE\(\(public\.get_attendance_engagement_summary\('tribe', t\.id\) ->> 'avg_rate'\)::numeric, 0\) ELSE NULL END/i, 'attendance_rate delegates to engagement for tribe rows, NULL for native');
  assert.match(body, /NOTIFY\s+pgrst/i);
});

test('m3 PR4 forward-defense: no 2026-03-01 literal + no members×events attendance denominator', () => {
  assert.ok(!/'2026-03-01'/.test(code), 'hardcoded window literal removed');
  // the old attendance_rate denominator was (member count) * COUNT(DISTINCT ev.id)
  assert.ok(!/\)\s*\*\s*COUNT\(DISTINCT ev\.id\)/i.test(code), 'members×events attendance denominator removed');
});

test('m3 PR4 FE: CrossTribeWidget drops the Math.min(.,100) attendance clamp', () => {
  assert.ok(existsSync(WIDGET));
  assert.match(widget, /attendance_rate: Math\.round\(it\.attendance_rate \* 100\),/i, 'plain round, no clamp');
  assert.ok(!/Math\.min\(Math\.round\(it\.attendance_rate \* 100\), 100\)/i.test(widget), 'old Math.min clamp removed');
});

// ── DB-gated ──────────────────────────────────────────────────────────────────
test('m3 PR4 DB: auth gate intact (unauthenticated service-role rejected)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { error } = await sb.rpc('exec_cross_initiative_comparison', { p_kind: 'research_tribe' });
  assert.ok(error, 'no-auth caller must be rejected (Not authenticated)');
});
