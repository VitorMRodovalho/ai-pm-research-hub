/**
 * Contract: #766 PR4 — server-side `promotion` milestone.
 *
 * PR4 of the server-side milestones framework (table member_milestones + record_milestone
 * shipped PR1; term_signed PR2; first_attendance + first_deliverable PR3). PR4 fires the
 * `promotion` milestone when a member's operational_role is elevated to 'tribe_leader' (the
 * leader-track role) from any non-leader role.
 *
 * GROUNDING (execute_sql, 2026-06-17): operational_role has NO value 'leader' — the SPEC §7
 * draft said 'leader' but the live leader-track role is 'tribe_leader'. promote_to_leader_track
 * does NOT set operational_role (it touches selection_applications); the role is set by the
 * sync_operational_role_cache trigger from auth_engagements. So the trigger lives on
 * members.operational_role (captures EVERY promotion path), keyed on tribe_leader.
 *
 * Distinct from PR2/PR3: NO new invariant. promotion has no immutable source of truth
 * (operational_role is a mutable cache; demotion is routine), so a directional "milestone =>
 * is tribe_leader now" check would generate permanent false positives. Count stays 31. The
 * structural guard is the trigger WHEN clause + UNIQUE(member_id,milestone_key) + record_milestone
 * REVOKE (data-architect + security-engineer GO-with-changes, PR4).
 *
 * Migration: 20260805000204_promotion_milestone.sql.
 * Cross-ref: docs/specs/SPEC_766_SERVER_SIDE_MILESTONES.md §7 (PR4).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');
const MIG = read('supabase/migrations/20260805000204_promotion_milestone.sql');
const FE = read('src/components/milestones/MilestoneCelebration.tsx');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── Offline: migration shape ───────────────────────────────────────────────────
test('migration: promotion trigger is AFTER UPDATE OF operational_role, gated WHEN tribe_leader (not "leader")', () => {
  assert.ok(MIG, 'PR4 migration exists');
  assert.match(MIG, /CREATE TRIGGER trg_record_promotion_milestone\s+AFTER UPDATE OF operational_role ON public\.members/);
  assert.match(MIG, /WHEN \(NEW\.operational_role = 'tribe_leader' AND OLD\.operational_role IS DISTINCT FROM 'tribe_leader'\)/);
  // the live leader-track role is tribe_leader; 'leader' is not a real operational_role value
  assert.ok(!/=\s*'leader'/.test(MIG), "must key on 'tribe_leader', never the non-existent 'leader' value");
});

test('migration: trigger body calls schema-qualified public.record_milestone with promotion + role metadata', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\._trg_record_promotion_milestone\(\)/);
  assert.match(MIG, /PERFORM public\.record_milestone\(\s*NEW\.id, 'promotion', 'promotion', NULL::uuid/);
  assert.match(MIG, /'from_role', OLD\.operational_role, 'to_role', NEW\.operational_role/);
});

test('migration: trigger fn is SECURITY DEFINER search_path empty + REVOKEd FROM PUBLIC', () => {
  assert.match(MIG, /SECURITY DEFINER SET search_path = ''/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._trg_record_promotion_milestone\(\) FROM PUBLIC/);
});

test('migration: backfill is silent (acknowledged_at=now) on tribe_leader cohort, BEFORE CREATE TRIGGER', () => {
  const backfill = MIG.indexOf('INSERT INTO public.member_milestones');
  const trigger = MIG.indexOf('CREATE TRIGGER trg_record_promotion_milestone');
  assert.ok(backfill > -1 && trigger > -1, 'both present');
  assert.ok(backfill < trigger, 'backfill precedes CREATE TRIGGER (race-safe, SPEC §6.3)');
  assert.match(MIG, /WHERE operational_role = 'tribe_leader'/);
  assert.match(MIG, /ON CONFLICT \(member_id, milestone_key\) DO NOTHING/);
  // occurred_at proxy (no promoted_at column exists)
  assert.match(MIG, /COALESCE\(updated_at, created_at, now\(\)\), 'promotion'/);
});

test('migration: sanity guard asserts every tribe_leader got a milestone', () => {
  assert.match(MIG, /promotion backfill sanity FAIL/);
});

test('migration: adds NO new invariant — count stays 31 (no immutable source for promotion)', () => {
  // Unlike PR2/PR3, promotion has no immutable source of truth, so check_schema_invariants()
  // is intentionally untouched. The migration must not redefine it nor add an AE_* label.
  assert.ok(!/check_schema_invariants/.test(MIG), 'PR4 must not touch check_schema_invariants()');
  assert.ok(!/AE_/.test(MIG), 'PR4 adds no AE invariant');
});

// ── Offline: FE surface ─────────────────────────────────────────────────────────
test('FE: MilestoneCelebration owns promotion (alongside first_attendance + first_deliverable)', () => {
  assert.ok(FE, 'component exists');
  // Inclusion check (not exact-array) so PR5 (profile_complete) plugging in does not rebump this.
  const owned = FE.match(/OWNED_KEYS\s*=\s*\[([^\]]*)\]/);
  assert.ok(owned, 'OWNED_KEYS declared');
  assert.ok(/'first_attendance'/.test(owned[1]) && /'first_deliverable'/.test(owned[1]) && /'promotion'/.test(owned[1]),
    'first_attendance + first_deliverable + promotion are owned by this surface');
});

test('FE: promotion copy exists in all 3 locales, CTA to /workspace', () => {
  const block = FE.slice(FE.indexOf('promotion: {'), FE.indexOf('};', FE.indexOf('promotion: {')));
  assert.ok(block, 'promotion copy block present');
  for (const loc of ['pt-BR', 'en-US', 'es-LATAM']) {
    assert.ok(block.includes(`'${loc}':`), `${loc} promotion copy present`);
  }
  assert.match(block, /ctaHref: '\/workspace'/);
});

test('FE: promotion copy has ZERO numbers (grounding — no fabricated points/counts)', () => {
  const block = FE.slice(FE.indexOf('promotion: {'), FE.indexOf('};', FE.indexOf('promotion: {')));
  assert.ok(!/\d/.test(block), 'promotion copy must contain no digits');
});

// ── DB-gated: live behaviour ────────────────────────────────────────────────────
test('DB: no promotion-specific invariant exists (mutable cache, no directional check), 0 violations', { skip: dbGated ? false : skipMsg }, async () => {
  // PR4 deliberately added no invariant for promotion (operational_role is a mutable cache;
  // demotion is routine). The absolute count is NOT pinned here — later PRs legitimately add
  // invariants for OTHER milestones (PR5 added AE for profile_complete, whose source is monotonic).
  // What must hold: no invariant is keyed on the promotion milestone.
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('check_schema_invariants');
  assert.ok(!error, error?.message);
  const total = data.reduce((s, r) => s + r.violation_count, 0);
  assert.equal(total, 0, 'no invariant may have violations');
  assert.ok(!data.some((r) => /promotion/i.test(r.invariant_name)), 'no promotion-specific invariant should exist');
});

test('DB: every current tribe_leader has a promotion milestone', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: leaders, error: e1 } = await sb.from('members').select('id').eq('operational_role', 'tribe_leader');
  assert.ok(!e1, e1?.message);
  const leaderIds = [...new Set((leaders || []).map((m) => m.id))];
  const { data: ms, error: e2 } = await sb.from('member_milestones').select('member_id').eq('milestone_key', 'promotion');
  assert.ok(!e2, e2?.message);
  const milestoneIds = new Set((ms || []).map((m) => m.member_id));
  const missing = leaderIds.filter((id) => !milestoneIds.has(id));
  assert.equal(missing.length, 0, `tribe_leaders without a promotion milestone: ${missing.join(', ')}`);
});

test('DB: backfilled promotion milestones are acknowledged (silent, not pending)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb
    .from('member_milestones')
    .select('acknowledged_at')
    .eq('milestone_key', 'promotion')
    .contains('metadata', { backfill: true });
  assert.ok(!error, error?.message);
  const pending = (data || []).filter((m) => m.acknowledged_at === null);
  assert.equal(pending.length, 0, 'backfilled promotion milestones must be acknowledged (no retroactive celebration)');
});
