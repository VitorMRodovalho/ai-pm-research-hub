/**
 * Contract: p277 / #419 (ADR-0100) metric 4 — PR4-A: canonical roster primitive.
 *
 * member_count / tribe_roster = DISTINCT persons with an ACTIVE, NON-OBSERVER ROLE engagement on the
 * resolved initiative. The primitive (view v_initiative_roster + helper get_initiative_roster_count)
 * filters on ROLE (role<>'observer'), NEVER on kind — kind='volunteer' is the live bug that drops the
 * curator (Roberto Macêdo, role=curator/kind=observer; the exec_tribe_dashboard 5 vs canonical 6). An
 * active engagement IS the current-cycle cohort (engagements has no cycle_id); members.current_cycle_active
 * is the drifting gate that over-counts (the get_weekly_tribe_digest 7).
 *
 * PR4-A is ADDITIVE — no surface RPC is touched yet. The tribe/initiative-keyed RPCs converge onto this
 * primitive in the follow-up PRs (4-B initiative RPCs · 4-C tribe RPCs: exec_tribe_dashboard 5->6 +
 * get_weekly_tribe_digest 7->6 · 4-D frontend single-source · 4-F conditional get_member_tribe axis).
 * So this test asserts the PRIMITIVE is correct + ready, not the convergence (which follows).
 *
 * Cross-ref: SPEC_419_M4_M8_CANONICAL_METRICS.md §M4; ADR-0100 §2.2 tribe_roster/member_count + §2.4 V4
 * bridge; ADR-0005 (initiatives primitive / tribes-as-bridge); issue #419.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000082_p277_419_m4a_initiative_roster_primitive.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const mig = migRaw.replace(/^\s*--.*$/gm, '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── STATIC ──────────────────────────────────────────────────────────────────────
test('M4-A static: v_initiative_roster filters on ROLE (role<>observer), never kind', () => {
  assert.ok(existsSync(MIG), 'M4-A migration 20260805000082 exists');
  assert.match(mig, /CREATE OR REPLACE VIEW public\.v_initiative_roster/, 'declares the roster view');
  assert.match(mig, /WHERE e\.status = 'active'\s+AND e\.role <> 'observer'/, 'active + role<>observer');
  // forward-defense: the view body must NOT gate membership on kind='volunteer' (the dropped-curator bug)
  const viewBlock = mig.match(/CREATE OR REPLACE VIEW public\.v_initiative_roster[\s\S]*?;/);
  assert.ok(viewBlock, 'view block parses');
  assert.doesNotMatch(viewBlock[0], /kind = 'volunteer'/, "membership does NOT gate on kind='volunteer'");
});

test('M4-A static: get_initiative_roster_count counts DISTINCT person over the view', () => {
  const fn = mig.match(/CREATE OR REPLACE FUNCTION public\.get_initiative_roster_count[\s\S]*?\$function\$;/);
  assert.ok(fn, 'helper block parses');
  assert.match(fn[0], /COUNT\(DISTINCT person_id\)/, 'counts distinct person');
  assert.match(fn[0], /FROM public\.v_initiative_roster/, 'reads the canonical view');
});

test('M4-A static: reuses the existing tribe<->initiative resolvers (no duplicate definition)', () => {
  // PR4-A must NOT (re)define resolve_initiative_id / resolve_tribe_id — they already exist.
  assert.doesNotMatch(mig, /CREATE OR REPLACE FUNCTION public\.resolve_initiative_id/, 'does not redefine resolve_initiative_id');
  assert.doesNotMatch(mig, /CREATE OR REPLACE FUNCTION public\.resolve_tribe_id/, 'does not redefine resolve_tribe_id');
});

// ── BEHAVIOURAL (DB-gated) ───────────────────────────────────────────────────────
test('M4-A behavioural: tribe 8 roster = 6 and INCLUDES the curator Roberto (role-not-kind)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: initId, error: e0 } = await sb.rpc('resolve_initiative_id', { p_tribe_id: 8 });
  assert.ifError(e0);
  const { data: count, error: e1 } = await sb.rpc('get_initiative_roster_count', { p_initiative_id: initId });
  assert.ifError(e1);
  assert.equal(count, 6, 'tribe-8 canonical roster = 6');

  const { data: rows, error: e2 } = await sb
    .from('v_initiative_roster').select('name, role').eq('initiative_id', initId);
  assert.ifError(e2);
  assert.ok(rows.some((r) => r.name === 'Roberto Macêdo'),
    'the curator Roberto (role=curator/kind=observer) IS in the roster — the row kind=volunteer wrongly drops');
  assert.equal(rows.filter((r) => r.role === 'observer').length, 0, 'no role=observer rows');
});

test('M4-A behavioural: helper count == COUNT(DISTINCT person) over the view, per initiative', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: initId } = await sb.rpc('resolve_initiative_id', { p_tribe_id: 6 });
  const { data: count } = await sb.rpc('get_initiative_roster_count', { p_initiative_id: initId });
  const { data: rows } = await sb.from('v_initiative_roster').select('person_id').eq('initiative_id', initId);
  const distinct = new Set(rows.map((r) => r.person_id)).size;
  assert.equal(Number(count), distinct, 'helper == distinct person over the view');
  assert.equal(Number(count), 6, 'tribe-6 canonical roster = 6');
});
