/**
 * Contract: #425 — Tribe gamification tab -> per-member coaching cockpit.
 *
 * RPC layer (mig 20260805000128, two same-signature CREATE OR REPLACE):
 *   get_tribe_gamification(integer) + get_initiative_gamification(uuid)
 *   - trail_completion: was hardcoded 'trail_completion', 0; now a REAL fraction 0..1
 *     (AVG over the roster cohort of completed trail courses / total is_trail courses).
 *     Live-verified 2026-06-07: tribe-8 0 -> 0.27.
 *   - trail_progress (per member): recanonised to COMPLETED trail COURSES from
 *     course_progress (SSOT, aligns with get_public_trail_ranking), not category='trail' points.
 *   - NEW per-member coaching primitives wired from canonical SSOT RPCs:
 *       attendance_rate -> get_attendance_rate ; current/longest streak + active_cycles
 *       -> get_member_gamification_stats (guarded by EXCEPTION for non-active viewers);
 *       last_activity ; trail_courses[] (per-course completed|in_progress|missing).
 *
 * Frontend (TribeGamificationTab.tsx, shared by tribe + initiative surfaces):
 *   - Member.id typed string (uuid) — was number (latent type lie).
 *   - per-member drill-down panel + 23 new comp.gamification.* i18n keys (3-dict parity).
 *
 * Cross-ref: docs/audit/METRIC_DISPARITY_AUDIT_2026-05-28.md (GI-1); ADR-0100; issue #425.
 * Upstream deps shipped + closed: #419 (canonical primitives), #420 (attendance present-detection),
 * #424 (champions canonical decision). #425 = the cockpit consumption layer.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000128_p278_425_gamification_coaching_cockpit.sql');
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
// strip comments so header-comment mentions of the OLD hardcoded value don't trip forward-defense
const code = body.replace(/--[^\n]*/g, '');

const TSX = resolve(ROOT, 'src/components/tribes/TribeGamificationTab.tsx');
const tsx = existsSync(TSX) ? readFileSync(TSX, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const TRIBE8 = 8;
const MESA = '6e9af7a8-1696-4169-a1a1-c0e160600002'; // native initiative (no tribe), exercises standalone path

const NEW_I18N_KEYS = [
  'streakCol', 'attendanceRateCol', 'expand', 'collapse', 'coachingTitle', 'coachingSignals',
  'attendanceRateLabel', 'currentStreak', 'longestStreak', 'activeCycles', 'cyclesUnit',
  'lastActivity', 'noActivity', 'trailBreakdown', 'statusCompleted', 'statusInProgress',
  'statusMissing', 'recognition', 'credlyBadges', 'cpmaiYes', 'cpmaiNo', 'noChampionsYet',
  'championsHint',
];

// ── STATIC: migration shape ───────────────────────────────────────────────────────
test('425 static: two same-signature CREATE OR REPLACE (no DROP), both SECDEF', () => {
  assert.ok(existsSync(MIG), 'migration 128 exists');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_tribe_gamification\(p_tribe_id integer\)/i);
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_initiative_gamification\(p_initiative_id uuid\)/i);
  assert.ok(!/DROP FUNCTION/i.test(body), 'same signatures → no DROP (preserves ACL)');
  assert.equal((code.match(/SECURITY DEFINER/gi) || []).length, 2, 'both stay SECURITY DEFINER');
  assert.match(body, /SET search_path TO 'public', 'pg_temp'/i, 'tribe search_path preserved');
});

test('425 static: trail_completion is NO LONGER hardcoded 0 (the GI-1 lie is dead)', () => {
  // the misleading constant must be gone from BOTH functions
  assert.ok(!/'trail_completion',\s*0\b/.test(code),
    "hardcoded \"'trail_completion', 0\" must not appear anywhere");
  // real computation present in both paths
  assert.match(code, /'trail_completion',\s*COALESCE\(v_trail_completion/, 'tribe path computes trail_completion');
  assert.match(code, /'trail_completion',\s*COALESCE\(\(SELECT pct FROM v_trail\)/, 'initiative path computes trail_completion');
  // computed as AVG of completed/total over the cohort (fraction 0..1)
  assert.match(code, /ROUND\(AVG\(member_pct\),\s*2\)/, 'trail completion = ROUND(AVG(member_pct),2) fraction');
});

test('425 static: trail_progress recanonised to completed trail COURSES (course_progress SSOT)', () => {
  // was: count(*) gamification_points category='trail'. now: completed is_trail course_progress.
  assert.ok(!/category = 'trail'/.test(code), "old gamification_points category='trail' trail_progress gone");
  const sites = code.match(/FROM course_progress cp\s*\n?\s*WHERE cp\.member_id = \w+\.\w*id?\b/gi) || [];
  assert.match(code, /cp\.status = 'completed'/, 'trail completion keys on status=completed');
  assert.match(code, /courses WHERE is_trail = true/, 'denominator is dynamic is_trail count');
});

test('425 static: new per-member coaching keys present (both functions)', () => {
  for (const k of ['attendance_rate', 'current_streak', 'longest_streak', 'active_cycles', 'last_activity', 'trail_courses']) {
    const n = (code.match(new RegExp(`'${k}',`, 'g')) || []).length;
    assert.ok(n >= 2, `member key '${k}' present in both functions (found ${n})`);
  }
});

test('425 static: coaching signals reuse canonical SSOT RPCs, not re-derived', () => {
  assert.match(code, /public\.get_attendance_rate\(/, 'attendance_rate via canonical get_attendance_rate');
  assert.match(code, /public\.get_member_gamification_stats\(/, 'streaks via canonical get_member_gamification_stats');
  // the streak call is guarded so a non-active viewer still gets the table, but the
  // catch is NARROW (council fold): only the documented callee RAISEs are swallowed,
  // schema-drift / programming errors propagate.
  assert.match(code, /BEGIN[\s\S]*get_member_gamification_stats[\s\S]*EXCEPTION WHEN insufficient_privilege OR invalid_parameter_value THEN[\s\S]*v_stats := '\{\}'::jsonb;/,
    'streak stats call wrapped in a NARROW EXCEPTION guard (insufficient_privilege OR invalid_parameter_value)');
  assert.ok(!/EXCEPTION WHEN OTHERS/.test(code), 'must not use the over-broad WHEN OTHERS catch');
});

test('425 static: trail_courses carries per-course status completed|in_progress|missing', () => {
  assert.match(code, /'status',\s*COALESCE\(cp\.status,\s*'missing'\)/, 'missing = no course_progress row');
  assert.match(code, /LEFT JOIN course_progress cp ON cp\.course_id = c\.id AND cp\.member_id/, 'per-course LEFT JOIN');
});

test('425 forward-defense: the v_trail/v_trend typo is not present (monthly_trend uses v_trend)', () => {
  assert.ok(!/trend_json FROM v_trail/.test(code), 'monthly_trend must read v_trend, not v_trail');
  assert.match(code, /'monthly_trend',\s*\(SELECT trend_json FROM v_trend\)/, 'initiative monthly_trend reads v_trend');
});

test('425 no-regression: existing summary keys + per-member pillars + envelope preserved', () => {
  for (const k of ['total_xp', 'avg_xp', 'tribe_rank', 'cert_coverage', 'trail_completion']) {
    assert.match(body, new RegExp(`'${k}',`), `summary key '${k}' preserved`);
  }
  for (const k of ['attendance_points', 'cert_points', 'badge_points', 'learning_points',
    'producao_points', 'curadoria_points', 'champions_points', 'credly_badge_count', 'has_cpmai', 'trail_progress']) {
    assert.match(body, new RegExp(`'${k}',`), `per-member pillar '${k}' preserved`);
  }
  assert.match(body, /RETURN jsonb_build_object\('summary', v_summary, 'members', v_members, 'tribe_ranking', v_ranking, 'monthly_trend', v_trend\);/,
    'tribe envelope preserved');
  assert.match(body, /RETURN v_result;/, 'initiative epilogue preserved');
});

// ── STATIC: frontend ──────────────────────────────────────────────────────────────
test('425 static: TribeGamificationTab Member.id typed string (uuid), not number', () => {
  assert.ok(existsSync(TSX), 'TribeGamificationTab.tsx exists');
  assert.match(tsx, /interface Member \{\s*\n\s*id: string;/, 'Member.id is string (was number — the GI-1 type lie)');
  assert.match(tsx, /interface TrailCourse/, 'TrailCourse interface added for the drill-down');
  assert.match(tsx, /MemberDrillDown/, 'per-member drill-down component present');
  assert.match(tsx, /aria-expanded=\{isOpen\}/, 'expand control is accessible (aria-expanded)');
});

test('425 static: i18n 3-dict parity for the 23 new comp.gamification.* keys', () => {
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const txt = readFileSync(resolve(ROOT, `src/i18n/${dict}.ts`), 'utf8');
    for (const k of NEW_I18N_KEYS) {
      assert.match(txt, new RegExp(`'comp\\.gamification\\.${k}':`), `${dict} has comp.gamification.${k}`);
    }
  }
});

// ── BEHAVIOURAL (DB-gated) ──────────────────────────────────────────────────────────
test('425 DB: auth gate intact — no-auth caller gets in-band Unauthorized (both fns)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: dt, error: et } = await sb.rpc('get_tribe_gamification', { p_tribe_id: TRIBE8 });
  assert.ifError(et);
  assert.equal(dt?.error, 'Unauthorized', 'get_tribe_gamification gate holds for no-auth caller');
  const { data: di, error: ei } = await sb.rpc('get_initiative_gamification', { p_initiative_id: MESA });
  assert.ifError(ei);
  assert.equal(di?.error, 'Unauthorized', 'get_initiative_gamification gate holds for no-auth caller');
});

test('425 DB: canonical primitives the cockpit depends on exist & are callable', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // trail denominator is non-empty (dynamic is_trail count)
  const { data: calc, error: ec } = await sb.rpc('calc_trail_completion_pct');
  assert.ifError(ec);
  assert.ok(calc !== null && Number(calc) >= 0, 'calc_trail_completion_pct returns a number');
  // get_attendance_rate is callable (returns numeric or null for a random uuid w/o events)
  const { error: ea } = await sb.rpc('get_attendance_rate', {
    p_member_id: '00000000-0000-0000-0000-000000000000', p_cycle_start: null,
  });
  assert.ifError(ea, 'get_attendance_rate callable');
});

test('425 DB: at least one is_trail course exists (denominator > 0)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.from('courses').select('id', { count: 'exact', head: false }).eq('is_trail', true);
  assert.ifError(error);
  assert.ok((data?.length || 0) >= 1, 'at least one is_trail course (trail_completion denominator)');
});
