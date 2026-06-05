/**
 * Contract: p276 — Bucket A LGPD / authorization hardening
 * (cross-surface metric-disparity audit, 2026-05-28).
 *
 * Closes four SECURITY DEFINER exposures surfaced by the audit:
 *   D1  get_public_leaderboard / get_public_trail_ranking — honor gamification_opt_out
 *       on the anon/public surface (ADR-0050). These anon-granted RPCs were the only
 *       leaderboard variants that ignored the member "hide me" consent toggle.
 *   D2  get_attendance_panel — was SECDEF + anon-granted with no in-body auth, leaking
 *       org-wide attendance % + dropout_risk + typology to UNAUTHENTICATED callers.
 *       Now requires an active member; masks dropout_risk/typology to all but leadership
 *       (manage_event) and the caller's own row. combined_pct ranking preserved.
 *   D3  get_global_research_pipeline — gated to GP leadership (manage_platform).
 *   D3  get_initiative_attendance_grid (native path) — scope check mirrors the tribe grid.
 *   XP  get_member_cycle_xp — gated self-or-privileged (view_pii).
 *
 * Migration: supabase/migrations/20260805000055_p276_bucket_a_lgpd_auth_hardening.sql
 *
 * Asserts:
 *   - Static (file body): per-RPC gate/mask/signature presence.
 *   - Forward-defense: the opt-out clause + the anon gate + the pipeline gate must
 *     remain present (locks the regression class permanently in CI).
 *   - DB-gated (skip offline): live anon/no-auth behavior closes the leak.
 *
 * Cross-ref:
 *   - Audit: docs/audit/METRIC_DISPARITY_AUDIT_2026-05-28.md (D1/D2/D3 + get_member_cycle_xp)
 *   - LGPD Art. 18 (consent self-management) · GC-162 (no PII via ungated SECDEF)
 *   - Reference opt-out predicate: get_gamification_leaderboard (member-tier variant)
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATION_FILE = resolve(
  ROOT,
  'supabase/migrations/20260805000055_p276_bucket_a_lgpd_auth_hardening.sql'
);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIGRATION_FILE) ? readFileSync(MIGRATION_FILE, 'utf8') : '';

// ===================================================================
// STATIC migration body assertions (always run)
// ===================================================================

test('p276: migration file exists', () => {
  assert.ok(existsSync(MIGRATION_FILE), `Migration file must exist at ${MIGRATION_FILE}`);
});

test('p276: all six target RPCs are CREATE OR REPLACE (same-signature, no DROP)', () => {
  for (const fn of [
    'get_public_leaderboard',
    'get_public_trail_ranking',
    'get_attendance_panel',
    'get_global_research_pipeline',
    'get_initiative_attendance_grid',
    'get_member_cycle_xp',
  ]) {
    assert.match(
      body,
      new RegExp(`CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${fn}\\b`, 'i'),
      `${fn} must be CREATE OR REPLACE`
    );
  }
  assert.ok(!/DROP\s+FUNCTION/i.test(body), 'must not DROP any function (no consumer break)');
});

test('p276: all six RPCs preserve SECURITY DEFINER', () => {
  const secdef = (body.match(/SECURITY DEFINER/g) || []).length;
  assert.ok(secdef >= 6, `expected >=6 SECURITY DEFINER, found ${secdef}`);
});

// ---- D1: public leaderboard + trail ranking honor opt-out ----
test('p276 D1: get_public_leaderboard honors gamification_opt_out', () => {
  const seg = body.slice(body.indexOf('FUNCTION public.get_public_leaderboard'), body.indexOf('FUNCTION public.get_public_trail_ranking'));
  assert.match(seg, /m\.gamification_opt_out\s*=\s*false/i, 'get_public_leaderboard must filter gamification_opt_out = false');
});

test('p276 D1: get_public_trail_ranking honors gamification_opt_out', () => {
  const seg = body.slice(body.indexOf('FUNCTION public.get_public_trail_ranking'), body.indexOf('FUNCTION public.get_attendance_panel'));
  assert.match(seg, /m\.gamification_opt_out\s*=\s*false/i, 'get_public_trail_ranking must filter gamification_opt_out = false');
});

test('p276 D1 forward-defense: the opt-out clause appears on BOTH public RPCs', () => {
  const occ = (body.match(/gamification_opt_out\s*=\s*false/g) || []).length;
  assert.ok(occ >= 2, `opt-out clause must remain on both public RPCs; found ${occ}`);
});

// ---- D2: get_attendance_panel requires auth + masks HR fields ----
test('p276 D2: get_attendance_panel requires an active member (anon gate)', () => {
  const seg = body.slice(body.indexOf('FUNCTION public.get_attendance_panel'), body.indexOf('FUNCTION public.get_global_research_pipeline'));
  assert.match(seg, /LANGUAGE plpgsql/i, 'get_attendance_panel must be plpgsql (gate needs a body)');
  assert.match(seg, /m\.auth_id\s*=\s*auth\.uid\(\)\s+AND\s+m\.is_active/i, 'must resolve caller via auth.uid() + is_active');
  assert.match(seg, /IF\s+v_caller_id\s+IS\s+NULL\s+THEN\s+RETURN;/i, 'anon/ghost path must RETURN no rows');
});

test('p276 D2: dropout_risk/typology masked to leadership (manage_event) or self', () => {
  const seg = body.slice(body.indexOf('FUNCTION public.get_attendance_panel'), body.indexOf('FUNCTION public.get_global_research_pipeline'));
  assert.match(seg, /can_by_member\(\s*v_caller_id\s*,\s*'manage_event'\s*\)/i, 'privilege gate must use manage_event');
  const masks = (seg.match(/v_privileged\s+OR\s+c\.id\s*=\s*v_caller_id/g) || []).length;
  assert.ok(masks >= 2, `dropout_risk AND typology must both be masked; found ${masks} mask guards`);
});

test('p276 D2 forward-defense: dropout_risk is never emitted unconditionally', () => {
  const seg = body.slice(body.indexOf('FUNCTION public.get_attendance_panel'), body.indexOf('FUNCTION public.get_global_research_pipeline'));
  // The raw boolean expression must appear only INSIDE a CASE ... v_privileged guard, never as a bare "... ) AS dropout_risk".
  assert.ok(
    !/\)\s+AS\s+dropout_risk/i.test(seg.replace(/CASE WHEN v_privileged[\s\S]*?END AS dropout_risk/i, '')),
    'dropout_risk must only be produced through the v_privileged/self CASE guard'
  );
});

// ---- D3a: research pipeline gated to manage_platform ----
test('p276 D3a: get_global_research_pipeline gated on manage_platform', () => {
  const seg = body.slice(body.indexOf('FUNCTION public.get_global_research_pipeline'), body.indexOf('FUNCTION public.get_initiative_attendance_grid'));
  assert.match(seg, /LANGUAGE plpgsql/i, 'must be plpgsql to hold the gate');
  assert.match(seg, /can_by_member\(\s*v_caller_id\s*,\s*'manage_platform'\s*\)/i, 'must gate on manage_platform');
  assert.match(seg, /json_build_object\(\s*'error'\s*,\s*'Unauthorized'\s*\)/i, 'must return error json on denial');
});

// ---- D3b: initiative grid scope check on native path ----
test('p276 D3b: get_initiative_attendance_grid scopes the native path', () => {
  const seg = body.slice(body.indexOf('FUNCTION public.get_initiative_attendance_grid'), body.indexOf('FUNCTION public.get_member_cycle_xp'));
  // delegation to tribe grid preserved
  assert.match(seg, /RETURN\s+public\.get_tribe_attendance_grid\(/i, 'tribe path delegation must be preserved');
  // mirrored scope check
  assert.match(seg, /can_by_member\(\s*v_caller\.id\s*,\s*'manage_member'\s*\)/i, 'native path must allow manage_member');
  assert.match(seg, /can_by_member\(\s*v_caller\.id\s*,\s*'manage_partner'\s*\)/i, 'native path must allow manage_partner (stakeholder)');
  assert.match(seg, /e\.initiative_id\s*=\s*p_initiative_id[\s\S]*?e\.status\s*=\s*'active'/i, 'native path must allow own active engagement on the initiative');
});

// ---- XP: get_member_cycle_xp self-or-privileged ----
test('p276 XP: get_member_cycle_xp gates self-or-view_pii', () => {
  const seg = body.slice(body.indexOf('FUNCTION public.get_member_cycle_xp'));
  assert.match(seg, /p_member_id\s*<>\s*v_caller_id/i, 'must compare requested member id against caller');
  assert.match(seg, /can_by_member\(\s*v_caller_id\s*,\s*'view_pii'\s*\)/i, 'cross-member read must require view_pii');
});

// ---- signatures / defaults preserved (SEDIMENT-238.C) ----
test('p276: parameter defaults preserved on replaced signatures', () => {
  assert.match(body, /get_public_leaderboard\(p_limit integer DEFAULT 50\)/i, 'get_public_leaderboard keeps p_limit DEFAULT 50');
  assert.match(body, /p_cycle_start date DEFAULT '2026-01-01'[\s\S]*?p_cycle_end date DEFAULT '2026-06-30'/i, 'get_attendance_panel keeps date defaults');
  assert.match(body, /get_initiative_attendance_grid\(p_initiative_id uuid, p_event_type text DEFAULT NULL/i, 'grid keeps p_event_type DEFAULT NULL');
});

test('p276: migration issues NOTIFY pgrst', () => {
  assert.match(body, /NOTIFY\s+pgrst/i, 'must reload PostgREST schema cache');
});

// ===================================================================
// DB-gated live behavior (skip without service-role env)
// ===================================================================

test('p276 DB: get_attendance_panel returns 0 rows without auth (anon gate live)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_attendance_panel');
  assert.ok(!error, `rpc should not error: ${error?.message}`);
  assert.equal((data || []).length, 0, 'service-role/no-auth caller must get zero rows (no anon leak)');
});

test('p276 DB: get_global_research_pipeline denies without auth', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data } = await sb.rpc('get_global_research_pipeline');
  assert.equal(data?.error, 'Unauthorized', 'no-auth caller must be denied');
});

test('p276 DB: get_member_cycle_xp raises without auth', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { error } = await sb.rpc('get_member_cycle_xp', { p_member_id: '00000000-0000-0000-0000-000000000000' });
  assert.ok(error, 'no-auth caller must be rejected (insufficient_privilege)');
});

test('p276 DB: get_public_leaderboard pool == active members with opt_out=false', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_public_leaderboard', { p_limit: 1000 });
  assert.ok(!error, `rpc should not error: ${error?.message}`);
  const { count } = await sb
    .from('members')
    .select('id', { count: 'exact', head: true })
    .eq('is_active', true)
    .eq('current_cycle_active', true)
    .eq('gamification_opt_out', false);
  assert.equal((data || []).length, count, 'leaderboard must equal the opt-out-respecting active pool');
});
