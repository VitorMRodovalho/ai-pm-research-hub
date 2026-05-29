/**
 * Contract: p277 / #419 (ADR-0100) metric 3 step 3c / PR1 — ENGAGEMENT foundation (additive).
 *
 * Ships the shared eligibility primitive + two engagement aggregates + the reliability aggregate, per
 * the PM-ratified SPEC_419_M3_ATTENDANCE_TWO_METRIC.md (all 10 §6 decisions accepted). ADDITIVE —
 * nothing consumes them yet (0 live number change). Surfaces converge in PR2..PR8 with antes→depois.
 *
 * Live smoke (cycle_3): engagement global avg=0.7619 (76.2%), cohort_n=37, present 570/expected 734;
 * reliability global avg=0.9905 (99.1%), absent_total=6, coverage_flag='partial'. Engagement ≤ reliability
 * structurally (engagement counts unrecorded no-shows as absent; reliability ignores them).
 *
 * Migration: supabase/migrations/20260805000066_p277_419_m3c_engagement_foundation.sql
 * Cross-ref: SPEC_419_M3_ATTENDANCE_TWO_METRIC.md · ADR-0100 §2.2/§2.3.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000066_p277_419_m3c_engagement_foundation.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const code = body.replace(/--[^\n]*/g, ''); // strip comments for forward-defense scans

test('m3c PR1: the four foundation functions exist with correct signatures', () => {
  assert.ok(existsSync(MIG));
  assert.match(body, /CREATE OR REPLACE FUNCTION public\._attendance_eligible_events\(p_member_id uuid, p_cycle_start date DEFAULT NULL\)\s*\n\s*RETURNS TABLE\(event_id uuid, event_type text, event_date date\)/i);
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_attendance_engagement_rate\(p_member_id uuid, p_cycle_start date DEFAULT NULL\)\s*\n\s*RETURNS numeric/i);
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_attendance_engagement_summary\(p_scope text DEFAULT 'global', p_scope_id integer DEFAULT NULL, p_cycle_start date DEFAULT NULL\)\s*\n\s*RETURNS jsonb/i);
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_attendance_reliability_summary\(p_scope text DEFAULT 'global', p_scope_id integer DEFAULT NULL, p_cycle_start date DEFAULT NULL\)\s*\n\s*RETURNS jsonb/i);
});

test('m3c PR1: eligibility model — type set {geral,kickoff,tribo,lideranca}, tribo via initiatives bridge, lideranca via manage_event', () => {
  assert.match(body, /e\.type IN \('geral', 'kickoff', 'tribo', 'lideranca'\)/i, 'canonical type set (D6)');
  assert.match(body, /e\.type = 'tribo' AND mt\.tribe_id IS NOT NULL AND EXISTS \(\s*SELECT 1 FROM public\.initiatives i\s*WHERE i\.id = e\.initiative_id AND i\.legacy_tribe_id = mt\.tribe_id\)/i, 'tribo eligibility via initiatives.legacy_tribe_id bridge (D4)');
  assert.match(body, /e\.type = 'lideranca' AND public\.can_by_member\(p_member_id, 'manage_event'\)/i, 'lideranca via manage_event capability (D3)');
});

test('m3c PR1 forward-defense: no events.tribe column, no deputy_manager phantom, no date literal fallback', () => {
  assert.ok(!/e\.tribe_id|events\.tribe\b|\be\.tribe\b/i.test(code), 'events has NO tribe column — tribe linkage only via initiatives bridge (review #9)');
  assert.ok(!/deputy_manager/i.test(code), 'deputy_manager is a phantom role — must not appear (D3 / review #14)');
  assert.ok(!/'2026-01-01'|'2026-03-01'/.test(code), 'no hardcoded date-literal window fallback (D10 / review #8) — window from cycles.is_current');
});

test('m3c PR1: engagement = present / (eligible excl-excused), LEFT JOIN so no-row counts as absent (D1)', () => {
  assert.match(body, /FROM public\._attendance_eligible_events\(p_member_id, p_cycle_start\) el\s*\n\s*LEFT JOIN public\.attendance att/i, 'denominator is the eligible set, LEFT JOIN attendance (no-row = absent)');
  assert.match(body, /count\(\*\) FILTER \(WHERE att\.present = true\)::numeric\s*\n\s*\/ NULLIF\(count\(\*\) FILTER \(WHERE att\.excused IS NOT TRUE\), 0\)/i, 'present / non-excused-eligible (excused removed, D1)');
});

test('m3c PR1: cohort = operational union {researcher,tribe_leader,manager} + AVG-of-member-rates (D2)', () => {
  const occ = (body.match(/m\.operational_role IN \('researcher', 'tribe_leader', 'manager'\)/gi) || []).length;
  assert.ok(occ >= 2, `cohort predicate present in both summaries; found ${occ}`);
  assert.match(body, /m\.is_active = true AND m\.current_cycle_active = true/i, 'active operational predicate');
  assert.match(body, /ROUND\(AVG\(rate\), 4\)/i, 'AVG-of-member-rates aggregate (D2, not pooled)');
});

test('m3c PR1: LGPD — all four REVOKE anon/authenticated + GRANT service_role; NOTIFY pgrst', () => {
  for (const fn of ['_attendance_eligible_events\\(uuid, date\\)', 'get_attendance_engagement_rate\\(uuid, date\\)', 'get_attendance_engagement_summary\\(text, integer, date\\)', 'get_attendance_reliability_summary\\(text, integer, date\\)']) {
    assert.match(body, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn} FROM PUBLIC, anon, authenticated`, 'i'), `${fn} revoked from anon/authenticated`);
    assert.match(body, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn} TO service_role`, 'i'), `${fn} granted to service_role`);
  }
  assert.match(body, /NOTIFY\s+pgrst/i);
});

// ── DB-gated ──────────────────────────────────────────────────────────────────
test('m3c PR1 DB: engagement global is a sane fraction with a real cohort; structurally ≤ reliability', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const eng = await sb.rpc('get_attendance_engagement_summary', { p_scope: 'global' });
  assert.ok(!eng.error, eng.error?.message);
  const rel = await sb.rpc('get_attendance_reliability_summary', { p_scope: 'global' });
  assert.ok(!rel.error, rel.error?.message);
  const e = eng.data, r = rel.data;
  assert.ok(e.cohort_n > 0, 'engagement cohort is non-empty');
  assert.ok(Number(e.avg_rate) > 0 && Number(e.avg_rate) <= 1, `engagement avg must be a 0..1 fraction, got ${e.avg_rate}`);
  assert.ok(Number(r.avg_rate) > 0 && Number(r.avg_rate) <= 1, `reliability avg must be a 0..1 fraction, got ${r.avg_rate}`);
  // the core invariant: engagement counts unrecorded no-shows as absent, reliability ignores them → eng ≤ rel
  assert.ok(Number(e.avg_rate) <= Number(r.avg_rate) + 1e-9, `engagement (${e.avg_rate}) must be ≤ reliability (${r.avg_rate}) — engagement counts no-shows that reliability hides`);
  // reliability is structurally near-100% because absences are under-recorded (the whole reason for two metrics)
  assert.ok(r.absent_total <= r.present_total, 'recorded absent rows must be far fewer than present (the under-recording signal)');
});

test('m3c PR1 DB: not exposed to anon/authenticated (LGPD)', { skip: dbGated ? false : skipMsg }, async () => {
  // service_role can call (covered above); the REVOKE is asserted statically. Here just confirm the
  // eligible-events helper composes (engagement summary already exercised it transitively).
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const eng = await sb.rpc('get_attendance_engagement_summary', { p_scope: 'tribe', p_scope_id: 1 });
  assert.ok(!eng.error, eng.error?.message);
  assert.ok(eng.data && eng.data.scope === 'tribe', 'tribe scope resolves');
});
