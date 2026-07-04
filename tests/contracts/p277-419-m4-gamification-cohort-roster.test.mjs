/**
 * Contract: p277 / #419 (ADR-0100) metric 4 — M4 FINAL piece: converge the gamification member cohorts
 * onto the canonical roster primitive (v_initiative_roster / get_initiative_roster_count, mig 082+088).
 *
 * Two same-signature CREATE OR REPLACE (mig 089); ONLY the member-cohort sites change:
 *   1) get_tribe_gamification(integer) — 6 cohort sites: members.tribe_id ∧ is_active →
 *      v_initiative_roster (participants-only). member_count via get_initiative_roster_count(resolve_
 *      initiative_id(tribe)); the members list, cert_coverage denom, monthly_trend, AND the cross-tribe
 *      XP-ranking sums (tribe_rank + tribe_ranking, previously summed over members.tribe_id ∧ is_active)
 *      now ride the roster. Visible delta: ONLY tribe-8 (member_count 6→5, total_xp 2815→2535, avg_xp
 *      469→507, cert_coverage 0.17→0.20, tribe_rank 2→2 — order unchanged; tribe_ranking[8].total_xp
 *      2815→2535, now consistent with summary.total_xp). tribes 1/2/4/5/6/7 unchanged.
 *   2) get_initiative_gamification(uuid) NATIVE branch — init_members (engagements status='active', NO
 *      role/kind filter) → roster (participants-only). Visible deltas (live, cycle_3): Mesa Redonda 7→4
 *      (4880→2375), LATAM 5→3 (2660→1395), Grupo de Estudos 4→3 (1845→1845, dropped observer had 0 XP);
 *      5 other native unchanged. Tribe initiatives still delegate → inherit the get_tribe_gamification fix.
 *
 * Headline invariant: get_initiative_gamification(X).summary.member-count == get_tribe_stats / exec_cross /
 * the roster for every initiative X (the 3 native forks Mesa/LATAM/Grupo are killed here — they were the
 * last surfaces still disagreeing with the roster post-mig-088).
 *
 * SCOPE = member-cohort axis only. The XP-RANKING expressions (ORDER BY total_points DESC on the members
 * list, RANK() OVER (ORDER BY txp DESC) on tribe_rank) are LEFT UNTOUCHED — cycle-mode ordering +
 * member_id tiebreak is metric 5 / PR5-E, kept separable per the M4-C discipline (change WHO is in the
 * cohort, not HOW XP ranks). Same-sig CREATE OR REPLACE; non-cohort sections preserved (Phase-C md5
 * file≡live verified: get_tribe_gamification 568ef502…, get_initiative_gamification d1175156…).
 * Cross-ref: SPEC_419_M4_M8_CANONICAL_METRICS.md §M4.5 (row 148) / §M4.6 (PR4-B/PR4-C); ADR-0100 §2.2; issue #419.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000089_p277_419_m4_gamification_cohort_roster.sql');
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
// strip comments so header-comment mentions of the OLD predicate don't trip forward-defense
const code = body.replace(/--[^\n]*/g, '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// live initiative ids (stable)
const TRIBE8 = 8;
const MESA  = '6e9af7a8-1696-4169-a1a1-c0e160600002'; // congress, native, 7→4
const LATAM = 'a68fcc06-7de8-400b-b5b3-60e368fb46ac'; // congress, native, 5→3
const GRUPO = '2f5846f3-5b6b-4ce1-9bc6-e07bdb22cd19'; // study_group, native, 4→3

// ── STATIC ────────────────────────────────────────────────────────────────────────
test('M4-gam static: two same-signature CREATE OR REPLACE (no DROP), both SECDEF', () => {
  assert.ok(existsSync(MIG), 'migration 089 exists');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_tribe_gamification\(p_tribe_id integer\)/i);
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_initiative_gamification\(p_initiative_id uuid\)/i);
  assert.ok(!/DROP FUNCTION/i.test(body), 'same signatures → no DROP');
  assert.equal((body.match(/SECURITY DEFINER/gi) || []).length, 2, 'both stay SECURITY DEFINER');
  assert.match(body, /SET search_path TO 'public', 'pg_temp'/i, 'get_tribe_gamification search_path preserved');
  assert.match(body, /NOTIFY pgrst, 'reload schema'/, 'PostgREST reload present');
});

test('M4-gam static: get_tribe_gamification member_count = canonical primitive', () => {
  assert.match(code, /v_initiative_id := public\.resolve_initiative_id\(p_tribe_id\);/,
    'resolves tribe → initiative via the canonical resolver');
  assert.match(code, /v_member_count := public\.get_initiative_roster_count\(v_initiative_id\);/,
    'member_count reads the canonical roster-count primitive (was count(*) members.tribe_id ∧ is_active)');
});

test('M4-gam static: get_tribe_gamification subject-cohort sites ride v_initiative_roster (>=3 IN-subqueries)', () => {
  // v_members list + cert_coverage denom + monthly_trend cohort
  const sites = code.match(/SELECT member_id FROM v_initiative_roster WHERE initiative_id = v_initiative_id/g) || [];
  assert.ok(sites.length >= 3,
    `expected >=3 roster cohort subqueries (members list, cert_coverage, monthly_trend); found ${sites.length}`);
});

test('M4-gam static: get_tribe_gamification cross-tribe ranking rides the roster (tribe_rank + tribe_ranking)', () => {
  const xt = code.match(/SELECT DISTINCT legacy_tribe_id, member_id FROM v_initiative_roster/g) || [];
  assert.ok(xt.length >= 2,
    `expected >=2 roster-based cross-tribe sums (tribe_rank tribe_totals + tribe_ranking); found ${xt.length}`);
  assert.match(code, /gp\.member_id = m2\.member_id/, 'tribe_totals joins gamification_points via roster member_id');
  assert.match(code, /gp\.member_id = m4\.member_id/, 'tribe_ranking joins gamification_points via roster member_id');
});

test('M4-gam static: get_initiative_gamification native init_members rides the roster; bridge preserved', () => {
  assert.match(code, /v_tribe_id := public\.resolve_tribe_id\(p_initiative_id\);/, 'bridge resolver preserved');
  assert.match(code, /IF v_tribe_id IS NOT NULL THEN\s*RETURN public\.get_tribe_gamification\(v_tribe_id\);/,
    'tribe initiatives still delegate to get_tribe_gamification (inherit the fix)');
  assert.match(code, /init_members AS \(\s*SELECT DISTINCT m\.id, m\.name, m\.cpmai_certified, m\.credly_badges\s*FROM v_initiative_roster vir\s*JOIN members m ON m\.id = vir\.member_id\s*WHERE vir\.initiative_id = p_initiative_id/,
    'native init_members rides v_initiative_roster (participants-only)');
});

test('M4-gam forward-defense: the members.tribe_id ∧ is_active MEMBER cohort is gone (tribe filter kept)', () => {
  // every member-cohort reference to members.tribe_id must be gone (the OLD subject + cross-tribe joins)
  assert.ok(!/m\.tribe_id = p_tribe_id/.test(code), 'old subject members.tribe_id cohort gone');
  assert.ok(!/m2\.tribe_id = t\.id/.test(code), 'old tribe_totals member join (m2.tribe_id) gone');
  assert.ok(!/m4\.tribe_id = t\.id/.test(code), 'old tribe_ranking member join (m4.tribe_id) gone');
  assert.ok(!/m5\.tribe_id = p_tribe_id/.test(code), 'old monthly_trend member cohort (m5.tribe_id) gone');
  // the TRIBE-level active filter is a different axis and MUST remain (cross-tribe iterates active tribes)
  assert.match(code, /t\.is_active = true/, 'tribe-level is_active filter preserved (not a member cohort)');
});

test('M4-gam forward-defense: native init_members no longer reads raw engagements status=active', () => {
  assert.ok(!/JOIN members m ON m\.person_id = eng\.person_id/.test(code),
    'old init_members person-join over engagements is gone');
  assert.ok(!/eng\.initiative_id = p_initiative_id AND eng\.status = 'active'/.test(code),
    'old engagements status=active (no role/kind filter) init_members predicate gone');
});

test('M4-gam static: XP ranking left untouched (metric 5 / PR5-E separable)', () => {
  assert.match(code, /ORDER BY COALESCE\(p\.total_points, 0\) DESC/, 'tribe members list keeps lifetime-total ordering');
  assert.match(code, /RANK\(\) OVER \(ORDER BY txp DESC\)/, 'tribe_rank keeps RANK() OVER (ORDER BY txp DESC)');
  assert.match(code, /ORDER BY md\.total_points DESC/, 'native members list keeps lifetime-total ordering');
});

test('M4-gam static: no body truncation — summary keys + per-member pillars + envelope preserved', () => {
  for (const k of ['total_xp','avg_xp','tribe_rank','cert_coverage','trail_completion']) {
    assert.match(body, new RegExp(`'${k}',`), `summary key '${k}' preserved`);
  }
  for (const k of ['attendance_points','cert_points','badge_points','learning_points','producao_points',
                   'curadoria_points','champions_points','credly_badge_count','has_cpmai','trail_progress']) {
    assert.match(body, new RegExp(`'${k}',`), `per-member key '${k}' preserved`);
  }
  assert.match(body, /'tribe_ranking'/, 'tribe_ranking envelope key preserved');
  assert.match(body, /'monthly_trend'/, 'monthly_trend envelope key preserved');
  assert.match(body, /RETURN jsonb_build_object\('summary', v_summary, 'members', v_members, 'tribe_ranking', v_ranking, 'monthly_trend', v_trend\);/,
    'get_tribe_gamification envelope preserved');
  assert.match(body, /RETURN v_result;/, 'get_initiative_gamification epilogue preserved');
});

// ── BEHAVIOURAL (DB-gated) ──────────────────────────────────────────────────────────
test('M4-gam DB: auth gate intact — no-auth caller gets in-band Unauthorized (both fns)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: dt, error: et } = await sb.rpc('get_tribe_gamification', { p_tribe_id: TRIBE8 });
  assert.ifError(et);
  assert.equal(dt?.error, 'Unauthorized', 'get_tribe_gamification gate returns in-band Unauthorized for no-auth caller');
  const { data: di, error: ei } = await sb.rpc('get_initiative_gamification', { p_initiative_id: MESA });
  assert.ifError(ei);
  assert.equal(di?.error, 'Unauthorized', 'get_initiative_gamification gate returns in-band Unauthorized for no-auth caller');
});

test('M4-gam DB: tribe-8 cohort == canonical roster == 5 (participants-only); the count get_tribe_gamification now returns', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: initId } = await sb.rpc('resolve_initiative_id', { p_tribe_id: TRIBE8 });
  const { data: roster } = await sb.rpc('get_initiative_roster_count', { p_initiative_id: initId });
  assert.equal(Number(roster), 5, 'tribe-8 canonical roster = 5 (mig 088: observer-kind curator Roberto excluded)');
});

test('M4-gam DB: native forks KILLED — Mesa=4, LATAM=3, Grupo=3 (== get_initiative_stats == roster)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const expect = { [MESA]: 4, [LATAM]: 3, [GRUPO]: 3 };
  for (const [id, n] of Object.entries(expect)) {
    const { data: roster } = await sb.rpc('get_initiative_roster_count', { p_initiative_id: id });
    const { data: stats } = await sb.rpc('get_initiative_stats', { p_initiative_id: id });
    assert.equal(Number(roster), n, `roster(${id}) == ${n}`);
    assert.equal(Number(stats.member_count), n,
      `get_initiative_stats(${id}).member_count == ${n} — get_initiative_gamification now agrees (shares the roster)`);
  }
});

test('M4-gam DB: only tribe-8 changed — other tribes stable (drift-tolerant baselines)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // tribe-6 6→5: offboarding legítimo de membro em 2026-06-11 (alumni, ROI & Portfólio)
  // tribe-2 5→4: offboarding legítimo de Ricardo França em 2026-07-04 (alumni, external_priority)
  const expect = { 1: 4, 2: 4, 6: 5 };
  for (const [tid, n] of Object.entries(expect)) {
    const { data: initId } = await sb.rpc('resolve_initiative_id', { p_tribe_id: Number(tid) });
    const { data: roster } = await sb.rpc('get_initiative_roster_count', { p_initiative_id: initId });
    assert.equal(Number(roster), n, `tribe ${tid} roster == ${n} (unchanged)`);
  }
});
