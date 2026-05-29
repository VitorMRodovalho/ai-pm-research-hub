/**
 * Contract: p277 / #419 (ADR-0100) metric 3 — PR6: get_member_detail two-metric + reliability type-scope.
 *
 * (1) get_attendance_rate (reliability primitive): +event-type scope {geral,kickoff,tribo,lideranca};
 *     -remove the '2026-03-01' COALESCE fallback. reliability_summary.avg_rate auto-inherits.
 * (2) get_attendance_reliability_summary: type-scope the `recorded` CTE too (P/A/E counts don't auto-inherit).
 * (3) get_member_detail.attendance: fix 3 bugs + show BOTH per-member metrics:
 *     (a) attended=count(a.id) [any row] → present-filtered; (b) rate=count(a.id)/count(DISTINCT e.id)
 *     [silent 3rd denom] → engagement (Participação) + reliability (Confiabilidade) via canonical primitives;
 *     (c) recent[].present = att.id IS NOT NULL → att.present = true. Raw P/A/E/no_record + eligible recent[].
 *
 * Live smoke (as Vitor): Jefferson Pinto buggy rate 9.6% (27/281) → engagement 100% + reliability 100% (24/24
 * eligible, P24/A0/E0); recent[] eligible-only with present=att.present. Non-attendance member-detail sections
 * byte-identical. Reliability counts: global P586→577/A6→5/E56→54 (−12 non-elig), PMI-GO P198→191. md5 file==live.
 *
 * Migration: supabase/migrations/20260805000073_p277_419_m3_pr6_member_detail_reliability_typescope.sql
 * Frontend:  src/components/admin/members/MemberDetailIsland.tsx
 * Cross-ref: SPEC_419_M3_ATTENDANCE_TWO_METRIC.md surface [9] + §7 PR6 · ADR-0100.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000073_p277_419_m3_pr6_member_detail_reliability_typescope.sql');
const COMP = resolve(ROOT, 'src/components/admin/members/MemberDetailIsland.tsx');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const code = body.replace(/--[^\n]*/g, '');
const comp = existsSync(COMP) ? readFileSync(COMP, 'utf8') : '';

test('m3 PR6: get_attendance_rate type-scoped + 2026-03-01 fallback removed (same sig)', () => {
  assert.ok(existsSync(MIG), 'migration exists');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_attendance_rate\(p_member_id uuid, p_cycle_start date DEFAULT NULL::date\)/);
  assert.ok(!/DROP FUNCTION[^\n]*get_attendance_rate/i.test(body), 'same sig → no DROP');
  assert.ok(!/'2026-03-01'/.test(code), "the '2026-03-01' COALESCE fallback is removed");
  // event-type scope present in BOTH get_attendance_rate AND the reliability recorded CTE (2 occurrences)
  assert.ok((code.match(/e\.type IN \('geral', 'kickoff', 'tribo', 'lideranca'\)/g) || []).length >= 2, 'type scope on get_attendance_rate + reliability recorded CTE');
});

test('m3 PR6: reliability summary recorded CTE type-scoped (same 4-arg sig, avg via type-scoped rate)', () => {
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_attendance_reliability_summary\(p_scope text DEFAULT 'global', p_scope_id integer DEFAULT NULL, p_cycle_start date DEFAULT NULL, p_chapter text DEFAULT NULL\)/);
  assert.ok(!/DROP FUNCTION[^\n]*get_attendance_reliability_summary/i.test(body), 'same 4-arg sig → no DROP');
  // recorded CTE retains its present/absent/excused FILTERs AND now type-scopes
  assert.match(code, /recorded AS \([\s\S]*?att\.present = false AND att\.excused IS NOT TRUE[\s\S]*?e\.type IN \('geral', 'kickoff', 'tribo', 'lideranca'\)[\s\S]*?\)/, 'recorded CTE type-scoped');
});

test('m3 PR6: get_member_detail attendance → two-metric + raw counts (same sig)', () => {
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_member_detail\(p_member_id uuid\)/);
  assert.match(body, /SET search_path TO ''/, 'empty search_path preserved (public.-qualified refs)');
  assert.match(code, /'engagement_pct', ROUND\(COALESCE\(public\.get_attendance_engagement_rate\(p_member_id\), 0\) \* 100, 1\)/);
  assert.match(code, /'reliability_pct', ROUND\(COALESCE\(public\.get_attendance_rate\(p_member_id\), 0\) \* 100, 1\)/);
  for (const k of ['present', 'absent', 'excused', 'no_record', 'eligible_total']) {
    assert.ok(code.includes(`'${k}'`), `attendance raw count key ${k}`);
  }
  // recent[] now built from the member's eligible events
  assert.match(code, /'recent',[\s\S]*?public\._attendance_eligible_events\(p_member_id\)/);
  assert.match(body, /NOTIFY\s+pgrst/);
});

test('m3 PR6 forward-defense: the 3 get_member_detail bugs cannot reappear', () => {
  // bug (a): attended = count(a.id)
  assert.ok(!/'attended', count\(a\.id\)/.test(code), "bug (a) attended=count(a.id) gone");
  // bug (b): rate = count(a.id)/count(DISTINCT e.id)
  assert.ok(!/count\(a\.id\)::numeric \/ NULLIF\(count\(DISTINCT e\.id\)/.test(code), "bug (b) silent 3rd-denominator rate gone");
  // bug (c): present = att.id IS NOT NULL
  assert.ok(!/att\.id IS NOT NULL/.test(code), "bug (c) present=att.id IS NOT NULL gone");
});

test('m3 PR6 FE: MemberDetailIsland renders Participação + Confiabilidade w/ raw counts', () => {
  assert.ok(existsSync(COMP));
  assert.match(comp, /engagement_pct: number; reliability_pct: number/);
  assert.match(comp, /data\.attendance\.engagement_pct/);
  assert.match(comp, /data\.attendance\.reliability_pct/);
  assert.match(comp, /data\.attendance\.present[\s\S]*data\.attendance\.absent[\s\S]*data\.attendance\.excused/);
  assert.match(comp, /Participação/);
  assert.match(comp, /Confiabilidade/);
  // excused distinguished in the recent table (not just present/absent)
  assert.match(comp, /evt\.excused \?/);
  // old buggy fields no longer read
  assert.ok(!/data\.attendance\.rate\b/.test(comp), 'old .rate read gone');
  assert.ok(!/data\.attendance\.attended\b/.test(comp), 'old .attended read gone');
  assert.ok(!/data\.attendance\.total_events\b/.test(comp), 'old .total_events read gone');
});

// ── DB-gated ──────────────────────────────────────────────────────────────────
test('m3 PR6 DB: get_member_detail auth gate intact (unauthenticated rejected)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_member_detail', { p_member_id: '00000000-0000-0000-0000-000000000000' });
  assert.ok(error || (data && data.error), 'no-auth caller must be rejected (Forbidden)');
});

test('m3 PR6 DB: type-scoped primitives resolve + sane shape', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: rate, error: e1 } = await sb.rpc('get_attendance_rate', { p_member_id: '622ab18b-a8b4-46ff-b151-7bbd34394ed3' });
  assert.ok(!e1, e1?.message);
  assert.ok(rate === null || (Number(rate) >= 0 && Number(rate) <= 1), `rate is a 0..1 fraction (got ${rate})`);
  const { data: rel, error: e2 } = await sb.rpc('get_attendance_reliability_summary', { p_scope: 'global' });
  assert.ok(!e2, e2?.message);
  assert.ok(Number(rel.present_total) >= 0 && Number(rel.absent_total) >= 0 && Number(rel.excused_total) >= 0, 'recorded counts present');
  assert.ok(Number(rel.avg_rate) > 0.9 && Number(rel.avg_rate) <= 1, 'global reliability avg ~0.99');
});
