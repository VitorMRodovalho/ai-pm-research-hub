/**
 * #1103 — role-scoped onboarding steps (tribe_leader-specific journey).
 *
 * onboarding_steps gains applies_to_role text[] (NULL = all roles). 4 leader steps
 * (leader_refine_theme/roadmap/capture_video/review_tribe) are scoped to
 * {tribe_leader}. Every seed/read path must filter by role via the canonical
 * predicate onboarding_step_applies(applies_to_role, member_role) — otherwise the
 * leader steps leak to every member (researchers included), inflating denominators
 * and blocking researcher "all_complete".
 *
 * Offline: static source-contract on the migration + the OnboardingChecklist fallback.
 * DB-aware (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY): live predicate + per-role counts.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const read = (rel) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');

const MIG = read('../../supabase/migrations/20260805000339_1103_leader_onboarding_role_scoped_steps.sql');
const CHECKLIST = read('../../src/components/onboarding/OnboardingChecklist.tsx');

const LEADER_STEPS = ['leader_refine_theme', 'leader_roadmap', 'leader_capture_video', 'leader_review_tribe'];
// Every function that reads onboarding_steps for seeding/counting/completion must
// apply the role predicate. consume_onboarding_token is intentionally excluded
// (it references selection_cycles.onboarding_steps jsonb, not the table).
const ROLE_AWARE_FNS = [
  'get_my_onboarding',
  'approve_selection_application',
  'get_onboarding_dashboard',
  'get_candidate_onboarding_progress',
  '_trg_record_onboarding_complete_milestone',
  'complete_onboarding_step',
];

// ───────────────────────── Offline: migration contract ─────────────────────────

test('1103: onboarding_steps gains applies_to_role text[]', () => {
  assert.match(MIG, /add column if not exists applies_to_role text\[\]/i);
});

test('1103: canonical predicate onboarding_step_applies exists (NULL = all roles)', () => {
  assert.match(MIG, /create or replace function public\.onboarding_step_applies\(/i);
  assert.match(MIG, /p_applies_to_role is null/i);
});

test('1103: the 4 leader steps are seeded scoped to {tribe_leader}', () => {
  for (const step of LEADER_STEPS) {
    assert.match(MIG, new RegExp(`'${step}'`), `${step} missing from seed`);
  }
  // each leader step row ends with ARRAY['tribe_leader']
  const scoped = MIG.match(/ARRAY\['tribe_leader'\]/g) ?? [];
  assert.ok(scoped.length >= LEADER_STEPS.length, `expected >=${LEADER_STEPS.length} ARRAY['tribe_leader'], got ${scoped.length}`);
  assert.match(MIG, /on conflict \(id\) do nothing/i, 'seed must be idempotent');
});

test('1103: every role-aware function is rewritten AND applies the predicate', () => {
  for (const fn of ROLE_AWARE_FNS) {
    assert.match(MIG, new RegExp(`create or replace function public\\.${fn}\\(`, 'i'), `${fn} not rewritten`);
  }
  // predicate is referenced at least once per role-aware function (6+ call sites;
  // get_my_onboarding alone applies it 4×)
  const calls = MIG.match(/onboarding_step_applies\(/g) ?? [];
  // 1 definition + >= ROLE_AWARE_FNS.length call sites
  assert.ok(calls.length >= ROLE_AWARE_FNS.length + 1, `too few predicate references: ${calls.length}`);
});

test('1103: consume_onboarding_token is NOT rewritten (false positive — jsonb column, not the table)', () => {
  assert.doesNotMatch(MIG, /create or replace function public\.consume_onboarding_token\(/i);
});

// ───────────────────────── Offline: frontend fallback ─────────────────────────

test('1103: OnboardingChecklist gives non-bespoke (leader) steps a generic CTA — no dead-ends', () => {
  assert.match(CHECKLIST, /BESPOKE_CTA_STEPS\s*=\s*new Set/);
  assert.match(CHECKLIST, /!BESPOKE_CTA_STEPS\.has\(s\.step_id\)/);
  // the fallback both links to the tribe and offers mark-done
  assert.match(CHECKLIST, /completeStep\(s\.step_id\)/);
});

// ───────────────────────── DB-aware: live predicate + counts ─────────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('1103 runtime: predicate scopes leader steps to tribe_leader', { skip: dbGated ? false : skipMsg }, async () => {
  const { createClient } = await import('@supabase/supabase-js');
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  const applies = async (roleArr, memberRole) => {
    const { data, error } = await sb.rpc('onboarding_step_applies', {
      p_applies_to_role: roleArr, p_member_role: memberRole,
    });
    assert.ok(!error, error?.message);
    return data;
  };

  assert.equal(await applies(null, 'researcher'), true, 'NULL applies to all roles');
  assert.equal(await applies(['tribe_leader'], 'researcher'), false, 'leader step hidden from researcher');
  assert.equal(await applies(['tribe_leader'], 'tribe_leader'), true, 'leader step shown to leader');
});

test('1103 runtime: researcher sees the base steps only; tribe_leader sees base + leader steps', { skip: dbGated ? false : skipMsg }, async () => {
  const { createClient } = await import('@supabase/supabase-js');
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  const { data: steps, error } = await sb
    .from('onboarding_steps')
    .select('id, is_required, applies_to_role');
  assert.ok(!error, error?.message);

  const applies = (row, role) => row.applies_to_role == null || row.applies_to_role.includes(role);
  const required = steps.filter((s) => s.is_required);
  const researcherCount = required.filter((s) => applies(s, 'researcher')).length;
  const leaderCount = required.filter((s) => applies(s, 'tribe_leader')).length;

  assert.ok(researcherCount >= 5, `researcher base steps present (${researcherCount})`);
  assert.equal(leaderCount, researcherCount + LEADER_STEPS.length, 'leader = base + 4 leader steps');
  // the 4 leader steps exist and are all scoped
  for (const step of LEADER_STEPS) {
    const row = steps.find((s) => s.id === step);
    assert.ok(row, `${step} seeded`);
    assert.deepEqual(row.applies_to_role, ['tribe_leader'], `${step} scoped to tribe_leader`);
  }
});
