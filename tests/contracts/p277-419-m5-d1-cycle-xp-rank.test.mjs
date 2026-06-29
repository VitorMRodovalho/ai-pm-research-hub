/**
 * Contract: #419 (ADR-0100) metric 5 / D1 — get_member_cycle_xp rank is cycle-scoped.
 *
 * BUG (live-grounded 2026-06-04, cycle_3 start 2026-03-01): the RPC DISPLAYED each member's
 * cycle XP (points since cycle_start) but computed rank_position by LIFETIME XP
 * (ROW_NUMBER() OVER (ORDER BY SUM(points) DESC), no cycle filter, no tiebreak). The #1 cycle
 * earner (Hayala Curto, 435 cycle XP) surfaced at rank #12 (her all-time total); 31 of 60
 * members shared a cycle-XP value so ties ranked non-deterministically.
 *
 * FIX (migration 20260805000101, body-only CREATE OR REPLACE, same signature):
 *   1. rank by cycle XP: COALESCE(SUM(points) FILTER (WHERE created_at >= cycle_start_date), 0)
 *   2. deterministic member_id tiebreak in the ROW_NUMBER ORDER BY
 *   3. removed the dead hardcoded January-1 literal fallback
 * The self-or-view_pii gate, SECURITY DEFINER, search_path, and every displayed field
 * (lifetime_points, cycle_*, cycle_code/label, total_ranked) are unchanged.
 *
 * Scope guard: rank_position is consumed ONLY by the MCP/chat tools (get_my_xp_and_ranking,
 * get_member_cycle_xp, get_in_dashboard). No web surface renders it. get_public_leaderboard
 * stays lifetime-by-design (out of scope, PM-confirmed).
 *
 * Static checks lock the canonical body; the DB-gated check proves file == live (deployed,
 * not drifted) via the Phase-C body hash. The RPC itself can't be invoked here — its auth.uid()
 * gate rejects a service-role client — so the live-body hash is the strongest behavioural proof.
 *
 * Cross-ref: SPEC_419_M4_M8_CANONICAL_METRICS.md §M5; PM_DECISION_BRIEF_2026-06-04.md D1; issue #419.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { parseMigration, loadLatestCaptures } from '../helpers/rpc-body-drift-parser.mjs';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000101_m5_419_d1_get_member_cycle_xp_rank_cycle_scoped.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

function fnBlock() {
  const m = migRaw.match(/CREATE OR REPLACE FUNCTION public\.get_member_cycle_xp[\s\S]*?\$function\$;/);
  assert.ok(m, 'get_member_cycle_xp CREATE OR REPLACE block parses');
  return m[0];
}

// ── STATIC: same-signature body-only replacement ───────────────────────────────
test('M5 static: migration file exists', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000101 exists on disk');
});

test('M5 static: get_member_cycle_xp is CREATE OR REPLACE same-signature (no DROP)', () => {
  const fn = fnBlock();
  assert.match(fn, /CREATE OR REPLACE FUNCTION public\.get_member_cycle_xp\(p_member_id uuid\)/i,
    'same signature get_member_cycle_xp(p_member_id uuid)');
  assert.doesNotMatch(migRaw, /DROP\s+FUNCTION/i, 'must not DROP the function (no consumer break)');
});

test('M5 static: SECURITY DEFINER + search_path preserved', () => {
  const fn = fnBlock();
  assert.match(fn, /SECURITY DEFINER/i, 'SECURITY DEFINER preserved');
  assert.match(fn, /SET search_path TO 'public', 'pg_temp'/i, 'search_path pin preserved');
});

test('M5 static: self-or-view_pii gate preserved (LGPD, p276)', () => {
  const fn = fnBlock();
  assert.match(fn, /p_member_id\s*<>\s*v_caller_id/i, 'compares requested member id against caller');
  assert.match(fn, /can_by_member\(\s*v_caller_id\s*,\s*'view_pii'\s*\)/i, 'cross-member read requires view_pii');
});

test('M5 static: rank is ordered by THIS-cycle XP (filtered SUM), not lifetime', () => {
  const fn = fnBlock();
  assert.match(
    fn,
    /ROW_NUMBER\(\) OVER \(\s*ORDER BY COALESCE\(SUM\(points\) FILTER \(WHERE created_at >= cycle_start_date\), 0\) DESC/i,
    'ROW_NUMBER orders by the cycle-filtered points sum'
  );
});

test('M5 static: deterministic member_id tiebreak in the rank ORDER BY', () => {
  const fn = fnBlock();
  assert.match(fn, /DESC,\s*member_id\s*\)\s*as pos/i, 'member_id is the tiebreak after the DESC sort');
});

test('M5 static: the hardcoded January-1 literal fallback is gone (forward-defense)', () => {
  const fn = fnBlock();
  assert.doesNotMatch(fn, /2026-01-01/, "no '2026-01-01' literal survives anywhere in the function");
  assert.doesNotMatch(fn, /cycle_start_date\s*:=\s*'/i, 'no literal assignment to cycle_start_date');
});

test('M5 static: displayed fields + denominator unchanged (rank-only fix)', () => {
  const fn = fnBlock();
  // total_ranked stays the full cohort of members with any XP (matches the 60-member denominator)
  assert.match(fn, /SELECT COUNT\(DISTINCT member_id\) FROM public\.gamification_points/i,
    'total_ranked denominator preserved');
  // the displayed cycle_points field is untouched (was already cycle-correct)
  assert.match(fn, /'cycle_points', coalesce\(sum\(points\) filter \(where created_at >= cycle_start_date\), 0\)::int/i,
    'cycle_points display field unchanged');
  assert.match(fn, /'rank_position', coalesce\(v_rank, 0\)/i, 'rank_position still emitted');
});

test('M5 static: migration issues NOTIFY pgrst', () => {
  assert.match(migRaw, /NOTIFY pgrst, 'reload schema'/i, 'PostgREST schema reload notified');
});

// ── BEHAVIOURAL (DB-gated): the fix is deployed and not drifted ─────────────────
test('M5 behavioural: live get_member_cycle_xp body == migration body (deployed, no drift)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
    assert.ifError(error);
    const live = (data || []).find((r) => r.proname === 'get_member_cycle_xp');
    assert.ok(live, 'get_member_cycle_xp present in live function inventory');
    assert.equal(live.is_secdef, true, 'live function is SECURITY DEFINER');

    // Compare live against the LATEST migration capture (the function may be legitimately
    // re-created by a later migration — e.g. mig …288 / Onda 2 FU-2 added the chapter-scope guard
    // while preserving the M5 ranking logic asserted statically above). Pinning to MIG (mig …101)
    // alone would false-fail on any unrelated re-creation; the latest-capture compare is the real
    // "deployed, no drift" invariant (mirrors rpc-migration-coverage Phase C).
    const { latest } = loadLatestCaptures(resolve(ROOT, 'supabase/migrations'));
    const cap = [...latest.entries()].find(([k]) => k.split('@')[0] === 'get_member_cycle_xp');
    assert.ok(cap, 'get_member_cycle_xp has a migration capture');
    assert.equal(live.body_md5, cap[1].bodyHash,
      'live body hash must equal the LATEST migration capture (Phase-C: change is deployed, file == live)');
  });
