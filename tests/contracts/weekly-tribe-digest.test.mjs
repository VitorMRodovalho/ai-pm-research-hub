/**
 * p162 Track B' G5 — weekly-tribe-digest contract.
 *
 * Static (always run): both migrations 20260655 (g2a) and 20260656 (g2b) declare
 * the documentation-hygiene shape — ata_pending recurrence-grouped, attendance_pending,
 * champion_pending — plus cycle scoping, COALESCE for type=geral without initiative,
 * extended v_has_signal in the cron, and invariants O+P.
 *
 * Live DB (skipped without SUPABASE_URL+SERVICE_ROLE_KEY): get_weekly_tribe_digest
 * returns the expected jsonb shape for an active tribe.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const G2A = resolve(
  process.cwd(),
  'supabase/migrations/20260655000000_p162_track_b_prime_g2a_tribe_digest_3_sections.sql'
);
const G2B = resolve(
  process.cwd(),
  'supabase/migrations/20260656000000_p162_track_b_prime_g2b_cron_signal_invariants_o_p.sql'
);
const g2aSql = readFileSync(G2A, 'utf8');
const g2bSql = readFileSync(G2B, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

// ===== Static tests =====

test('Track B G2a: get_weekly_tribe_digest declares ata_pending key', () => {
  assert.ok(
    /'ata_pending'\s*,/i.test(g2aSql),
    'aggregates must include ata_pending entry'
  );
  assert.ok(
    /count_groups[\s\S]*count_events[\s\S]*top_groups/i.test(g2aSql),
    'ata_pending payload must expose count_groups, count_events, top_groups'
  );
  assert.ok(
    /is_recurring[\s\S]*occurrence_count[\s\S]*sample_title[\s\S]*latest_event_id[\s\S]*latest_date/i.test(g2aSql),
    'ata_pending top_groups items must expose is_recurring, occurrence_count, sample_title, latest_event_id, latest_date'
  );
});

test('Track B G2a: get_weekly_tribe_digest declares attendance_pending key', () => {
  assert.ok(/'attendance_pending'\s*,/i.test(g2aSql), 'aggregates must include attendance_pending entry');
  // attendance_pending shape: { count, top_events[] }
  const attBlock = g2aSql.split(/'attendance_pending'/i)[1] || '';
  assert.ok(/'count'/i.test(attBlock), 'attendance_pending payload must expose count');
  assert.ok(/'top_events'/i.test(attBlock), 'attendance_pending payload must expose top_events');
});

test('Track B G2a: get_weekly_tribe_digest declares champion_pending key', () => {
  assert.ok(/'champion_pending'\s*,/i.test(g2aSql), 'aggregates must include champion_pending entry');
  const champBlock = g2aSql.split(/'champion_pending'/i)[1] || '';
  assert.ok(/'count'/i.test(champBlock), 'champion_pending payload must expose count');
  assert.ok(/'top_events'/i.test(champBlock), 'champion_pending payload must expose top_events');
});

test('Track B G2a: cycle-scoped via v_cycle_start / v_cycle_end', () => {
  assert.ok(
    /v_cycle_start\s+timestamptz/i.test(g2aSql) && /v_cycle_end\s+timestamptz/i.test(g2aSql),
    'must declare v_cycle_start/v_cycle_end timestamptz vars'
  );
  assert.ok(
    /is_current\s*=\s*true/i.test(g2aSql),
    'must read current cycle from cycles table'
  );
  assert.ok(
    /e\.date::timestamptz\s*>=\s*v_cycle_start/i.test(g2aSql),
    'event filters must respect cycle_start lower bound'
  );
});

test('Track B G2a: COALESCE for type=geral events without initiative_id', () => {
  // Allow flexible whitespace (quote and join newlines into a single line).
  const flat = g2aSql.replace(/\s+/g, ' ');
  assert.ok(
    /e\.initiative_id\s*=\s*v_initiative_id\s+OR\s+\(e\.type\s*=\s*'geral'\s+AND\s+e\.initiative_id\s+IS\s+NULL\)/i.test(flat),
    "must allow type=geral events with NULL initiative via COALESCE-style OR clause"
  );
});

test('Track B G2a: meeting_artifacts.is_published gates ata_pending NOT EXISTS', () => {
  assert.ok(
    /NOT\s+EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+public\.meeting_artifacts\s+ma\s+WHERE\s+ma\.event_id\s*=\s*e\.id\s+AND\s+ma\.is_published\s*=\s*true\s*\)/i.test(g2aSql),
    'ata_pending must filter events with no published meeting_artifacts'
  );
});

test('Track B G2a: champions_awarded status=active gates champion_pending', () => {
  // champion_pending uses NOT EXISTS on champions_awarded with context_kind='event' AND status='active'
  const flat = g2aSql.replace(/\s+/g, ' ');
  assert.ok(
    /NOT\s+EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+public\.champions_awarded\s+ca\s+WHERE\s+ca\.context_kind\s*=\s*'event'\s+AND\s+ca\.context_id\s*=\s*e\.id\s+AND\s+ca\.status\s*=\s*'active'\s*\)/i.test(flat),
    'champion_pending must filter events with no active champions_awarded'
  );
});

test('Track B G2a: SECURITY DEFINER + search_path hardening', () => {
  assert.ok(/SECURITY\s+DEFINER/i.test(g2aSql), 'RPC must be SECURITY DEFINER');
  assert.ok(/SET\s+search_path\s+TO\s+''/i.test(g2aSql), "search_path must be hardened (empty)");
});

test('Track B G2b: cron v_has_signal includes 3 new aggregates', () => {
  // The cron checks v_has_signal across cards aggregates AND now ata/attendance/champion pending.
  const flat = g2bSql.replace(/\s+/g, ' ');
  assert.ok(/v_has_signal/i.test(g2bSql), 'cron must declare v_has_signal');
  // The cron uses ata_pending.count_events (the leaf event count, not the
  // recurrence-grouped count) so a single recurring series with N occurrences
  // still triggers a digest. Tests should match production semantics.
  assert.ok(
    /ata_pending'\s*->>\s*'count_events'/i.test(g2bSql),
    'v_has_signal expression must consult ata_pending.count_events'
  );
  assert.ok(
    /attendance_pending'\s*->>\s*'count'/i.test(g2bSql),
    'v_has_signal expression must consult attendance_pending.count'
  );
  assert.ok(
    /champion_pending'\s*->>\s*'count'/i.test(g2bSql),
    'v_has_signal expression must consult champion_pending.count'
  );
});

test('Track B G2b: invariant O (meeting_artifact event orphan) declared', () => {
  assert.ok(
    /O_meeting_artifact_event_orphan/i.test(g2bSql),
    'must declare O_meeting_artifact_event_orphan invariant'
  );
});

test('Track B G2b: invariant P (tribe-initiative bridge complete) declared', () => {
  assert.ok(
    /P_tribe_initiative_bridge_complete/i.test(g2bSql),
    'must declare P_tribe_initiative_bridge_complete invariant'
  );
});

// ===== Live DB tests =====

test('Live: get_weekly_tribe_digest returns expected shape for active tribe', { skip: !canRun && skipMsg }, async () => {
  const tribesRes = await fetch(
    `${SUPABASE_URL}/rest/v1/tribes?select=id&is_active=eq.true&limit=1`,
    { headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` } }
  );
  const tribes = await tribesRes.json();
  assert.ok(Array.isArray(tribes) && tribes.length > 0, 'Need ≥1 active tribe for live shape test');

  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/get_weekly_tribe_digest`, {
    method: 'POST',
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ p_tribe_id: tribes[0].id }),
  });
  assert.equal(res.status, 200, `RPC must return 200 (got ${res.status})`);
  const body = await res.json();
  assert.ok(body && typeof body === 'object', 'response must be object');
  assert.ok('aggregates' in body, 'response must have aggregates');
  const agg = body.aggregates || {};

  // 8 card-based aggregates (pre-existing + tribe_health_pct)
  for (const k of [
    'active_members',
    'cards_overdue_total',
    'cards_due_next_7d',
    'cards_without_assignee',
    'cards_without_due_date',
    'cards_completed_window',
    'tribe_health_pct',
    'members_with_overdue_cards',
  ]) {
    assert.ok(k in agg, `aggregates must contain ${k}`);
  }

  // 3 documentation-hygiene aggregates (G2a additions)
  assert.ok(agg.ata_pending && typeof agg.ata_pending === 'object', 'aggregates.ata_pending must be object');
  assert.ok('count_groups' in agg.ata_pending, 'ata_pending.count_groups required');
  assert.ok('count_events' in agg.ata_pending, 'ata_pending.count_events required');
  assert.ok(Array.isArray(agg.ata_pending.top_groups), 'ata_pending.top_groups must be array');

  assert.ok(agg.attendance_pending && typeof agg.attendance_pending === 'object', 'aggregates.attendance_pending must be object');
  assert.ok('count' in agg.attendance_pending, 'attendance_pending.count required');
  assert.ok(Array.isArray(agg.attendance_pending.top_events), 'attendance_pending.top_events must be array');

  assert.ok(agg.champion_pending && typeof agg.champion_pending === 'object', 'aggregates.champion_pending must be object');
  assert.ok('count' in agg.champion_pending, 'champion_pending.count required');
  assert.ok(Array.isArray(agg.champion_pending.top_events), 'champion_pending.top_events must be array');
});

test('Live: get_weekly_tribe_digest 404 for invalid tribe id raises', { skip: !canRun && skipMsg }, async () => {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/get_weekly_tribe_digest`, {
    method: 'POST',
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ p_tribe_id: 999999 }),
  });
  // SECURITY DEFINER + RAISE EXCEPTION → PostgREST returns 4xx with the exception message.
  assert.ok(res.status >= 400 && res.status < 500, `expected 4xx for invalid tribe (got ${res.status})`);
  const body = await res.json();
  assert.ok(
    String(body.message || body.error || '').toLowerCase().includes('tribe not found'),
    `error message must mention tribe not found; got ${JSON.stringify(body)}`
  );
});
