/**
 * Contract: #766 PR5 — server-side `profile_complete` milestone (the CLOSING milestone PR).
 *
 * PR5 of the server-side milestones framework (table member_milestones + record_milestone PR1;
 * term_signed PR2; first_attendance + first_deliverable PR3; promotion PR4). PR5 fires the
 * `profile_complete` milestone when members.profile_completed_at transitions NULL -> NOT NULL
 * (the member's first profile save).
 *
 * GROUNDING (execute_sql, 2026-06-17): members.profile_completed_at (timestamptz NULL) is written
 * ONLY by update_my_profile(jsonb), and only as
 *   profile_completed_at = CASE WHEN profile_completed_at IS NULL THEN now() ELSE profile_completed_at END
 * — set ONCE on the first profile save, never cleared. So the column is MONOTONIC. The SPEC §2
 * grounding stands: there is NO "+50pts" award for profile completion (no gamification_rule /
 * gamification_points references the column), so the FE copy must NOT mention points.
 *
 * Unlike PR4 (promotion, NO invariant — operational_role is a mutable cache with routine demotion),
 * profile_completed_at is monotonic, so PR5 ADDS a directional invariant AE that is
 * false-positive-free and consistent with AA/AB/AC/AD. Count goes 31 -> 32 (data-architect
 * GO-with-changes, PR5).
 *
 * Migration: 20260805000205_profile_complete_milestone.sql.
 * Cross-ref: docs/specs/SPEC_766_SERVER_SIDE_MILESTONES.md §7 (PR5).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');
const MIG = read('supabase/migrations/20260805000205_profile_complete_milestone.sql');
const FE = read('src/components/milestones/MilestoneCelebration.tsx');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── Offline: migration shape ───────────────────────────────────────────────────
test('migration: profile_complete trigger is AFTER UPDATE OF profile_completed_at, gated WHEN OLD NULL -> NEW NOT NULL', () => {
  assert.ok(MIG, 'PR5 migration exists');
  assert.match(MIG, /CREATE TRIGGER trg_record_profile_complete_milestone\s+AFTER UPDATE OF profile_completed_at ON public\.members/);
  assert.match(MIG, /WHEN \(OLD\.profile_completed_at IS NULL AND NEW\.profile_completed_at IS NOT NULL\)/);
});

test('migration: trigger body calls schema-qualified public.record_milestone with profile_complete', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\._trg_record_profile_complete_milestone\(\)/);
  assert.match(MIG, /PERFORM public\.record_milestone\(\s*NEW\.id, 'profile_complete', 'profile', NULL::uuid/);
});

test('migration: trigger fn is SECURITY DEFINER search_path empty + REVOKEd FROM PUBLIC', () => {
  assert.match(MIG, /SECURITY DEFINER SET search_path = ''/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._trg_record_profile_complete_milestone\(\) FROM PUBLIC/);
});

test('migration: backfill is silent (acknowledged_at=now) on profile_completed_at cohort, BEFORE CREATE TRIGGER', () => {
  const backfill = MIG.indexOf('INSERT INTO public.member_milestones');
  const trigger = MIG.indexOf('CREATE TRIGGER trg_record_profile_complete_milestone');
  assert.ok(backfill > -1 && trigger > -1, 'both present');
  assert.ok(backfill < trigger, 'backfill precedes CREATE TRIGGER (race-safe, SPEC §6.3)');
  assert.match(MIG, /WHERE profile_completed_at IS NOT NULL/);
  assert.match(MIG, /ON CONFLICT \(member_id, milestone_key\) DO NOTHING/);
  // occurred_at is the real event moment (profile_completed_at), COALESCEd for the NOT NULL column.
  assert.match(MIG, /COALESCE\(profile_completed_at, created_at, now\(\)\), 'profile'/);
});

test('migration: sanity guard asserts every member with profile_completed_at got a milestone', () => {
  assert.match(MIG, /profile_complete backfill sanity FAIL/);
});

test('migration: ADDS invariant AE (count 31 -> 32) — monotonic source, unlike promotion', () => {
  // profile_completed_at is monotonic, so a directional invariant is false-positive-free (unlike
  // PR4's promotion). The migration must redefine check_schema_invariants() with the AE block.
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.check_schema_invariants\(\)/);
  assert.match(MIG, /AE_profile_complete_milestone_has_profile_completed_at/);
  assert.match(MIG, /mm\.milestone_key = 'profile_complete'/);
});

// ── Offline: FE surface ─────────────────────────────────────────────────────────
test('FE: MilestoneCelebration owns profile_complete (alongside first_attendance/first_deliverable/promotion)', () => {
  assert.ok(FE, 'component exists');
  const owned = FE.match(/OWNED_KEYS\s*=\s*\[([^\]]*)\]/);
  assert.ok(owned, 'OWNED_KEYS declared');
  assert.ok(/'profile_complete'/.test(owned[1]), 'profile_complete is owned by this surface');
});

test('FE: profile_complete copy exists in all 3 locales, CTA to /workspace', () => {
  const block = FE.slice(FE.indexOf('profile_complete: {'), FE.indexOf('};', FE.indexOf('profile_complete: {')));
  assert.ok(block, 'profile_complete copy block present');
  for (const loc of ['pt-BR', 'en-US', 'es-LATAM']) {
    assert.ok(block.includes(`'${loc}':`), `${loc} profile_complete copy present`);
  }
  assert.match(block, /ctaHref: '\/workspace'/);
});

test('FE: profile_complete copy has ZERO numbers and NO points mention (+50pts award does not exist)', () => {
  const block = FE.slice(FE.indexOf('profile_complete: {'), FE.indexOf('};', FE.indexOf('profile_complete: {')));
  assert.ok(!/\d/.test(block), 'profile_complete copy must contain no digits');
  assert.ok(!/\b(pts|points|pontos|puntos)\b/i.test(block), 'no points mention (SPEC §2: no such award)');
});

// ── DB-gated: live behaviour ────────────────────────────────────────────────────
test('DB: check_schema_invariants reports 32 invariants, 0 violations, AE present', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('check_schema_invariants');
  assert.ok(!error, error?.message);
  assert.equal(data.length, 32, `expected 32 invariants, got ${data.length}`);
  const total = data.reduce((s, r) => s + r.violation_count, 0);
  assert.equal(total, 0, 'no invariant may have violations');
  const ae = data.find((r) => /^AE_/.test(r.invariant_name));
  assert.ok(ae, 'AE invariant present');
  assert.equal(ae.violation_count, 0, 'AE has no violations');
});

test('DB: every member with profile_completed_at has a profile_complete milestone', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: members, error: e1 } = await sb.from('members').select('id').not('profile_completed_at', 'is', null);
  assert.ok(!e1, e1?.message);
  const memberIds = [...new Set((members || []).map((m) => m.id))];
  const { data: ms, error: e2 } = await sb.from('member_milestones').select('member_id').eq('milestone_key', 'profile_complete');
  assert.ok(!e2, e2?.message);
  const milestoneIds = new Set((ms || []).map((m) => m.member_id));
  const missing = memberIds.filter((id) => !milestoneIds.has(id));
  assert.equal(missing.length, 0, `members with profile_completed_at lacking a milestone: ${missing.join(', ')}`);
});

test('DB: backfilled profile_complete milestones are acknowledged (silent, not pending)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb
    .from('member_milestones')
    .select('acknowledged_at')
    .eq('milestone_key', 'profile_complete')
    .contains('metadata', { backfill: true });
  assert.ok(!error, error?.message);
  const pending = (data || []).filter((m) => m.acknowledged_at === null);
  assert.equal(pending.length, 0, 'backfilled profile_complete milestones must be acknowledged (no retroactive celebration)');
});
