/**
 * Contract: #766 PR3 — server-side `first_attendance` + `first_deliverable` milestones.
 *
 * PR3 of the server-side milestones framework (table member_milestones + record_milestone
 * shipped PR1, term_signed PR2). PR3 adds two milestones, each mirroring an existing sibling
 * trigger so the milestone fires on the SAME domain event:
 *   - first_attendance: trigger _trg_record_first_attendance_milestone (AFTER INSERT ON
 *     attendance, WHEN present=true) — mirrors auto_complete_first_meeting.
 *   - first_deliverable: trigger _trg_record_first_deliverable_milestone (AFTER INSERT OR
 *     UPDATE ON tribe_deliverables, body keyed on status='completed') — mirrors
 *     trg_tribe_deliverable_completed_xp. Keyed on status, NOT completed_at (a derived col).
 * Silent backfill (acknowledged_at=now()) runs BEFORE CREATE TRIGGER (race-safe, SPEC §6.3).
 * Invariants AC + AD appended to check_schema_invariants() (29 -> 31), mirroring AA/AB:
 *   - AC_first_attendance_milestone_has_attendance,
 *   - AD_first_deliverable_milestone_has_completed_deliverable.
 *
 * Migration: 20260805000203_first_attendance_first_deliverable_milestones.sql.
 * Cross-ref: docs/specs/SPEC_766_SERVER_SIDE_MILESTONES.md §7 (PR3).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');
const MIG = read('supabase/migrations/20260805000203_first_attendance_first_deliverable_milestones.sql');
const FE = read('src/components/milestones/MilestoneCelebration.tsx');
const LAYOUT = read('src/layouts/BaseLayout.astro');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── Offline: migration shape ───────────────────────────────────────────────────
test('migration: first_attendance trigger is AFTER INSERT, gated WHEN present=true', () => {
  assert.ok(MIG, 'PR3 migration exists');
  assert.match(MIG, /CREATE TRIGGER trg_record_first_attendance_milestone\s+AFTER INSERT ON public\.attendance/);
  assert.match(MIG, /WHEN \(NEW\.present = true\)/);
  assert.match(MIG, /PERFORM public\.record_milestone\(\s*NEW\.member_id, 'first_attendance'/);
});

test('migration: first_deliverable trigger is AFTER INSERT OR UPDATE, body keyed on status=completed (not completed_at)', () => {
  assert.match(MIG, /CREATE TRIGGER trg_record_first_deliverable_milestone\s+AFTER INSERT OR UPDATE ON public\.tribe_deliverables/);
  // firing condition mirrors trg_tribe_deliverable_completed_xp
  assert.match(MIG, /NEW\.status = 'completed'\s+AND \(TG_OP = 'INSERT' OR OLD\.status IS DISTINCT FROM 'completed'\)/);
  assert.match(MIG, /PERFORM public\.record_milestone\(\s*NEW\.assigned_member_id, 'first_deliverable'/);
});

test('migration: both trigger fns are SECURITY DEFINER search_path empty + REVOKEd', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\._trg_record_first_attendance_milestone\(\)/);
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\._trg_record_first_deliverable_milestone\(\)/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._trg_record_first_attendance_milestone\(\) FROM PUBLIC/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._trg_record_first_deliverable_milestone\(\) FROM PUBLIC/);
  assert.equal((MIG.match(/SET search_path = ''/g) || []).length >= 2, true);
});

test('migration: backfills are silent (acknowledged_at=now) and run BEFORE both CREATE TRIGGER', () => {
  const firstBackfill = MIG.indexOf("INSERT INTO public.member_milestones");
  const firstTrigger = MIG.indexOf('CREATE TRIGGER trg_record_first_attendance_milestone');
  const delivTrigger = MIG.indexOf('CREATE TRIGGER trg_record_first_deliverable_milestone');
  assert.ok(firstBackfill > -1 && firstTrigger > -1 && delivTrigger > -1, 'all present');
  assert.ok(firstBackfill < firstTrigger && firstBackfill < delivTrigger, 'backfill precedes CREATE TRIGGER (race-safe, SPEC §6.3)');
  // attendance occurred_at = real check-in moment (COALESCE), not migration time
  assert.match(MIG, /COALESCE\(a\.checked_in_at, a\.created_at, now\(\)\), 'attendance'/);
  // deliverable backfill is keyed on status='completed' (NOT completed_at IS NOT NULL)
  assert.match(MIG, /WHERE td\.status = 'completed' AND td\.assigned_member_id IS NOT NULL/);
  assert.equal((MIG.match(/ON CONFLICT \(member_id, milestone_key\) DO NOTHING/g) || []).length, 2);
});

test('migration: sanity guards assert every eligible member got a milestone', () => {
  assert.match(MIG, /first_attendance backfill sanity FAIL/);
  assert.match(MIG, /first_deliverable backfill sanity FAIL/);
});

test('migration: invariants AC + AD present; AD keys on status=completed (not completed_at)', () => {
  assert.match(MIG, /AC_first_attendance_milestone_has_attendance/);
  assert.match(MIG, /AD_first_deliverable_milestone_has_completed_deliverable/);
  const adBlock = MIG.slice(MIG.indexOf('-- AD (#766 PR3)'));
  const adPredicate = adBlock.slice(0, adBlock.indexOf('FROM drift'));
  assert.match(adPredicate, /td\.status = 'completed'/);
  assert.ok(!/td\.completed_at\s+IS NOT NULL/.test(adPredicate),
    'AD must key on status=completed, not completed_at (the trigger fires on status)');
});

// ── Offline: FE surface ─────────────────────────────────────────────────────────
test('FE: MilestoneCelebration owns first_attendance + first_deliverable (not onboarding/term)', () => {
  assert.ok(FE, 'component exists');
  // OWNED_KEYS grows as later PRs plug in (PR4 promotion, PR5 profile_complete); assert the two
  // PR3 keys are present rather than pinning the exact array (which each later PR would rebump).
  const owned = FE.match(/OWNED_KEYS\s*=\s*\[([^\]]*)\]/);
  assert.ok(owned, 'OWNED_KEYS declared');
  assert.ok(/'first_attendance'/.test(owned[1]) && /'first_deliverable'/.test(owned[1]),
    'first_attendance + first_deliverable are owned by this surface');
  // onboarding_complete / term_signed must not be quoted milestone keys this surface handles
  // (they may still appear in explanatory comments — only the quoted-string forms matter).
  assert.ok(!/'onboarding_complete'/.test(FE), 'onboarding_complete stays owned by OnboardingChecklist');
  assert.ok(!/'term_signed'/.test(FE), 'term_signed stays deferred');
});

test('FE: reads get_my_milestones, dismiss calls acknowledge_milestone, a11y role=status', () => {
  assert.match(FE, /rpc\('get_my_milestones'\)/);
  assert.match(FE, /rpc\('acknowledge_milestone', \{ p_milestone_key/);
  assert.match(FE, /role="status"/);
  assert.match(FE, /aria-live="polite"/);
  // bottom-left to clear the bottom-right HelpFloatingButton
  assert.match(FE, /fixed bottom-4 left-4/);
});

test('FE: island is mounted in BaseLayout', () => {
  assert.match(LAYOUT, /import MilestoneCelebration from/);
  assert.match(LAYOUT, /<MilestoneCelebration client:load lang=\{lang\} \/>/);
});

// ── DB-gated: live behaviour ────────────────────────────────────────────────────
test('DB: check_schema_invariants reports 31 invariants, 0 total violations', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('check_schema_invariants');
  assert.ok(!error, error?.message);
  assert.equal(data.length, 31, `expected 31 invariants, got ${data.length}`);
  const total = data.reduce((s, r) => s + r.violation_count, 0);
  assert.equal(total, 0, 'no invariant may have violations');
});

test('DB: AC + AD present, medium severity, 0 violations', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('check_schema_invariants');
  assert.ok(!error, error?.message);
  for (const name of ['AC_first_attendance_milestone_has_attendance', 'AD_first_deliverable_milestone_has_completed_deliverable']) {
    const inv = data.find((r) => r.invariant_name === name);
    assert.ok(inv, `${name} present`);
    assert.equal(inv.severity, 'medium');
    assert.equal(inv.violation_count, 0, `${name} must have 0 violations`);
  }
});

test('DB: every present-attendance member has a first_attendance milestone', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: att, error: e1 } = await sb.from('attendance').select('member_id').eq('present', true);
  assert.ok(!e1, e1?.message);
  const memberIds = [...new Set((att || []).map((a) => a.member_id).filter(Boolean))];
  const { data: ms, error: e2 } = await sb.from('member_milestones').select('member_id').eq('milestone_key', 'first_attendance');
  assert.ok(!e2, e2?.message);
  const milestoneIds = new Set((ms || []).map((m) => m.member_id));
  const missing = memberIds.filter((id) => !milestoneIds.has(id));
  assert.equal(missing.length, 0, `present-attendance members without a first_attendance milestone: ${missing.join(', ')}`);
});

test('DB: backfilled milestones are acknowledged (silent, not pending)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb
    .from('member_milestones')
    .select('acknowledged_at, milestone_key')
    .in('milestone_key', ['first_attendance', 'first_deliverable'])
    .contains('metadata', { backfill: true });
  assert.ok(!error, error?.message);
  const pending = (data || []).filter((m) => m.acknowledged_at === null);
  assert.equal(pending.length, 0, 'backfilled milestones must be acknowledged (no retroactive celebration)');
});
