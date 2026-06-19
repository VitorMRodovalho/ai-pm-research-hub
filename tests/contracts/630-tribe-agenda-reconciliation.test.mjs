import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIG = 'supabase/migrations/20260613150200_630_reconcile_tribe_weekly_events_july.sql';
const MIG_T4 = 'supabase/migrations/20260613150634_630_reconcile_t4_weekly_events_july.sql';
const MIG_COMMS = 'supabase/migrations/20260613151535_630_seed_comms_alignment_recurring_events_july.sql';
const MIG_COMMS_PARITY = 'supabase/migrations/20260613152719_630_correct_comms_biweekly_parity_june11_anchor.sql';
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const bodyT4 = existsSync(MIG_T4) ? readFileSync(MIG_T4, 'utf8') : '';
const bodyComms = existsSync(MIG_COMMS) ? readFileSync(MIG_COMMS, 'utf8') : '';
const bodyCommsParity = existsSync(MIG_COMMS_PARITY) ? readFileSync(MIG_COMMS_PARITY, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SERVICE_KEY
  ? createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })
  : null;

test('#630 static: migration reconciles confirmed tribe slots and leaves T4 untouched', () => {
  assert.ok(existsSync(MIG), 'migration exists');
  for (const fragment of [
    "(1, 1, TIME '19:00', TIME '21:00', 120",
    "(2, 1, TIME '19:30', TIME '21:00',  90",
    "(5, 1, TIME '18:00', TIME '19:30',  90",
    "(6, 3, TIME '18:30', TIME '20:00',  90",
    "(7, 2, TIME '20:00', TIME '21:00',  60",
    "(8, 4, TIME '20:30', TIME '22:00',  90",
  ]) {
    assert.ok(body.includes(fragment), `missing confirmed slot fragment: ${fragment}`);
  }
  assert.ok(!/\(4,\s/.test(body), 'T4 must remain untouched until operational confirmation');
  assert.match(body, /AND e\.type = 'tribo'/, 'inserts/updates must preserve tribe event categorization');
  assert.match(body, /JOIN public\.initiatives i ON i\.legacy_tribe_id = target\.tribe_id AND i\.kind = 'research_tribe'/);
  assert.match(body, /DATE '2026-06-13'/);
  assert.match(body, /v_end_date date := DATE '2026-07-31'/);
});

test('#630 static: T4 follow-up migration reconciles confirmed Wednesday slot', () => {
  assert.ok(existsSync(MIG_T4), 'T4 migration exists');
  assert.match(bodyT4, /v_tribe_id integer := 4/);
  assert.match(bodyT4, /v_day_of_week integer := 3/);
  assert.match(bodyT4, /v_time_start time := TIME '18:00'/);
  assert.match(bodyT4, /v_time_end time := TIME '20:00'/);
  assert.match(bodyT4, /v_duration_minutes integer := 120/);
  assert.match(bodyT4, /https:\/\/meet\.google\.com\/kfv-qzqf-ejn/);
  assert.match(bodyT4, /e\.type = 'tribo'/);
  assert.match(bodyT4, /i\.legacy_tribe_id = v_tribe_id/);
});

test('#630 static: comms initiative migration seeds weekly Tuesday and biweekly Thursday alignments', () => {
  assert.ok(existsSync(MIG_COMMS), 'comms migration exists');
  assert.match(bodyComms, /v_initiative_id uuid := '9ea82b09-55c6-4cc3-ab7f-178518d0ab47'/);
  assert.match(bodyComms, /Alinhamento Comunicação \| Núcleo IA/);
  assert.match(bodyComms, /https:\/\/meet\.google\.com\/nwg-nrwx-cqb/);
  assert.match(bodyComms, /generate_series\(DATE '2026-06-16', DATE '2026-07-31', INTERVAL '7 days'\)/);
  assert.match(bodyComms, /generate_series\(DATE '2026-06-18', DATE '2026-07-31', INTERVAL '14 days'\)/);
  assert.match(bodyComms, /'comms'/);
  assert.match(bodyComms, /'initiative'/);
});

test('#630 static: comms parity correction anchors Thursday biweekly cadence on 2026-06-11', () => {
  assert.ok(existsSync(MIG_COMMS_PARITY), 'comms parity correction migration exists');
  assert.match(bodyCommsParity, /2026-06-11/);
  assert.match(bodyCommsParity, /DATE '2026-06-18', DATE '2026-07-02', DATE '2026-07-16', DATE '2026-07-30'/);
  assert.match(bodyCommsParity, /generate_series\(DATE '2026-06-25', DATE '2026-07-31', INTERVAL '14 days'\)/);
  assert.match(bodyCommsParity, /COALESCE\(e\.status, 'scheduled'\) = 'scheduled'/);
});

test('#630 live: confirmed tribes have seven linked weekly tribe events through July', { skip: sb ? false : 'Supabase env required' }, async () => {
  const expected = new Map([
    [1, { day: 1, count: 7 }],
    [2, { day: 1, count: 7 }],
    [4, { day: 3, count: 7 }],
    [5, { day: 1, count: 7 }],
    [6, { day: 3, count: 7 }],
    [7, { day: 2, count: 7 }],
    [8, { day: 4, count: 7 }],
  ]);

  const { data: initiatives, error: e1 } = await sb
    .from('initiatives')
    .select('id, legacy_tribe_id, kind')
    .in('legacy_tribe_id', [...expected.keys()])
    .eq('kind', 'research_tribe');
  assert.ifError(e1);

  const byInitiative = new Map((initiatives ?? []).map((initiative) => [initiative.id, initiative.legacy_tribe_id]));
  const { data: events, error: e2 } = await sb
    .from('events')
    .select('id, initiative_id, date, type, status')
    .in('initiative_id', [...byInitiative.keys()])
    .eq('type', 'tribo')
    .gte('date', '2026-06-13')
    .lte('date', '2026-07-31');
  assert.ifError(e2);

  for (const [tribeId, spec] of expected) {
    const rows = (events ?? []).filter((event) => {
      const eventDate = new Date(`${event.date}T12:00:00Z`);
      return byInitiative.get(event.initiative_id) === tribeId
        && eventDate.getUTCDay() === spec.day;
    });
    // #803 (BUG-630.A): assert the seeded weekly cadence by counting DISTINCT
    // dates on the expected weekday in ANY status. A legitimately cancelled
    // instance keeps its row, so it still counts as a planned slot. The window
    // holds exactly `spec.count` occurrences of the weekday, so `>= spec.count`
    // distinct dates proves full coverage with no gap — and stays green through
    // legitimate cancellations/reschedules, unlike the old "exactly N active" gate.
    const distinctDates = new Set(rows.map((event) => event.date));
    assert.ok(
      distinctDates.size >= spec.count,
      `tribe ${tribeId} weekly grid: expected >= ${spec.count} distinct weekday-${spec.day} slots, got ${distinctDates.size}`,
    );
    assert.ok(rows.every((event) => event.type === 'tribo'), `tribe ${tribeId} all events type=tribo`);
    assert.ok(rows.every((event) => event.initiative_id), `tribe ${tribeId} all events linked to initiative`);
  }
});

test('#630 live: comms workgroup has Tuesday weekly and Thursday biweekly alignments through July', { skip: sb ? false : 'Supabase env required' }, async () => {
  const { data: events, error } = await sb
    .from('events')
    .select('title, initiative_id, date, time_start, duration_minutes, type, status, meeting_link')
    .eq('initiative_id', '9ea82b09-55c6-4cc3-ab7f-178518d0ab47')
    .like('title', 'Alinhamento Comunicação | Núcleo IA%')
    .gte('date', '2026-06-13')
    .lte('date', '2026-07-31');
  assert.ifError(error);

  // #803 (BUG-630.A): assert the expected anchor dates are PRESENT in any status
  // (a cancelled instance keeps its row + date), rather than an exact equality
  // over active rows that one legitimate cancellation would break.
  const allEvents = events ?? [];
  const tuesdayDates = new Set(
    allEvents.filter((event) => event.title.endsWith('(terça)')).map((event) => event.date),
  );
  const thursdayDates = new Set(
    allEvents.filter((event) => event.title.endsWith('(quinta quinzenal)')).map((event) => event.date),
  );
  for (const date of [
    '2026-06-16', '2026-06-23', '2026-06-30',
    '2026-07-07', '2026-07-14', '2026-07-21', '2026-07-28',
  ]) {
    assert.ok(tuesdayDates.has(date), `comms Tuesday weekly alignment missing ${date}`);
  }
  for (const date of ['2026-06-25', '2026-07-09', '2026-07-23']) {
    assert.ok(thursdayDates.has(date), `comms Thursday biweekly alignment missing ${date}`);
  }
  for (const event of allEvents) {
    assert.equal(event.type, 'comms');
    assert.equal(event.time_start, '19:30:00');
    assert.equal(event.duration_minutes, 60);
    assert.equal(event.meeting_link, 'https://meet.google.com/nwg-nrwx-cqb');
  }
});
