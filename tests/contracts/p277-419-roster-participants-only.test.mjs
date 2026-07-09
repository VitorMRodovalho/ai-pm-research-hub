/**
 * Contract: p277 / #419 (ADR-0100 §M4 revised) — v_initiative_roster = PARTICIPANTS ONLY.
 *
 * PM decision (2026-06-01, supersedes the original M4.2 ratification): curators/observers do NOT count
 * as members — member_count = participants. kind='observer' is the explicit non-participation marker, so
 * the canonical roster excludes observers on BOTH axes: role<>'observer' AND kind<>'observer' (mig 088).
 *
 * Drops the 4 observer-kind people on the role-vs-kind boundary: Roberto (tribe-8, role=curator) + three
 * observer-kind reviewers — Welma (Grupo), Fabricio + Sarah (LATAM). Keeps the active external_reviewer
 * (Mario) and all speakers. Live antes→depois: tribe-8 6→5, LATAM 5→3, Grupo 4→3, Mesa 4→4 (its observers
 * were already role=observer); all other tribes/initiatives unchanged.
 *
 * Because M4-A/B/C route every member-count surface through this single primitive, the one view revision
 * propagates everywhere (get_tribe_stats / exec_tribe_dashboard / digest / exec_cross all read 5 for tribe-8).
 *
 * D-M4-AXIS (PR-F) is NOT applied: get_member_tribe stays on the kind axis, which is now CONSISTENT with the
 * participants-only member definition (the role-vs-kind divergence is gone). metric-3 reads operational_role
 * + get_member_tribe, NOT this view → it is UNAFFECTED. This test forward-defends both: the migration must
 * NOT touch get_member_tribe, and the roster must exclude observers.
 *
 * Cross-ref: ADR-0100 §M4 (revised) + decision log; issue #419; mig 088 supersedes mig 082's role<>observer.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { attendanceCycleStart } from '../helpers/reference-cycle.mjs';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000088_p277_419_roster_participants_only.sql');
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const code = body.replace(/--[^\n]*/g, ''); // strip comments for forward-defense

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const svcGated = !!(SUPABASE_URL && SERVICE_KEY);
const anonGated = !!(SUPABASE_URL && ANON_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const LATAM = 'a68fcc06-7de8-400b-b5b3-60e368fb46ac';
const GRUPO = '2f5846f3-5b6b-4ce1-9bc6-e07bdb22cd19';
const MESA  = '6e9af7a8-1696-4169-a1a1-c0e160600002';

// ── STATIC ────────────────────────────────────────────────────────────────────────
test('roster participants-only static: view excludes observers by kind AND role', () => {
  assert.ok(existsSync(MIG), 'migration 088 exists');
  assert.match(body, /CREATE OR REPLACE VIEW public\.v_initiative_roster AS/);
  assert.match(code, /e\.role <> 'observer'::text/, 'keeps role<>observer');
  assert.match(code, /e\.kind <> 'observer'::text/, 'adds kind<>observer (participants-only)');
});

test('roster participants-only static: re-asserts the mig-085 anon lockdown', () => {
  assert.match(body, /ALTER VIEW public\.v_initiative_roster SET \(security_invoker = true\)/, 'security_invoker preserved');
  assert.match(body, /REVOKE ALL ON public\.v_initiative_roster FROM anon, PUBLIC/, 'anon + PUBLIC revoked (pg_default_acl trap)');
  assert.match(body, /GRANT SELECT ON public\.v_initiative_roster TO authenticated, service_role/, 'authenticated + service_role retained');
});

test('roster participants-only forward-defense: this migration does NOT touch get_member_tribe (M4-F NOT applied)', () => {
  // the member definition and the attendance resolver are unified on the kind axis by EXCLUSION, not by
  // changing get_member_tribe — so metric-3 stays frozen. PR-F (D-M4-AXIS) is deliberately not applied here.
  assert.ok(!/get_member_tribe/.test(code), 'must not redefine get_member_tribe in this PR (comments may reference it)');
});

// ── BEHAVIOURAL (DB-gated) ──────────────────────────────────────────────────────────
test('roster participants-only DB: tribe-8 = 5, natives LATAM = 3 / Grupo = 3 / Mesa = 4', { skip: svcGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const { data: t8Init } = await sb.rpc('resolve_initiative_id', { p_tribe_id: 8 });
  const counts = {};
  for (const [k, id] of Object.entries({ tribe8: t8Init, LATAM, GRUPO: GRUPO, MESA })) {
    const { data } = await sb.rpc('get_initiative_roster_count', { p_initiative_id: id });
    counts[k] = Number(data);
  }
  assert.equal(counts.tribe8, 5, 'tribe-8 = 5 (curator Roberto excluded)');
  assert.equal(counts.LATAM, 3, 'LATAM = 3 (Fabricio + Sarah observer-kind reviewers excluded)');
  assert.equal(counts.GRUPO, 3, 'Grupo = 3 (Welma observer-kind reviewer excluded)');
  assert.equal(counts.MESA, 4, 'Mesa = 4 (unchanged — its observers were already role=observer)');
});

test('roster participants-only DB: no observer rows (role OR kind) survive in any roster', { skip: svcGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const { data: rows } = await sb.from('v_initiative_roster').select('role, kind');
  assert.ok(Array.isArray(rows) && rows.length > 0, 'roster has rows');
  assert.equal(rows.filter((r) => r.role === 'observer' || r.kind === 'observer').length, 0,
    'no row has role=observer OR kind=observer');
});

test('roster participants-only DB: single-source propagation — get_tribe_stats(8) == digest == 5', { skip: svcGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const { data: stats } = await sb.rpc('get_tribe_stats', { p_tribe_id: 8 });
  const { data: digest } = await sb.rpc('get_weekly_tribe_digest', { p_tribe_id: 8 });
  assert.equal(Number(stats.member_count), 5, 'get_tribe_stats tribe-8 member_count = 5 (via primitive)');
  assert.equal(Number(digest.aggregates.active_members), 5, 'weekly digest tribe-8 active_members = 5 (via primitive)');
});

test('roster participants-only DB: metric-3 is INDEPENDENT — get_member_tribe still kind-based (M4-F not applied)', { skip: svcGated ? false : skipMsg }, async (t) => {
  const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  // Roberto's get_member_tribe stays NULL (his tribe-8 engagement is kind=observer) → he is NOT pulled into
  // the tribe-8 attendance cohort. tribe-8 engagement cohort_n stays 5 (unchanged by the roster revision).
  const cs = await attendanceCycleStart(sb); // most recent populated cycle (#1123)
  if (!cs) { t.skip('no populated attendance cohort — cycle turnover (#1234)'); return; }
  const { data: t8eng } = await sb.rpc('get_attendance_engagement_summary', { p_scope: 'tribe', p_scope_id: 8, p_cycle_start: cs });
  assert.equal(Number(t8eng.cohort_n), 5, 'metric-3 tribe-8 cohort_n = 5 (unchanged — reads operational_role + get_member_tribe, not the roster)');
});

test('roster participants-only DB: anon CANNOT SELECT the view (mig-085 lockdown intact)', { skip: anonGated ? false : 'anon key required' }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { data, error } = await anon.from('v_initiative_roster').select('name').limit(1);
  assert.ok(error || !data || data.length === 0, 'anon must get an error or zero rows (no member names leak)');
});
