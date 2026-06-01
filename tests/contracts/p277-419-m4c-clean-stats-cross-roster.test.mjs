/**
 * Contract: p277 / #419 (ADR-0100) metric 4 — PR4-C-clean: converge the REMAINING member-cohort RPCs
 * onto the canonical roster primitive (v_initiative_roster / get_initiative_roster_count, mig 082).
 *
 * Three same-signature CREATE OR REPLACE (mig 086); ONLY the member-cohort sites change:
 *   1) get_tribe_stats(integer)          — tribe_members CTE (path E: members.tribe_id ∧ is_active ∧
 *      current_cycle_active) → v_initiative_roster; member_count → get_initiative_roster_count(resolve_
 *      initiative_id(tribe)). 0 VISIBLE DELTA (roster member-SET == path-E SET for every tribe today;
 *      member_count AND top_contributors byte-identical). Structural hardening (correct-by-construction).
 *   2) get_initiative_stats(uuid)        — NATIVE branch init_members (active engagement, NO role filter)
 *      → roster (role<>'observer'). Visible delta: ONLY the Mesa Redonda congress 7→4 (drops 3
 *      role=observer). Bridged initiatives still delegate to get_tribe_stats (unchanged).
 *   3) exec_cross_initiative_comparison  — the cohort predicate "is_active AND EXISTS(engagements ...
 *      kind<>'observer')" repeated 5× (member_count, members_inactive_30d, total_hours, total_xp,
 *      avg_xp) → roster. kind<>observer is the bug (drops members whose kind='observer' but
 *      role<>'observer'). Visible deltas (verified live, cycle_3): tribe 8 5→6 (+Roberto curator),
 *      LATAM LIM 3→5 (+2 reviewers), Grupo CPMAI 3→4 (+1 reviewer); Mesa 4→4 (same set). tribe-8
 *      total_xp 2535→2815 / avg 507.0→469.2 — now MATCHES the shipped exec_tribe_dashboard (mig 084).
 *
 * The headline invariant this PR establishes: get_initiative_stats(X).member_count ==
 * exec_cross(X).member_count == get_initiative_roster_count(X) for every initiative X — today they
 * FORK on the natives (Mesa 7 vs 4, LATAM 5 vs 3, Grupo 4 vs 3); after mig 086 they all read the roster.
 *
 * Same-sig CREATE OR REPLACE; non-cohort sections byte-identical (Phase-C md5 file≡live verified).
 * The leader-name lookup (en.kind ~ regex) is leader identification, NOT member counting — left untouched.
 * Cross-ref: SPEC_419_M4_M8_CANONICAL_METRICS.md §M4.5/§M4.6; ADR-0100 §2.2; issue #419.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000086_p277_419_m4c_clean_stats_cross_roster.sql');
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
// strip comments (full-line + inline) so header-comment mentions of the OLD predicate don't trip forward-defense
const code = body.replace(/--[^\n]*/g, '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// live initiative ids (stable)
const TRIBE8 = 8;
const MESA = '6e9af7a8-1696-4169-a1a1-c0e160600002'; // congress, native, 7→4
const LATAM = 'a68fcc06-7de8-400b-b5b3-60e368fb46ac'; // congress, native, exec_cross 3→5
const GRUPO = '2f5846f3-5b6b-4ce1-9bc6-e07bdb22cd19'; // study_group, native, exec_cross 3→4

// ── STATIC ────────────────────────────────────────────────────────────────────────
test('M4-C-clean static: three same-signature CREATE OR REPLACE (no DROP), all SECDEF', () => {
  assert.ok(existsSync(MIG), 'migration 086 exists');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_tribe_stats\(p_tribe_id integer\)/i);
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_initiative_stats\(p_initiative_id uuid\)/i);
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.exec_cross_initiative_comparison\(p_kind text DEFAULT 'research_tribe'::text, p_cycle text DEFAULT NULL::text\)/i);
  assert.ok(!/DROP FUNCTION/i.test(body), 'same signatures → no DROP');
  assert.equal((body.match(/SECURITY DEFINER/gi) || []).length, 3, 'all three stay SECURITY DEFINER');
  assert.match(body, /SET search_path TO 'public', 'pg_temp'/i, 'exec_cross search_path preserved');
});

test('M4-C-clean static: get_tribe_stats rides the roster (CTE + primitive)', () => {
  assert.match(code, /tribe_members AS \(\s*SELECT DISTINCT vir\.member_id AS id\s*FROM v_initiative_roster vir\s*WHERE vir\.legacy_tribe_id = p_tribe_id/,
    'tribe_members CTE now selects from v_initiative_roster (was members.tribe_id ∧ is_active ∧ current_cycle_active)');
  assert.match(code, /'member_count', public\.get_initiative_roster_count\(public\.resolve_initiative_id\(p_tribe_id\)\)/,
    'member_count reads the canonical primitive');
});

test('M4-C-clean static: get_initiative_stats native rides the roster; bridge branch preserved', () => {
  assert.match(code, /v_tribe_id := public\.resolve_tribe_id\(p_initiative_id\);/, 'bridge resolver preserved');
  assert.match(code, /IF v_tribe_id IS NOT NULL THEN\s*RETURN public\.get_tribe_stats\(v_tribe_id\);/,
    'bridged initiatives still delegate to get_tribe_stats (unchanged)');
  assert.match(code, /init_members AS \(\s*SELECT DISTINCT vir\.member_id AS id, vir\.name\s*FROM v_initiative_roster vir\s*WHERE vir\.initiative_id = p_initiative_id/,
    'native init_members CTE rides v_initiative_roster (role<>observer)');
  assert.match(code, /'member_count', public\.get_initiative_roster_count\(p_initiative_id\)/,
    'native member_count reads the primitive');
});

test('M4-C-clean static: exec_cross member_count = primitive; >=4 cohort sites ride the roster view', () => {
  assert.match(code, /'member_count', public\.get_initiative_roster_count\(i\.id\)/, 'member_count = get_initiative_roster_count(i.id)');
  const sites = code.match(/SELECT member_id FROM public\.v_initiative_roster\s*WHERE initiative_id = i\.id AND member_id IS NOT NULL/g) || [];
  assert.ok(sites.length >= 4,
    `expected >=4 roster-view cohort subqueries (inactive_30d, total_hours, total_xp, avg_xp); found ${sites.length}`);
});

test('M4-C-clean forward-defense: the kind<>observer MEMBER cohort is gone from exec_cross', () => {
  // the 5 verbose member-cohort blocks "m.is_active AND EXISTS(engagements ... kind <> 'observer')" must be gone
  assert.ok(!/en\.kind != 'observer'/.test(code) && !/en\.kind <> 'observer'/.test(code),
    "no engagement kind<>'observer' member-cohort predicate survives");
  assert.ok(!/EXISTS \(\s*SELECT 1 FROM public\.engagements en\d*\s*WHERE en\d*\.person_id = m\d*\.person_id/.test(code),
    'the EXISTS(engagements WHERE person_id=m.person_id ... kind<>observer) member blocks are gone');
});

test('M4-C-clean static: the leader-name lookup (kind regex) is preserved — separate concern', () => {
  // leader identification != member counting; must NOT be converged onto the roster
  assert.match(code, /en\.kind ~ '\(coordinator\|owner\|leader\|manager\)'/, 'leader lookup kind regex preserved');
});

test('M4-C-clean static: no body truncation — all exec_cross keys + section integrity', () => {
  for (const k of ['member_count','members_inactive_30d','total_cards','cards_completed','articles_submitted',
                   'attendance_rate','total_hours','meetings_count','total_xp','avg_xp','last_meeting_date','days_since_last_meeting']) {
    assert.match(body, new RegExp(`'${k}',`), `exec_cross key '${k}' preserved`);
  }
  assert.match(body, /RETURN v_result;/i, 'exec_cross epilogue preserved');
  // get_tribe_stats / get_initiative_stats keys
  for (const k of ['events_held','impact_hours','cards_backlog','top_contributors']) {
    assert.match(body, new RegExp(`'${k}',`), `stats key '${k}' preserved`);
  }
  assert.match(body, /NOTIFY pgrst, 'reload schema'/, 'PostgREST reload present');
});

// ── BEHAVIOURAL (DB-gated) ──────────────────────────────────────────────────────────
test('M4-C-clean DB: exec_cross auth gate intact (unauthenticated rejected)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { error } = await sb.rpc('exec_cross_initiative_comparison', { p_kind: null, p_cycle: null });
  assert.ok(error, 'no-auth caller must be rejected (manage_platform gate unchanged)');
});

test('M4-C-clean DB: get_tribe_stats(8).member_count == roster primitive == 5 (participants-only, mig 088)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: initId } = await sb.rpc('resolve_initiative_id', { p_tribe_id: TRIBE8 });
  const { data: roster } = await sb.rpc('get_initiative_roster_count', { p_initiative_id: initId });
  const { data: stats } = await sb.rpc('get_tribe_stats', { p_tribe_id: TRIBE8 });
  assert.equal(Number(roster), 5, 'tribe-8 canonical roster = 5 (participants-only, mig 088: observer-kind curator excluded)');
  assert.equal(Number(stats.member_count), Number(roster), 'get_tribe_stats.member_count reads the primitive');
});

test('M4-C-clean DB: fork KILLED — get_initiative_stats(X).member_count == roster for every native initiative', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // before mig 086 these forked (Mesa 7 vs 4, LATAM 5 vs 3 in exec_cross); now all agree on the roster
  for (const id of [MESA, LATAM, GRUPO]) {
    const { data: roster } = await sb.rpc('get_initiative_roster_count', { p_initiative_id: id });
    const { data: stats } = await sb.rpc('get_initiative_stats', { p_initiative_id: id });
    assert.equal(Number(stats.member_count), Number(roster),
      `get_initiative_stats(${id}).member_count (${stats?.member_count}) must equal roster (${roster})`);
  }
});

test('M4-C-clean DB: Mesa Redonda converged 7→4 (drops 3 role=observer); top_contributors follows', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: stats } = await sb.rpc('get_initiative_stats', { p_initiative_id: MESA });
  assert.equal(Number(stats.member_count), 4, 'Mesa Redonda member_count = 4 (was 7 — 3 role=observer dropped)');
  assert.equal(Array.isArray(stats.top_contributors) ? stats.top_contributors.length : -1, 4,
    'top_contributors rides the same cohort (4, not 7)');
});
