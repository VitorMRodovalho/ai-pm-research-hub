/**
 * Contract: p277 / #419 (ADR-0100) metric 3 — PR5a: exec_cycle_report attendance → engagement+reliability.
 *
 * The cycle report's per-tribe attendance array consumed get_attendance_summary(...).combined_pct (the hidden
 * 0.4*geral + 0.6*tribe weighting D9 ratified to DROP). PR5a DECOUPLES: attendance is now an object
 * {engagement, reliability, by_tribe[]} sourced from the canonical summaries — get_attendance_summary is no
 * longer called. get_attendance_engagement_summary gains an additive at_risk_count (engagement < 0.50).
 *
 * Live smoke (as Vitor): non-attendance scalars byte-identical (76/52/87/7/39/206/1331/0); attendance.engagement
 * global=0.7619 (cohort 37, at_risk 4); reliability=0.9905; by_tribe[7]; tribe2 combined 49.5% → engagement 51.8%
 * (reliability 98.7%, P61/A1/E6). calc_attendance_pct() = 76.2 (PR2 consumer unbroken). md5 file==live both fns.
 *
 * Migration: supabase/migrations/20260805000071_p277_419_m3_pr5a_cycle_report_attendance_engagement.sql
 * Frontend:  src/pages/admin/cycle-report.astro
 * Cross-ref: SPEC_419_M3_ATTENDANCE_TWO_METRIC.md surface [7] + §7 PR5 · ADR-0100.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000071_p277_419_m3_pr5a_cycle_report_attendance_engagement.sql');
const PAGE = resolve(ROOT, 'src/pages/admin/cycle-report.astro');
const DICTS = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => resolve(ROOT, `src/i18n/${l}.ts`));

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const code = body.replace(/--[^\n]*/g, '');           // strip line comments for forward-defense
const page = existsSync(PAGE) ? readFileSync(PAGE, 'utf8') : '';

test('m3 PR5a: engagement summary gains at_risk_count (same 3-arg signature, additive)', () => {
  assert.ok(existsSync(MIG), 'migration file exists');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_attendance_engagement_summary\(p_scope text DEFAULT 'global', p_scope_id integer DEFAULT NULL, p_cycle_start date DEFAULT NULL\)/i, 'engagement summary keeps the 3-arg signature');
  assert.ok(!/DROP FUNCTION[^\n]*get_attendance_engagement_summary/i.test(body), 'additive — no DROP of the summary');
  assert.match(code, /'at_risk_count',\s*\(SELECT count\(\*\) FROM rates WHERE rate IS NOT NULL AND rate < 0\.50\)/i, 'at_risk_count = non-null engagement rate < 0.50');
  // grant ladder preserved (service_role only)
  assert.match(body, /REVOKE ALL ON FUNCTION public\.get_attendance_engagement_summary\(text, integer, date\) FROM PUBLIC, anon, authenticated/i);
  assert.match(body, /GRANT EXECUTE ON FUNCTION public\.get_attendance_engagement_summary\(text, integer, date\) TO service_role/i);
});

test('m3 PR5a: exec_cycle_report same signature + attendance object {engagement, reliability, by_tribe}', () => {
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.exec_cycle_report\(p_cycle_code text DEFAULT 'cycle3-2026'::text\)/i, 'preserves the DEFAULT param (SEDIMENT-238.C)');
  assert.ok(!/DROP FUNCTION[^\n]*exec_cycle_report/i.test(body), 'same signature → no DROP');
  // the final attendance object
  assert.match(code, /v_attendance := jsonb_build_object\(\s*'engagement', public\.get_attendance_engagement_summary\('global'\),\s*'reliability', public\.get_attendance_reliability_summary\('global'\),\s*'by_tribe', v_att_by_tribe\s*\)/i, 'attendance = {engagement(global), reliability(global), by_tribe}');
  // per-tribe row shows BOTH + raw counts + engagement-derived at_risk
  assert.match(code, /'engagement_pct', ROUND\(COALESCE\(\(eng\.j ->> 'avg_rate'\)::numeric, 0\) \* 100, 1\)/i);
  assert.match(code, /'reliability_pct', ROUND\(COALESCE\(\(rel\.j ->> 'avg_rate'\)::numeric, 0\) \* 100, 1\)/i);
  assert.match(code, /'at_risk_count', COALESCE\(\(eng\.j ->> 'at_risk_count'\)::int, 0\)/i, 'at_risk sourced from engagement summary, not inline');
  for (const k of ['present_total', 'absent_total', 'excused_total']) {
    assert.ok(code.includes(`'${k}', COALESCE((rel.j ->> '${k}')::int, 0)`), `per-tribe raw count ${k}`);
  }
  // one summary call per tribe via LATERAL
  assert.match(code, /CROSS JOIN LATERAL \(SELECT public\.get_attendance_engagement_summary\('tribe', t\.id\) AS j\) eng/i);
  assert.match(code, /CROSS JOIN LATERAL \(SELECT public\.get_attendance_reliability_summary\('tribe', t\.id\) AS j\) rel/i);
  assert.match(body, /NOTIFY\s+pgrst/i);
});

test('m3 PR5a forward-defense: get_attendance_summary fully decoupled + no combined_pct weighting', () => {
  assert.ok(!/get_attendance_summary\s*\(/.test(code), 'exec_cycle_report no longer calls get_attendance_summary (D9 decouple)');
  assert.ok(!/combined_pct/i.test(code), 'no combined_pct (0.4/0.6 weighting) reintroduced');
  assert.ok(!/avg_geral_pct|avg_tribe_pct/i.test(code), 'old per-tribe geral/tribe split columns removed');
});

test('m3 PR5a FE: cycle-report.astro renders the attendance object (Participação + Confiabilidade)', () => {
  assert.ok(existsSync(PAGE));
  assert.match(page, /const att = \(r\.attendance && !Array\.isArray\(r\.attendance\)\) \? r\.attendance : \{\}/, 'reads attendance as object');
  assert.match(page, /const byTribe = Array\.isArray\(att\.by_tribe\) \? att\.by_tribe : \[\]/);
  assert.match(page, /att\.engagement/);
  assert.match(page, /att\.reliability/);
  assert.match(page, /a\.engagement_pct/);
  assert.match(page, /a\.reliability_pct/);
  // raw P/A/E counts surfaced on the reliability diagnostic card (D10 — never bare)
  assert.match(page, /relG\.present_total[\s\S]*relG\.absent_total[\s\S]*relG\.excused_total/);
  // per-tribe reliability cell discloses the full P/A/E triple too (review LOW — D10 at every granularity)
  assert.match(page, /a\.present_total[\s\S]*a\.absent_total[\s\S]*a\.excused_total/);
  // engagement headline card surfaces global at_risk (review LOW — self-documents the untribed gap)
  assert.match(page, /engG\.at_risk_count/);
  assert.ok(!/a\.avg_combined_pct/.test(page), 'frontend no longer reads avg_combined_pct');
  assert.ok(!/T\.attColCombinedPct|T\.attColGeneralPct|T\.attColTribePct/.test(page), 'retired combined/geral/tribe column headers gone from render');
});

test('m3 PR5a i18n: new attendance keys present in all 3 dictionaries', () => {
  const keys = [
    'cycleReport.attColEngagement',
    'cycleReport.attColReliability',
    'cycleReport.attEngagementLbl',
    'cycleReport.attReliabilityLbl',
    'cycleReport.attEngagementHint',
  ];
  const retired = ['cycleReport.attColGeneralPct', 'cycleReport.attColTribePct', 'cycleReport.attColCombinedPct'];
  for (const f of DICTS) {
    const d = readFileSync(f, 'utf8');
    for (const k of keys) assert.ok(d.includes(`'${k}'`), `${k} missing in ${f}`);
    for (const k of retired) assert.ok(!d.includes(`'${k}'`), `retired combined-weighting key ${k} still in ${f}`);
  }
});

// ── DB-gated ──────────────────────────────────────────────────────────────────
test('m3 PR5a DB: exec_cycle_report auth gate intact (unauthenticated service-role rejected)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { error } = await sb.rpc('exec_cycle_report');
  assert.ok(error, 'no-auth caller must be rejected (Not authenticated)');
});

test('m3 PR5a DB: engagement summary exposes at_risk_count + cohort 37 + ~76% global', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_attendance_engagement_summary', { p_scope: 'global' });
  assert.ok(!error, error?.message);
  assert.ok(data && Object.prototype.hasOwnProperty.call(data, 'at_risk_count'), 'at_risk_count key present');
  assert.equal(Number(data.cohort_n), 37, 'operational cohort = 37');
  const rate = Number(data.avg_rate);
  assert.ok(rate >= 0.74 && rate <= 0.78, `global engagement ~0.76 (got ${rate})`);
  assert.ok(Number(data.at_risk_count) >= 0, 'at_risk_count numeric');
});
