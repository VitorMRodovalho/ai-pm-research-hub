/**
 * Contract: events visibility vocabulary + tribe-leader create-lock (PM-hit 2026-06-11).
 *
 * Bug 1 — vocab mismatch: both attendance modals shipped <option value="public"> while the DB
 * check (events_visibility_check) only allows 'all'|'leadership'|'gp_only'. create_event coerces
 * unknown→'all' (so CREATION silently worked), but update_future_events_in_group did NOT — any
 * group edit of an event whose visibility didn't match an <option> (select snapped to 'public')
 * bombed 400 on the whole series, blocking the PM from reclassifying mistyped events.
 * Fix: frontend vocab 'public'→'all' everywhere + coerce parity in the RPC (mig 20260805000144).
 *
 * Bug 2 — dead leader lock: attendance.astro gated the create-modal type/tribe lock on
 * MEMBER.role === 'leader', but the member object carries operational_role with V4 vocab
 * 'tribe_leader' → the lock never engaged (wrong field AND wrong value).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const MIG = 'supabase/migrations/20260805000144_update_future_events_visibility_coerce_parity.sql';
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const page = readFileSync('src/pages/attendance.astro', 'utf8');

test('visibility vocab: no value="public" option survives in either attendance modal', () => {
  for (const f of ['src/components/attendance/EditEventModal.astro', 'src/components/attendance/NewEventModal.astro']) {
    const src = readFileSync(f, 'utf8');
    assert.ok(!/value="public"/.test(src), `${f} must not offer the non-DB value 'public'`);
    assert.match(src, /value="all">Público</, `${f} keeps the Público label on the DB value 'all'`);
  }
});

test("visibility vocab: attendance.astro has zero 'public' visibility literals", () => {
  // Anchor on the visibility-select IDs: any line touching ev-visibility/edit-ev-visibility must not
  // read or write the value 'public' (DB vocab is all|leadership|gp_only).
  const offending = page
    .split('\n')
    .filter((l) => /(ev-visibility|edit-ev-visibility)/.test(l) && /'public'/.test(l));
  assert.deepEqual(offending, [], `visibility literals must use DB vocab, found: ${offending.join(' | ')}`);
});

test('mig 144: update_future_events_in_group coerces unknown visibility (parity with create_event)', () => {
  assert.ok(existsSync(MIG), 'migration 144 exists');
  assert.match(mig, /IF p_visibility IS NOT NULL AND p_visibility NOT IN \('all','leadership','gp_only'\) THEN\s*\n\s*p_visibility := 'all';/,
    'coerce block present');
  assert.match(mig, /NOTIFY pgrst/, 'schema reload notified');
});

test('leader create-lock: gated on operational_role tribe_leader (V4 vocab), not the dead role===leader', () => {
  assert.match(page, /MEMBER\?\.operational_role === 'tribe_leader' && MEMBER\?\.tribe_id/,
    'lock reads operational_role with the live V4 value');
  assert.ok(!/MEMBER\?\.role === 'leader'/.test(page), "dead-code gate MEMBER?.role === 'leader' removed");
});
