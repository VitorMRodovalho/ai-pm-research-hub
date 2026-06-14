import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIG = 'supabase/migrations/20260805000166_676_recurring_meeting_write_path_v4.sql';
const ISLAND = 'src/components/admin/RecurringAgendaIsland.tsx';
const DICTS = ['src/i18n/pt-BR.ts', 'src/i18n/en-US.ts', 'src/i18n/es-LATAM.ts'];
const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SERVICE_KEY
  ? createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })
  : null;

const HUB_COMMS = '9ea82b09-55c6-4cc3-ab7f-178518d0ab47';

test('#676 slice3 static: write RPCs + V4 leader-scoped authority helper', () => {
  const body = read(MIG);
  assert.ok(body, 'migration present');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\._can_manage_recurring_rule/);
  // leader scope reuses the #666 v_initiative_roster role='leader' pattern
  assert.match(body, /v_initiative_roster r[\s\S]*?r\.role = 'leader'/, 'leader = roster role leader');
  assert.match(body, /can_by_member\(p_member_id, 'manage_platform'\)/, 'GP path present');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.update_recurring_meeting_rule/);
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.create_recurring_meeting_rule/);
  // reconcile re-captured with leader-scoped gate
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.reconcile_recurring_meeting/);
  assert.match(body, /requires manage_platform or initiative leadership/);
  // create derives scope from the initiative's legacy_tribe_id (no client-trusted scope)
  assert.match(body, /SELECT legacy_tribe_id INTO v_tribe FROM public\.initiatives/);
  // anon revoked on all three write RPCs
  assert.match(body, /REVOKE ALL ON FUNCTION public\.update_recurring_meeting_rule\(uuid, jsonb\) FROM PUBLIC, anon/);
  assert.match(body, /REVOKE ALL ON FUNCTION public\.create_recurring_meeting_rule\(jsonb\) FROM PUBLIC, anon/);
});

test('#676 slice3 static: island wires edit/create/reconcile to the write RPCs', () => {
  const isl = read(ISLAND);
  assert.match(isl, /rpc\('update_recurring_meeting_rule'/, 'edit calls update RPC');
  assert.match(isl, /rpc\('create_recurring_meeting_rule'/, 'create calls create RPC');
  assert.match(isl, /rpc\('reconcile_recurring_meeting'/, 'reconcile button calls reconcile RPC');
  assert.ok(!/\bclass=/.test(isl), 'uses className (React)');
});

test('#676 slice3 static: write-UI i18n keys parity across 3 dictionaries', () => {
  const KEYS = [
    'comp.recurringAgenda.colActions', 'comp.recurringAgenda.newRule', 'comp.recurringAgenda.reconcileNow',
    'comp.recurringAgenda.edit', 'comp.recurringAgenda.editTitle', 'comp.recurringAgenda.createTitle',
    'comp.recurringAgenda.fInitiative', 'comp.recurringAgenda.fTitle', 'comp.recurringAgenda.fDay',
    'comp.recurringAgenda.fTime', 'comp.recurringAgenda.fDuration', 'comp.recurringAgenda.fFrequency',
    'comp.recurringAgenda.fStatus', 'comp.recurringAgenda.fAnchor', 'comp.recurringAgenda.fLink',
    'comp.recurringAgenda.cancel', 'comp.recurringAgenda.save', 'comp.recurringAgenda.savedEdit',
    'comp.recurringAgenda.savedCreate', 'comp.recurringAgenda.saveError', 'comp.recurringAgenda.reconciled',
    'comp.recurringAgenda.pickInitiative', 'comp.recurringAgenda.writeNote',
  ];
  for (const dict of DICTS) {
    const body = read(dict);
    for (const k of KEYS) assert.ok(body.includes(`'${k}'`), `${dict} missing ${k}`);
  }
});

test('#676 slice3 live: leader-scope authority predicate (real roster leader)', { skip: sb ? false : 'Supabase env required' }, async () => {
  // find a live initiative leader from the canonical roster
  const { data: leaders, error } = await sb
    .from('v_initiative_roster')
    .select('member_id, initiative_id')
    .eq('role', 'leader')
    .not('member_id', 'is', null)
    .limit(1);
  assert.ifError(error);
  if (!leaders || leaders.length === 0) return; // no leaders seeded — skip gracefully
  const { member_id, initiative_id } = leaders[0];

  const { data: canOwn } = await sb.rpc('_can_manage_recurring_rule', { p_member_id: member_id, p_initiative_id: initiative_id });
  assert.equal(canOwn, true, 'leader can manage their own initiative rule');

  // a non-existent member cannot manage that initiative (not GP, not leader)
  const { data: canFake } = await sb.rpc('_can_manage_recurring_rule', {
    p_member_id: '00000000-0000-4000-8000-0000000000aa', p_initiative_id: initiative_id,
  });
  assert.equal(canFake, false, 'unknown member is denied');
});

test('#676 slice3 live: create → update → reconcile happy path (service role)', { skip: sb ? false : 'Supabase env required' }, async () => {
  // create (initiative scope, no tribe slot side-effects)
  const { data: ruleId, error: eCreate } = await sb.rpc('create_recurring_meeting_rule', {
    p_payload: {
      initiative_id: HUB_COMMS, title: 'TEST 676 s3 ct', day_of_week: 3, time_start: '10:00',
      frequency: 'weekly', anchor_date: new Date().toISOString().slice(0, 10), meeting_link: 'https://example.test/ct',
    },
  });
  assert.ifError(eCreate);
  assert.ok(typeof ruleId === 'string', 'create returns new uuid');

  try {
    // update: pause + change link
    const { data: upd, error: eUpd } = await sb.rpc('update_recurring_meeting_rule', {
      p_rule_id: ruleId, p_patch: { status: 'paused', meeting_link: 'https://example.test/ct2' },
    });
    assert.ifError(eUpd);
    assert.equal(upd.status, 'paused');

    // reconcile while paused → 0 events
    const { data: rec0 } = await sb.rpc('reconcile_recurring_meeting', { p_rule_id: ruleId });
    assert.equal(rec0.created_events, 0, 'paused rule generates nothing');

    // reactivate + reconcile → some events
    await sb.rpc('update_recurring_meeting_rule', { p_rule_id: ruleId, p_patch: { status: 'active' } });
    const { data: rec1 } = await sb.rpc('reconcile_recurring_meeting', { p_rule_id: ruleId });
    assert.ok(rec1.created_events >= 1, 'active reconcile generates events');

    // invalid patch is rejected
    const { error: eBad } = await sb.rpc('update_recurring_meeting_rule', { p_rule_id: ruleId, p_patch: { status: 'bogus' } });
    assert.ok(eBad, 'invalid status rejected');
  } finally {
    // cleanup events + rule
    const { data: ruleRow } = await sb.from('recurring_meeting_rules').select('recurrence_group').eq('id', ruleId).single();
    if (ruleRow?.recurrence_group) await sb.from('events').delete().eq('recurrence_group', ruleRow.recurrence_group);
    await sb.from('recurring_meeting_rules').delete().eq('id', ruleId);
  }
});
