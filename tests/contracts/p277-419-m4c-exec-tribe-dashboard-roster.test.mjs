/**
 * Contract: p277 / #419 (ADR-0100) metric 4 — PR4-C (the big one): exec_tribe_dashboard roster convergence.
 *
 * The 12KB tribe-KPI-tab dashboard computed its member-cohort NINE times via
 *   m.is_active = true AND EXISTS(engagements WHERE kind='volunteer' AND status='active' AND initiative=X)
 * The kind='volunteer' predicate WRONGLY dropped the curator Roberto Macêdo (engagement role=curator,
 * kind=observer) → tribe-8 KPI read 5. All 9 cohort sites now ride the canonical roster view
 * public.v_initiative_roster (role<>'observer'; primitive shipped PR4-A, mig 082):
 *   - members.total  := get_initiative_roster_count(v_tribe_initiative_id)   (reads the primitive directly)
 *   - members.active := members.total   (the current_cycle_active gate is retired — same convergence PR4-B
 *                                        applied to the weekly digest; an active engagement IS the cohort)
 *   - by_role / by_chapter / list / inactive_30d / tribe_total_xp / top_contributors-cohort / cpmai
 *     → m.id IN (SELECT member_id FROM public.v_initiative_roster WHERE initiative_id = v_tribe_initiative_id)
 *
 * antes→depois (verified live, cycle_3): ONLY tribe 8 changes 5→6 (gains Roberto); t1=4 t2=5 t3=0 t4=5 t5=3
 * t6=6 t7=4 unchanged. For every tribe today dash_total == dash_active, so active=total changes no number.
 * exec_initiative_dashboard(uuid,text) is a thin wrapper RETURN exec_tribe_dashboard(resolve_tribe_id(.),.)
 * — the primary live frontend path — so the fix is visible there too.
 *
 * SCOPE: only the member-cohort axis. top_contributors keeps its lifetime-SUM ORDER BY (cycle-mode/tiebreak
 * is metric 5 / PR5-E, kept separable). The cross-tribe auth gate still calls get_member_tribe (kind->role
 * axis is the separate conditional PR4-F) — untouched here.
 *
 * Same-signature CREATE OR REPLACE; non-cohort sections byte-identical to mig 069 (mechanically diffed).
 * Cross-ref: SPEC_419_M4_M8_CANONICAL_METRICS.md §M4.5/§M4.6 (PR4-C); ADR-0100 §2.2; issue #419.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { rosterViewCount } from '../helpers/roster-oracle.mjs';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000084_p277_419_m4c_exec_tribe_dashboard_roster.sql');
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
// strip comments (full-line + inline) so header-comment mentions of the OLD predicate don't trip forward-defense
const code = body.replace(/--[^\n]*/g, '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── STATIC ────────────────────────────────────────────────────────────────────────
test('M4-C static: same-signature CREATE OR REPLACE (no DROP)', () => {
  assert.ok(existsSync(MIG), 'M4-C migration 20260805000084 exists');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.exec_tribe_dashboard\(p_tribe_id integer, p_cycle text DEFAULT NULL::text\)/i, 'same signature');
  assert.ok(!/DROP FUNCTION/i.test(body), 'same signature → no DROP');
  assert.match(body, /SECURITY DEFINER/i, 'stays SECURITY DEFINER');
  assert.match(body, /SET search_path TO 'public', 'pg_temp'/i, 'search_path preserved');
});

test('M4-C static: member_count reads the canonical roster primitive; active converges onto total', () => {
  assert.match(code, /v_members_total := COALESCE\(public\.get_initiative_roster_count\(v_tribe_initiative_id\), 0\)/,
    'members.total = get_initiative_roster_count(v_tribe_initiative_id)');
  assert.match(code, /v_members_active := v_members_total;/,
    'members.active converges onto the same roster as total (current_cycle_active gate retired)');
});

test('M4-C static: all member-cohort sites ride v_initiative_roster (>=7 IN-subqueries)', () => {
  const matches = code.match(/v_initiative_roster WHERE initiative_id = v_tribe_initiative_id/g) || [];
  assert.ok(matches.length >= 7,
    `expected >=7 roster-view cohort sites (by_role, by_chapter, list, inactive_30d, tribe_total_xp, top_contributors, cpmai); found ${matches.length}`);
});

test('M4-C forward-defense: the kind=volunteer member-cohort predicate is gone (and no cca cohort)', () => {
  assert.ok(!/e\.kind = 'volunteer'/.test(code), "no engagement kind='volunteer' member-cohort predicate survives");
  assert.ok(!/current_cycle_active/.test(code), 'no current_cycle_active gate survives in the body (retired)');
  // the old verbose EXISTS(engagements ... e.person_id = m.person_id ...) member-cohort block must be gone
  assert.ok(!/EXISTS \(\s*SELECT 1 FROM public\.engagements e\s*WHERE e\.person_id = m\.person_id/.test(code),
    'the EXISTS(engagements WHERE person_id=m.person_id ...) cohort block is gone');
});

test('M4-C static: XP ranking left untouched (metric 5 separable)', () => {
  // top_contributors still orders by lifetime SUM(points) DESC — the cycle-mode/tiebreak fix is M5/PR5-E
  assert.match(code, /ROW_NUMBER\(\) OVER \(ORDER BY SUM\(gp\.points\) DESC\)/, 'top_contributors keeps lifetime-SUM ordering');
});

test('M4-C static: all six dashboard sections preserved (no body truncation)', () => {
  for (const section of ['tribe', 'members', 'production', 'engagement', 'gamification', 'trends']) {
    assert.match(body, new RegExp(`'${section}', jsonb_build_object`, 'i'), `${section} section preserved`);
  }
  assert.match(body, /RETURN v_result;/i);
});

// ── SECURITY (paired migration 085 — close the anon PII leak on the canonical roster view) ──
const MIG_SEC = resolve(ROOT, 'supabase/migrations/20260805000085_p277_419_m4c_roster_view_anon_lockdown.sql');
const sec = existsSync(MIG_SEC) ? readFileSync(MIG_SEC, 'utf8') : '';

test('M4-C security: v_initiative_roster locked down — security_invoker + anon revoked (forward-defense)', () => {
  assert.ok(existsSync(MIG_SEC), 'migration 085 (roster view anon lockdown) exists');
  // the view PR4-C makes load-bearing leaked 63 member names to anon (advisor security_definer_view ERROR)
  assert.match(sec, /ALTER VIEW public\.v_initiative_roster SET \(security_invoker = true\)/,
    'view flipped to security_invoker (honors base-table RLS; both SECDEF consumers run as postgres/bypassrls so unaffected)');
  assert.match(sec, /REVOKE ALL ON public\.v_initiative_roster FROM anon/,
    'anon SELECT revoked — closes the 63-name PII leak (CLAUDE.md invariant: anon gets nothing from PII)');
  assert.match(sec, /GRANT SELECT ON public\.v_initiative_roster TO authenticated, service_role/,
    'authenticated + service_role retained');
});

// ── BEHAVIOURAL (DB-gated) ──────────────────────────────────────────────────────────
test('M4-C DB: auth gate intact (unauthenticated service-role caller rejected)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { error } = await sb.rpc('exec_tribe_dashboard', { p_tribe_id: 8 });
  assert.ok(error, 'no-auth caller must be rejected (member not found) — gate not changed by PR4-C');
});

test('M4-C DB: tribe-8 canonical roster == 5 (participants-only, mig 088); the value members.total now returns', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: initId, error: e0 } = await sb.rpc('resolve_initiative_id', { p_tribe_id: 8 });
  assert.ifError(e0);
  const { data: roster, error: e1 } = await sb.rpc('get_initiative_roster_count', { p_initiative_id: initId });
  assert.ifError(e1);
  const viewCount = await rosterViewCount(sb, initId);
  // #1249: single-source contract (RPC == canonical view), not the dead absolute fixture (== 5).
  assert.equal(Number(roster), viewCount, 'get_initiative_roster_count == canonical view (single source)');
});

test('M4-C DB: get_initiative_roster_count agrees with the canonical view across tribes (single source)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // #1249: the migration-088 snapshot ({1:4,6:5}) was a dead cohort fixture — it broke at the C4
  // kickoff (reorg + #1247 phantom-membership regularization). The durable invariant is that
  // members.total (get_initiative_roster_count) reads the canonical view for EVERY tribe.
  for (const tid of [1, 6, 8]) {
    const { data: initId } = await sb.rpc('resolve_initiative_id', { p_tribe_id: tid });
    const viewCount = await rosterViewCount(sb, initId);
    const { data: roster } = await sb.rpc('get_initiative_roster_count', { p_initiative_id: initId });
    assert.equal(Number(roster), viewCount, `tribe ${tid} roster RPC == canonical view (single source)`);
  }
});
