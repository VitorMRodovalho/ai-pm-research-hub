/**
 * #785 follow-up — confidential gate on the event / roster / stats read RPCs that
 * PR-3 (20260805000233) missed. A non-engaged member could read a confidential
 * initiative's roster (get_initiative_members), stats (get_initiative_stats),
 * meetings (get_initiative_events_timeline / get_meeting_preparation /
 * get_events_with_attendance / list_meetings_with_notes) and event detail
 * (get_event_detail). Each now calls public.rls_can_see_initiative(...).
 *
 * Static (offline) assertions: every targeted RPC's CREATE block in the two
 * follow-up migrations applies the gate. The 4-identity behavioural proof
 * (non-engaged blocked everywhere; engaged committee leaders + GP keep access;
 * standard initiatives unchanged) was validated live in ROLLBACK transactions
 * during development; it is not replayed here because the harness has no
 * per-user JWT path (service_role sets auth.uid() = NULL).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const MIG1 = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260805000236_p785_gate_event_read_rpcs_confidential.sql'),
  'utf8',
);
const MIG2 = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260805000237_p785_gate_event_read_rpcs_confidential_part2.sql'),
  'utf8',
);

/** Slice the CREATE OR REPLACE block for a given function out of the migration text. */
function fnBlock(sql, name) {
  const start = sql.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  if (start === -1) return null;
  const next = sql.indexOf('CREATE OR REPLACE FUNCTION public.', start + 1);
  return sql.slice(start, next === -1 ? undefined : next);
}

const PART1 = ['get_initiative_members', 'get_initiative_stats', 'get_initiative_events_timeline', 'get_event_detail'];
const PART2 = ['get_meeting_preparation', 'get_events_with_attendance', 'list_meetings_with_notes'];

for (const name of PART1) {
  test(`#785 follow-up: ${name} applies rls_can_see_initiative (mig 236)`, () => {
    const block = fnBlock(MIG1, name);
    assert.ok(block, `${name} must be CREATE OR REPLACE'd in migration 236`);
    assert.ok(
      block.includes('rls_can_see_initiative'),
      `${name} must call rls_can_see_initiative (confidential gate)`,
    );
  });
}

for (const name of PART2) {
  test(`#785 follow-up: ${name} applies rls_can_see_initiative (mig 237)`, () => {
    const block = fnBlock(MIG2, name);
    assert.ok(block, `${name} must be CREATE OR REPLACE'd in migration 237`);
    assert.ok(
      block.includes('rls_can_see_initiative'),
      `${name} must call rls_can_see_initiative (confidential gate)`,
    );
  });
}

test('#785 follow-up: get_event_detail keeps the engaged-confidential bypass for gp_only/leadership', () => {
  const block = fnBlock(MIG1, 'get_event_detail');
  assert.ok(block.includes('v_engaged_confidential'), 'must compute engaged-confidential membership');
  assert.ok(block.includes("i.visibility = 'confidential'"), 'bypass must be scoped to confidential initiatives');
  assert.ok(block.includes('gp_only') && block.includes('leadership'), 'both visibility tiers must honour the bypass');
});

test('#785 follow-up: both migrations reload the PostgREST schema cache', () => {
  assert.ok(/NOTIFY pgrst/.test(MIG1), 'mig 236 must NOTIFY pgrst');
  assert.ok(/NOTIFY pgrst/.test(MIG2), 'mig 237 must NOTIFY pgrst');
});
