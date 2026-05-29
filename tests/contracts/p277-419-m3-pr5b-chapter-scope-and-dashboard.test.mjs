/**
 * Contract: p277 / #419 (ADR-0100) metric 3 — PR5b: 'chapter' scope on summaries + get_chapter_dashboard.
 *
 * (1) get_attendance_engagement_summary + get_attendance_reliability_summary → 4-arg (DROP+CREATE, add
 *     p_chapter text DEFAULT NULL + a 'chapter' scope cohort = member_status='active' AND chapter=p_chapter,
 *     the §7 carve-out). The 1-2-arg callers PR2..PR4 resolve unchanged (defaults fill the rest); exactly
 *     ONE overload each (DROP prevents an ambiguous overload set).
 * (2) get_chapter_dashboard.attendance was distinct-present-members/chapter-members over a 90-day window with
 *     NO event-type filter (reach metric, leaked entrevista/1on1/parceria/iniciativa). Now: engagement
 *     (headline, Participação) + reliability (ops diagnostic, raw P/A/E) via the new 'chapter' scope + a real
 *     hub_engagement_pct (was a hardcoded 70 in the FE chart). Volume helpers gain the
 *     {geral,kickoff,tribo,lideranca} type set + cycles.is_current window. members[].attendance_pct → engagement.
 *
 * Live smoke (as Vitor): PMI-GO non-attendance byte-identical (active 20, hub 52, pubs 32, hours 622.7, certs 7,
 * avg_xp 517, members 20); attendance reach 75% → engagement 50.4% (cohort 20) + reliability 98.8% (P198/E28);
 * avg_events 9.9→9.6, total 198→191 (type filter). calc_attendance_pct=76.2, tribe2 eng=0.5183, exec_cycle_report
 * eng=0.7619 (PR2/PR4/PR5a callers unbroken). overload_count=1 both summaries. md5 file==live all 3 fns.
 *
 * Migration: supabase/migrations/20260805000072_p277_419_m3_pr5b_chapter_scope_and_dashboard.sql
 * Frontend:  src/components/chapter/ChapterDashboard.tsx
 * Cross-ref: SPEC_419_M3_ATTENDANCE_TWO_METRIC.md surface [7] + §6 D4/D9/D10 + §7 PR5 · ADR-0100.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000072_p277_419_m3_pr5b_chapter_scope_and_dashboard.sql');
const COMP = resolve(ROOT, 'src/components/chapter/ChapterDashboard.tsx');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const code = body.replace(/--[^\n]*/g, '');
const comp = existsSync(COMP) ? readFileSync(COMP, 'utf8') : '';

test('m3 PR5b: both summaries DROP+CREATE to 4-arg with a chapter cohort branch', () => {
  assert.ok(existsSync(MIG), 'migration exists');
  for (const fn of ['get_attendance_engagement_summary', 'get_attendance_reliability_summary']) {
    assert.ok(new RegExp(`DROP FUNCTION IF EXISTS public\\.${fn}\\(text, integer, date\\)`).test(body), `${fn}: DROP 3-arg`);
    assert.ok(new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\(p_scope text DEFAULT 'global', p_scope_id integer DEFAULT NULL, p_cycle_start date DEFAULT NULL, p_chapter text DEFAULT NULL\\)`).test(body), `${fn}: 4-arg signature`);
    assert.ok(new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn}\\(text, integer, date, text\\) TO service_role`).test(body), `${fn}: grant on 4-arg sig`);
  }
  // chapter cohort = member_status='active' AND chapter=p_chapter (§7 carve-out), appears in BOTH summaries
  const chapterBranch = code.match(/WHEN p_scope = 'chapter' THEN \(m\.member_status = 'active' AND m\.chapter = p_chapter\)/g) || [];
  assert.equal(chapterBranch.length, 2, 'chapter cohort branch in both summaries');
  // global/tribe branch (operational union) preserved
  assert.ok(code.includes("m.operational_role IN ('researcher', 'tribe_leader', 'manager')"), 'operational cohort preserved for global/tribe');
  // engagement summary keeps at_risk_count (carried from PR5a)
  assert.match(code, /'at_risk_count', \(SELECT count\(\*\) FROM rates WHERE rate IS NOT NULL AND rate < 0\.50\)/);
  assert.match(body, /NOTIFY\s+pgrst/);
});

test('m3 PR5b: get_chapter_dashboard attendance → engagement + reliability + hub_engagement_pct', () => {
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_chapter_dashboard\(p_chapter text DEFAULT NULL::text\)/, 'same signature');
  assert.match(body, /SET search_path TO ''/, 'empty search_path preserved (all refs public.-qualified)');
  assert.match(code, /'engagement', public\.get_attendance_engagement_summary\('chapter', NULL, NULL, v_chapter\)/);
  assert.match(code, /'reliability', public\.get_attendance_reliability_summary\('chapter', NULL, NULL, v_chapter\)/);
  assert.match(code, /'hub_engagement_pct', ROUND\(COALESCE\(\(public\.get_attendance_engagement_summary\('global'\) ->> 'avg_rate'\)::numeric, 0\) \* 100, 1\)/);
  // members[].attendance_pct converges to per-member engagement
  assert.match(code, /COALESCE\(ROUND\(public\.get_attendance_engagement_rate\(m\.id\) \* 100\), 0\) AS attendance_pct/);
  // volume helpers: event-type set + cycles.is_current window
  assert.ok((code.match(/e\.type IN \('geral','kickoff','tribo','lideranca'\)/g) || []).length >= 2, 'type filter on both volume helpers');
  assert.ok((code.match(/e\.date >= \(SELECT cycle_start FROM public\.cycles WHERE is_current = true LIMIT 1\)/g) || []).length >= 2, 'cycle window on both volume helpers');
});

test('m3 PR5b forward-defense: 90-day window + reach rate_pct + hub_participation_pct retired', () => {
  assert.ok(!/interval '90 days'/.test(code), "90-day rolling window removed");
  assert.ok(!/'rate_pct'/.test(code), "reach 'rate_pct' key retired from attendance");
  assert.ok(!/'hub_participation_pct'/.test(code), "reach 'hub_participation_pct' key retired");
});

test('m3 PR5b FE: ChapterDashboard chart + card consume engagement object + reliability raw counts', () => {
  assert.ok(existsSync(COMP));
  // chart: chapter bar = engagement, hub bar = real hub_engagement_pct (was hardcoded 70)
  assert.match(comp, /a\.engagement\?\.avg_rate != null \? Math\.round\(a\.engagement\.avg_rate \* 100\)/);
  assert.match(comp, /a\.hub_engagement_pct \|\| 0/);
  assert.ok(!/p\.hub_total \|\| 0, 70,/.test(comp), 'hardcoded 70 hub baseline removed');
  assert.ok(!/a\.rate_pct/.test(comp), 'old a.rate_pct reads removed');
  // MetricCard: engagement headline + reliability with raw P/A/E (D10)
  assert.match(comp, /a\.reliability\?\.present_total[\s\S]*a\.reliability\?\.absent_total[\s\S]*a\.reliability\?\.excused_total/);
  // i18n: "Participação" headline, banned bare "Taxa de Presença" gone, reliabilityLbl in all 3 langs
  assert.ok(!/'Taxa de Presença'|'Attendance Rate'|'Tasa de Asistencia'/.test(comp), 'attendance label no longer the banned reach phrasing');
  assert.equal((comp.match(/reliabilityLbl:/g) || []).length, 3, 'reliabilityLbl in all 3 language blocks');
  // per-member table column now shows engagement → reuse t.attendance (Participação); banned 'Presença'/'Attendance' label retired
  assert.ok(!/attendanceLbl/.test(comp), 'attendanceLbl (Presença/Attendance) retired — member column reuses t.attendance');
  // orphan i18n keys removed (sub no longer shows activeParticipation/eventsPerMember)
  assert.ok(!/activeParticipation|eventsPerMember/.test(comp), 'orphan i18n keys removed');
});

// ── DB-gated ──────────────────────────────────────────────────────────────────
test('m3 PR5b DB: chapter scope returns the member_status=active cohort engagement', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_attendance_engagement_summary', { p_scope: 'chapter', p_chapter: 'PMI-GO' });
  assert.ok(!error, error?.message);
  assert.equal(Number(data.cohort_n), 20, 'PMI-GO chapter cohort (member_status=active) = 20');
  const r = Number(data.avg_rate);
  assert.ok(r > 0.40 && r < 0.60, `PMI-GO engagement ~0.50 (got ${r})`);
  assert.ok(Object.prototype.hasOwnProperty.call(data, 'at_risk_count'), 'at_risk_count still present on 4-arg');
});

test('m3 PR5b DB: reliability chapter scope + 1-2 arg callers still resolve (no ambiguous overload)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: rel, error: e1 } = await sb.rpc('get_attendance_reliability_summary', { p_scope: 'chapter', p_chapter: 'PMI-GO' });
  assert.ok(!e1, e1?.message);
  assert.ok(Number(rel.avg_rate) > 0.9, 'PMI-GO reliability ~0.99');
  assert.ok(['present_total', 'absent_total', 'excused_total'].every((k) => Object.prototype.hasOwnProperty.call(rel, k)), 'raw counts present');
  // 1-arg global call must still resolve unambiguously to the 4-arg fn
  const { data: g, error: e2 } = await sb.rpc('get_attendance_engagement_summary', { p_scope: 'global' });
  assert.ok(!e2, e2?.message);
  assert.equal(Number(g.cohort_n), 37, 'global cohort still 37 (PR2-PR4 callers unbroken)');
});

test('m3 PR5b DB: get_chapter_dashboard auth gate intact (unauthenticated → error envelope)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_chapter_dashboard', { p_chapter: 'PMI-GO' });
  // no JWT → auth.uid() NULL → {error: 'Not authenticated'} envelope (not a PG error)
  assert.ok(error || (data && data.error), 'unauthenticated caller must not receive chapter data');
});
