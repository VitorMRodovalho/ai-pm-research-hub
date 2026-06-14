import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// #676 Slice 5 lock — the homepage agenda must read from the canonical source, not a
// hardcoded cadence or a divergent slots table:
//   - general meeting: get_next_general_meeting (derived from `events`, type='geral')
//   - tribe weekly schedule: tribe_meeting_slots, which #676 made a DERIVED CACHE of the
//     canonical recurring_meeting_rules (kept in sync by reconcile/update).
// This test locks both paths so a future refactor can't regress to a hardcoded cadence.
const SECTION = 'src/components/sections/WeeklyScheduleSection.astro';
const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SERVICE_KEY
  ? createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })
  : null;

test('#676 slice5 static: homepage reads canonical sources (events RPC + derived slots)', () => {
  const body = read(SECTION);
  assert.ok(body, 'WeeklyScheduleSection present');
  assert.match(body, /rpc\('get_next_general_meeting'\)/, 'general meeting via the events-derived RPC');
  assert.match(body, /from\('tribe_meeting_slots'\)/, 'tribe schedule reads the derived slots cache');
  // the load-bearing invariant comment must stay (events, not a hardcoded cadence string)
  assert.match(body, /events table instead of a hardcoded cadence/i, 'documents the canonical-source invariant');
});

test('#676 slice5 live: get_next_general_meeting is derived from a real geral event', { skip: sb ? false : 'Supabase env required' }, async () => {
  const { data, error } = await sb.rpc('get_next_general_meeting');
  assert.ok(!error, `rpc should not error: ${error?.message}`);
  if (data && data.date) {
    const { data: ev } = await sb
      .from('events')
      .select('id, type, initiative_id, date')
      .eq('type', 'geral')
      .is('initiative_id', null)
      .eq('date', data.date)
      .limit(1);
    assert.ok(Array.isArray(ev) && ev.length === 1, 'the returned date maps to a real geral event (not hardcoded)');
  }
});

test('#676 slice5 live: homepage tribe slots reflect the canonical rules (derived cache)', { skip: sb ? false : 'Supabase env required' }, async () => {
  const { data: rules, error: e1 } = await sb
    .from('recurring_meeting_rules')
    .select('tribe_id, day_of_week, time_start, status, title')
    .eq('scope_type', 'tribe');
  assert.ifError(e1);
  const { data: slots, error: e2 } = await sb
    .from('tribe_meeting_slots')
    .select('tribe_id, day_of_week, time_start, is_active');
  assert.ifError(e2);

  // every active, non-synthetic tribe rule must have a matching slot the homepage can read
  for (const r of (rules ?? []).filter((x) => x.status === 'active' && !String(x.title || '').startsWith('TEST'))) {
    const pgDow = r.day_of_week % 7; // ISO -> pg dow used by tribe_meeting_slots
    const slot = (slots ?? []).find((s) => s.tribe_id === r.tribe_id && s.day_of_week === pgDow);
    assert.ok(slot, `tribe ${r.tribe_id} has a homepage-readable derived slot`);
    assert.equal(slot.time_start, r.time_start, `tribe ${r.tribe_id} slot time tracks the canonical rule`);
  }
});
