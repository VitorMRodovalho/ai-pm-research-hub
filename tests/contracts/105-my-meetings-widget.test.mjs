/**
 * #105 — member self-service "minhas reuniões" widget.
 *
 * Migration 20260805000330 adds get_my_meetings (member-scoped list backing the workspace widget).
 * The widget itself lives in MyMeetingsIsland, mounted + revealed in workspace.astro. This locks:
 *   - the RPC is member-scoped via auth.uid() (no p_member_id → no IDOR), fail-closed;
 *   - scoping mirrors get_near_events (own tribe + general events) + the #785 confidential gate;
 *   - cancelled events are excluded; per-caller attendance is joined (present/excused);
 *   - grants: authenticated only (REVOKE public/anon);
 *   - the widget reuses register_own_presence for self-mark (HONOURS the 48h check-in policy) —
 *     it must NOT bypass via mark_member_present;
 *   - the widget is mounted and revealed for all members in workspace.
 *
 * Source-contract assertions run offline (no DB env needed).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const MIG = readFileSync(
  fileURLToPath(new URL('../../supabase/migrations/20260805000330_105_get_my_meetings.sql', import.meta.url)),
  'utf8',
);
const ISLAND = readFileSync(
  fileURLToPath(new URL('../../src/components/workspace/MyMeetingsIsland.tsx', import.meta.url)),
  'utf8',
);
const WORKSPACE = readFileSync(
  fileURLToPath(new URL('../../src/pages/workspace.astro', import.meta.url)),
  'utf8',
);

test('105: get_my_meetings is member-scoped via auth.uid() (no p_member_id, fail-closed)', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.get_my_meetings\(/, 'RPC defined');
  assert.match(MIG, /WHERE m\.auth_id = auth\.uid\(\)/, 'caller derived from auth.uid()');
  assert.doesNotMatch(MIG, /p_member_id/, 'no p_member_id param → no IDOR surface');
  assert.match(MIG, /RAISE EXCEPTION 'Forbidden: authentication required'/, 'fail-closed for non-members');
});

test('105: scoping mirrors get_near_events (own tribe + general) + confidential gate', () => {
  assert.match(MIG, /e\.initiative_id IS NULL OR i\.legacy_tribe_id = v_tribe_id/, 'general + own-tribe scope');
  assert.match(MIG, /public\.rls_can_see_initiative\(e\.initiative_id\)/, '#785 confidential gate applied');
  assert.match(MIG, /e\.status <> 'cancelled'/, 'cancelled events excluded');
  assert.match(MIG, /LEFT JOIN public\.attendance a ON a\.event_id = e\.id AND a\.member_id = v_member_id/, 'per-caller attendance join');
});

test('105: hardened grants (authenticated only; REVOKE public/anon)', () => {
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.get_my_meetings\(integer, integer\) FROM public, anon/, 'revoke public/anon');
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.get_my_meetings\(integer, integer\) TO authenticated/, 'grant authenticated');
});

test('105: widget reads get_my_meetings and self-marks via register_own_presence (48h policy honoured)', () => {
  assert.match(ISLAND, /rpc\('get_my_meetings'/, 'widget calls get_my_meetings');
  assert.match(ISLAND, /rpc\('register_own_presence'/, 'self-mark via canonical check-in RPC');
  assert.doesNotMatch(ISLAND, /mark_member_present/, 'must NOT bypass the 48h policy via mark_member_present');
  assert.match(ISLAND, /withinCheckinWindow/, 'in-window rows show an active button; expired rows are gated');
});

test('105: three tabs present (upcoming / unmarked / history)', () => {
  assert.match(ISLAND, /tabUpcoming/);
  assert.match(ISLAND, /tabUnmarked/);
  assert.match(ISLAND, /tabHistory/);
});

test('105: widget mounted and revealed for all members in workspace', () => {
  assert.match(WORKSPACE, /import MyMeetingsIsland from '\.\.\/components\/workspace\/MyMeetingsIsland'/, 'imported');
  assert.match(WORKSPACE, /<MyMeetingsIsland client:load \/>/, 'mounted as island');
  assert.match(WORKSPACE, /getElementById\('wk-my-meetings'\)\?\.classList\.remove\('hidden'\)/, 'revealed on member load');
});
