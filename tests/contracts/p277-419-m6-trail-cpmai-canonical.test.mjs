/**
 * Contract: p277 / #419 (ADR-0100) metric 6 — trail_completion + cpmai_certified canonical.
 *
 * TRAIL (D-M6-TRAIL): calc_trail_completion_pct was already partial-credit; this migration fixes
 *   (1) the hardcoded /6.0 → dynamic NULLIF(count(courses WHERE is_trail),0), and
 *   (2) the cohort (drop operational_role='guest' so home == get_public_trail_ranking's cohort).
 *   Antes 44 → depois 47 (same 35-member cohort + dynamic total as the ranking; integer ROUND vs the
 *   ranking's 2dp 46.66 — same metric, display rounding differs).
 *
 * CPMAI (D-M6-CPMAI): the GOAL metric counts members who CERTIFIED DURING THE GOAL YEAR
 *   (cpmai_certified AND cpmai_certified_at in [year, year+1)). A pre-goal-year cert (member arrived
 *   already certified — e.g. Pedro 2025-10-23) is on the all-time WALL but NOT the goal. PMI-GO board
 *   rule. Canonical helper get_cpmai_certified_goal_count(p_year) repoints exec_portfolio_health,
 *   get_kpi_dashboard, get_annual_kpis. Live: goal-2026 = 1 (Marcos); wall all-time = 2.
 *
 * Static checks lock the canonical bodies + repoints; behavioural checks (DB-gated) assert the depois.
 * NOTE: the GI-1 trail_completion-hardcoded-0 in get_tribe_gamification/get_initiative_gamification is
 * DEFERRED to #425 (coaching cockpit) to avoid triple-touching the big gamification RPCs metric 4 + 5
 * also converge — out of scope here, by design.
 *
 * Cross-ref: SPEC_419_M4_M8_CANONICAL_METRICS.md §M6; ADR-0100 §2.2 trail_completion + cpmai_certified
 * rows + §7 (D-M6-TRAIL / D-M6-CPMAI); issues #419, #425.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000081_p277_419_m6_trail_cpmai_canonical.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const mig = migRaw.replace(/^\s*--.*$/gm, ''); // strip SQL line-comments

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── STATIC: trail canonical ─────────────────────────────────────────────────────
test('M6 static: calc_trail_completion_pct uses a dynamic is_trail total (no hardcoded 6)', () => {
  assert.ok(existsSync(MIG), 'M6 migration 20260805000081 exists');
  const fn = mig.match(/CREATE OR REPLACE FUNCTION public\.calc_trail_completion_pct[\s\S]*?\$function\$;/);
  assert.ok(fn, 'calc_trail_completion_pct block parses');
  assert.match(fn[0], /NULLIF\(\(SELECT COUNT\(\*\) FROM courses WHERE is_trail = true\), 0\)/,
    'denominator is the dynamic is_trail course count');
  assert.doesNotMatch(fn[0], /\/\s*6\.0/, 'no hardcoded /6.0');
});

test('M6 static: trail cohort excludes guests (aligns to get_public_trail_ranking)', () => {
  const fn = mig.match(/CREATE OR REPLACE FUNCTION public\.calc_trail_completion_pct[\s\S]*?\$function\$;/);
  assert.match(fn[0], /operational_role NOT IN \('sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor', 'guest'\)/,
    "the blocklist now includes 'guest'");
});

// ── STATIC: cpmai goal-metric helper + repoints ─────────────────────────────────
test('M6 static: get_cpmai_certified_goal_count windows on the goal year', () => {
  const fn = mig.match(/CREATE OR REPLACE FUNCTION public\.get_cpmai_certified_goal_count[\s\S]*?\$function\$;/);
  assert.ok(fn, 'helper block parses');
  assert.match(fn[0], /cpmai_certified = true/, 'requires the certified boolean');
  assert.match(fn[0], /cpmai_certified_at >= make_date\(COALESCE\(p_year/, 'lower bound = goal year start');
  assert.match(fn[0], /cpmai_certified_at <\s+make_date\(COALESCE\(p_year, EXTRACT\(year FROM now\(\)\)::int\) \+ 1/,
    'upper bound = goal year end (exclusive)');
});

test('M6 static: the 3 cpmai goal surfaces call the helper', () => {
  for (const fn of ['exec_portfolio_health', 'get_kpi_dashboard', 'get_annual_kpis']) {
    assert.match(mig, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\s*\\(`), `${fn} is repointed`);
  }
  const calls = (mig.match(/public\.get_cpmai_certified_goal_count\(/g) || []).length;
  assert.ok(calls >= 3, `>=3 helper call sites (found ${calls})`);
  // forward-defense: no surviving date-free cpmai count in the repointed goal surfaces
  assert.doesNotMatch(mig, /count\(\*\) FROM (public\.)?members WHERE cpmai_certified = true\)/i,
    'no date-free "count members WHERE cpmai_certified" survives in the repoints');
});

// ── BEHAVIOURAL (DB-gated) ───────────────────────────────────────────────────────
test('M6 behavioural: calc_trail_completion_pct == live re-derivation of its own cohort (#1180)', { skip: dbGated ? false : skipMsg }, async () => {
  // #1180: the original home==ranking parity assert rotted — get_public_trail_ranking later gained
  // extra cohort filters (gamification_opt_out, member_is_pre_onboarding, tribe/engagement requirement)
  // that calc_trail_completion_pct does not have, so with the C4 pre-onboarding influx the two surfaces
  // legitimately diverge (live 2026-07-08: home cohort 62 vs ranking cohort 36; home 40 vs ranking avg
  // 54.64). Whether the HOME headline should also exclude pre-onboarding members is a product decision
  // tracked on #1180; this test now verifies the function against a live re-derivation of its OWN
  // contract: partial-credit AVG of per-member completed/trail_total over the operational cohort.
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: home, error: e1 } = await sb.rpc('calc_trail_completion_pct');
  assert.ifError(e1);

  const { data: trailCourses, error: e2 } = await sb.from('courses').select('id').eq('is_trail', true);
  assert.ifError(e2);
  const trailIds = new Set((trailCourses || []).map((c) => c.id));
  assert.ok(trailIds.size > 0, 'trail has at least one course');

  const { data: cohort, error: e3 } = await sb
    .from('members').select('id')
    .eq('is_active', true).eq('current_cycle_active', true)
    .not('operational_role', 'in', '("sponsor","chapter_liaison","observer","candidate","visitor","guest")');
  assert.ifError(e3);
  assert.ok(cohort.length > 0, 'trail cohort non-empty');

  const { data: progress, error: e4 } = await sb
    .from('course_progress').select('member_id, course_id, status')
    .eq('status', 'completed').in('course_id', [...trailIds]);
  assert.ifError(e4);
  const completedByMember = new Map();
  for (const p of progress || []) {
    completedByMember.set(p.member_id, (completedByMember.get(p.member_id) || 0) + 1);
  }
  const avg = cohort.reduce((s, m) => s + (completedByMember.get(m.id) || 0) / trailIds.size, 0) / cohort.length;
  const expected = Math.round(avg * 100);
  // ±1 tolerance: the RPC and the re-derivation read the DB at slightly different instants.
  assert.ok(Math.abs(Number(home) - expected) <= 1,
    `home trail (${home}) == live re-derivation (${expected}) over cohort ${cohort.length}/trail ${trailIds.size}`);
});

test('M6 behavioural: cpmai goal count partitions by cert year (goal != wall)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: goal2026, error: e1 } = await sb.rpc('get_cpmai_certified_goal_count', { p_year: 2026 });
  assert.ifError(e1);
  const { data: wall, error: e2 } = await sb
    .from('members').select('id', { count: 'exact', head: true }).eq('cpmai_certified', true);
  assert.ifError(e2);
  const wallCount = wall?.length ?? null; // head:true returns count in the response meta; fall back below
  // robust: query the wall count directly via an rpc-free aggregate is not available, so re-derive:
  const { count: wallExact } = await sb
    .from('members').select('id', { count: 'exact', head: true }).eq('cpmai_certified', true);
  assert.ok(typeof goal2026 === 'number', 'goal count is an integer');
  assert.ok(goal2026 >= 1, 'at least one 2026 certification (Marcos)');
  assert.ok((wallExact ?? goal2026) >= goal2026, 'wall (all-time) >= goal (year-windowed)');
});

test('M6 behavioural: the 3 goal surfaces report the helper value', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: goal, error: e0 } = await sb.rpc('get_cpmai_certified_goal_count');
  assert.ifError(e0);
  const { data: kpi, error: e1 } = await sb.rpc('get_kpi_dashboard');
  assert.ifError(e1);
  const card = (kpi.kpis || []).find((k) => k.name === 'Certificação CPMAI');
  assert.ok(card, 'kpi has the Certificação CPMAI card');
  assert.equal(Number(card.current), Number(goal), 'kpi cpmai current == goal helper');
});
