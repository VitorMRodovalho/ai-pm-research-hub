import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIG = 'supabase/migrations/20260805000164_676_recurring_meeting_rules_foundation.sql';
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SERVICE_KEY
  ? createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })
  : null;

const HUB_COMMS = '9ea82b09-55c6-4cc3-ab7f-178518d0ab47';
const TEST_GRP = '00000000-0000-4000-8000-000000000676';
const TEST_GRP_PAUSED = '00000000-0000-4000-8000-000000000677';
const HORIZON = '2026-08-31';

function utcDow(d) { return new Date(`${d}T12:00:00Z`).getUTCDay(); } // 0=Sun..6=Sat
function daysBetween(a, b) {
  return Math.round((Date.parse(`${a}T00:00:00Z`) - Date.parse(`${b}T00:00:00Z`)) / 86400000);
}

// ---------------------------------------------------------------------------
// Static: the migration ships the canonical model + idempotent generator.
// ---------------------------------------------------------------------------
test('#676 static: migration exists with canonical rule table', () => {
  assert.ok(existsSync(MIG), 'migration file present');
  assert.match(body, /CREATE TABLE IF NOT EXISTS public\.recurring_meeting_rules/);
  assert.match(body, /scope_type\s+text NOT NULL CHECK \(scope_type IN \('tribe','initiative','general','leadership'\)\)/);
  assert.match(body, /frequency\s+text NOT NULL DEFAULT 'weekly' CHECK \(frequency IN \('weekly','biweekly'\)\)/);
  assert.match(body, /anchor_date\s+date NOT NULL/, 'biweekly parity needs an explicit anchor');
  assert.match(body, /day_of_week\s+smallint NOT NULL CHECK \(day_of_week BETWEEN 1 AND 7\)/);
  assert.match(body, /CONSTRAINT rmr_scope_refs CHECK/);
});

test('#676 static: reconcile RPC is idempotent and parity-correct', () => {
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.reconcile_recurring_meeting/);
  // no-duplicate guard
  assert.match(body, /WHERE NOT EXISTS \(\s*SELECT 1 FROM public\.events e\s*WHERE e\.recurrence_group = v_rule\.recurrence_group AND e\.date = v_d/);
  // weekly matches isodow; biweekly steps 14 days from anchor
  assert.match(body, /extract\(isodow FROM g\)::int = v_rule\.day_of_week/);
  assert.match(body, /generate_series\(v_rule\.anchor_date, v_horizon, interval '14 days'\)/);
  // derived slot sync converts ISO -> pg dow
  assert.match(body, /v_slot_dow := \(v_rule\.day_of_week % 7\)/);
  assert.match(body, /ON CONFLICT \(tribe_id, day_of_week\) DO UPDATE SET/);
  // V4 authority gate
  assert.match(body, /Unauthorized: requires manage_platform/);
});

test('#676 static: drift report + reconcile_all + backfill present', () => {
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_recurring_meeting_drift/);
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.reconcile_all_recurring_meetings/);
  assert.match(body, /CREATE UNIQUE INDEX IF NOT EXISTS ux_tribe_meeting_slots_tribe_dow/);
  assert.match(body, /DO \$backfill\$/, 'backfills rules from existing recurrence groups');
  assert.match(body, /DO \$slots\$/, 'syncs derived tribe_meeting_slots');
  assert.match(body, /trg_rmr_audit/, 'recurrence changes are audited');
});

// ---------------------------------------------------------------------------
// Live: backfilled rules, derived slots, generator idempotency + parity.
// ---------------------------------------------------------------------------
test('#676 live: 7 tribe rules + 2 comms rules backfilled with correct cadence', { skip: sb ? false : 'Supabase env required' }, async () => {
  const { data: rules, error } = await sb
    .from('recurring_meeting_rules')
    .select('scope_type, tribe_id, day_of_week, frequency, status, initiative_id, title');
  assert.ifError(error);

  // Exclude synthetic rules created by sibling tests (titled 'TEST …') — the suite runs
  // test files in parallel against the same DB, so the backfilled-rule count must ignore
  // any in-flight test fixtures to stay deterministic.
  const real = (rules ?? []).filter((r) => !String(r.title || '').startsWith('TEST'));
  const tribeRules = real.filter((r) => r.scope_type === 'tribe');
  const commsRules = real.filter((r) => r.scope_type === 'initiative');
  assert.equal(tribeRules.length, 7, 'seven tribe rules');
  assert.equal(commsRules.length, 2, 'two comms/initiative rules');

  // ISO weekday per tribe (matches #630 confirmed cadence)
  const isoByTribe = new Map([[1, 1], [2, 1], [4, 3], [5, 1], [6, 3], [7, 2], [8, 4]]);
  for (const r of tribeRules) {
    assert.equal(r.day_of_week, isoByTribe.get(r.tribe_id), `tribe ${r.tribe_id} ISO weekday`);
    assert.equal(r.frequency, 'weekly', `tribe ${r.tribe_id} is weekly`);
    assert.ok(r.initiative_id, `tribe ${r.tribe_id} rule anchored to an initiative`);
  }
  // exactly one biweekly among the comms rules (Thursday alignment)
  assert.equal(commsRules.filter((r) => r.frequency === 'biweekly').length, 1, 'one biweekly comms rule');
});

test('#676 live: tribe_meeting_slots is a derived cache of the tribe rules', { skip: sb ? false : 'Supabase env required' }, async () => {
  const { data: rules, error: e1 } = await sb
    .from('recurring_meeting_rules')
    .select('tribe_id, day_of_week, time_start, status')
    .eq('scope_type', 'tribe');
  assert.ifError(e1);
  const { data: slots, error: e2 } = await sb
    .from('tribe_meeting_slots')
    .select('tribe_id, day_of_week, time_start, is_active');
  assert.ifError(e2);

  for (const r of rules ?? []) {
    const pgDow = r.day_of_week % 7; // ISO -> pg dow
    const slot = (slots ?? []).find((s) => s.tribe_id === r.tribe_id && s.day_of_week === pgDow);
    assert.ok(slot, `tribe ${r.tribe_id} has a derived slot on pg dow ${pgDow}`);
    assert.equal(slot.time_start, r.time_start, `tribe ${r.tribe_id} slot time matches rule`);
    assert.equal(slot.is_active, r.status === 'active', `tribe ${r.tribe_id} slot active reflects rule status`);
  }
});

test('#676 live: reconcile generates biweekly Thursdays on parity, idempotently', { skip: sb ? false : 'Supabase env required' }, async () => {
  // clean slate for the synthetic group
  await sb.from('events').delete().eq('recurrence_group', TEST_GRP);
  await sb.from('recurring_meeting_rules').delete().eq('recurrence_group', TEST_GRP);

  const { data: rule, error: eIns } = await sb
    .from('recurring_meeting_rules')
    .insert({
      scope_type: 'initiative', initiative_id: HUB_COMMS, title: 'TEST 676 biweekly',
      event_type: 'comms', audience_level: 'initiative', visibility: 'leadership',
      day_of_week: 4, time_start: '19:30', duration_minutes: 60, frequency: 'biweekly',
      anchor_date: '2026-06-11', meeting_link: 'https://example.test/676', recurrence_group: TEST_GRP, status: 'active',
    })
    .select('id').single();
  assert.ifError(eIns);

  try {
    const { data: first, error: e1 } = await sb.rpc('reconcile_recurring_meeting', { p_rule_id: rule.id, p_horizon_end: HORIZON });
    assert.ifError(e1);
    assert.equal(first.created_events, 5, 'first run creates the five future Thursdays');

    const { data: ev1 } = await sb.from('events').select('date').eq('recurrence_group', TEST_GRP);
    for (const e of ev1 ?? []) {
      assert.equal(utcDow(e.date), 4, `${e.date} is a Thursday`);
      assert.equal(daysBetween(e.date, '2026-06-11') % 14, 0, `${e.date} on 14-day parity from anchor`);
    }

    const { data: second, error: e2 } = await sb.rpc('reconcile_recurring_meeting', { p_rule_id: rule.id, p_horizon_end: HORIZON });
    assert.ifError(e2);
    assert.equal(second.created_events, 0, 'second run is a no-op (idempotent, no duplicates)');

    const { count } = await sb.from('events').select('*', { count: 'exact', head: true }).eq('recurrence_group', TEST_GRP);
    assert.equal(count, 5, 'still exactly five events after re-running');
  } finally {
    await sb.from('events').delete().eq('recurrence_group', TEST_GRP);
    await sb.from('recurring_meeting_rules').delete().eq('recurrence_group', TEST_GRP);
  }
});

test('#676 live: paused rule generates no events', { skip: sb ? false : 'Supabase env required' }, async () => {
  await sb.from('events').delete().eq('recurrence_group', TEST_GRP_PAUSED);
  await sb.from('recurring_meeting_rules').delete().eq('recurrence_group', TEST_GRP_PAUSED);

  const { data: rule, error: eIns } = await sb
    .from('recurring_meeting_rules')
    .insert({
      scope_type: 'initiative', initiative_id: HUB_COMMS, title: 'TEST 676 paused',
      event_type: 'comms', audience_level: 'initiative', visibility: 'leadership',
      day_of_week: 2, time_start: '19:30', duration_minutes: 60, frequency: 'weekly',
      anchor_date: '2026-06-16', meeting_link: 'https://example.test/676p', recurrence_group: TEST_GRP_PAUSED, status: 'paused',
    })
    .select('id').single();
  assert.ifError(eIns);

  try {
    const { data: res, error } = await sb.rpc('reconcile_recurring_meeting', { p_rule_id: rule.id, p_horizon_end: HORIZON });
    assert.ifError(error);
    assert.equal(res.created_events, 0, 'paused rule creates nothing');
    const { count } = await sb.from('events').select('*', { count: 'exact', head: true }).eq('recurrence_group', TEST_GRP_PAUSED);
    assert.equal(count, 0, 'no events materialized for a paused rule');
  } finally {
    await sb.from('events').delete().eq('recurrence_group', TEST_GRP_PAUSED);
    await sb.from('recurring_meeting_rules').delete().eq('recurrence_group', TEST_GRP_PAUSED);
  }
});

test('#676 live: drift report surfaces missing future occurrences', { skip: sb ? false : 'Supabase env required' }, async () => {
  const { data, error } = await sb.rpc('get_recurring_meeting_drift', { p_horizon_end: HORIZON });
  assert.ifError(error);
  assert.ok(Array.isArray(data) && data.length >= 9, 'drift report covers all active rules');
  for (const row of data) {
    assert.ok(row.expected_future >= row.future_events, `${row.title}: expected >= materialized`);
    assert.equal(row.missing_future, Math.max(row.expected_future - row.future_events, 0));
  }
});
