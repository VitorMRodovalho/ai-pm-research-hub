/**
 * Contract: #1351 GP-wide visibility of pending tribe join-requests.
 *
 * Migration: supabase/migrations/20260805000432_1351_tribe_request_pending_operational_alert.sql
 *
 * Before: a tribe join-request notified only that tribe's leader and rendered only on that tribe's
 * Members tab (list_tribe_pending_requests). No aggregated view, so a pending in a full tribe
 * (un-approvable -> the approve raises "Tribo lotada" 400) was invisible to the GP and just expired.
 * Anchor: Guilherme -> Tribo 6 (8/8), stuck 4 days.
 *
 * After: detect_operational_alerts() (the manage_platform SSOT of operational alerts) emits one
 * `tribe_request_pending` alert per pending self-request across ALL tribes, severity escalated
 * (high when the tribe is full or the request is stale), carrying invitation_id for direct action.
 *
 * Invariants (static — the alert shape was proven live via a rolled-back DO block in the PR: a
 * temp pending on the full Tribo 6 produced a high-severity alert with tribe_full=true, slot 8/8,
 * days_pending, requester_name and invitation_id; detect_operational_alerts is manage_platform-gated
 * so it cannot be driven from a service-role client):
 *  - migration re-captures detect_operational_alerts;
 *  - it declares the cap (tribe_capacity_limit) and emits the tribe_request_pending alert type;
 *  - severity escalates to high when the tribe is full or the request is stale;
 *  - the alert carries invitation_id + the full/slot fields (GP can act + see why it is stuck);
 *  - the slot formula matches review_tribe_request/request_tribe_assignment (leader counts);
 *  - only pending self-requests are considered (invitee == inviter);
 *  - the message carries no em-dash / en-dash (deliverable rule).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000432_1351_tribe_request_pending_operational_alert.sql');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

// isolate the new alert block to assert on it specifically
const block = (() => {
  const i = mig.indexOf("'type', 'tribe_request_pending'");
  if (i < 0) return '';
  const start = mig.lastIndexOf('SELECT jsonb_agg', i);
  const end = mig.indexOf('RETURN jsonb_build_object', i);
  return mig.slice(start, end);
})();

test('#1351: migration re-captures detect_operational_alerts + declares the cap', () => {
  assert.ok(existsSync(MIG), 'migration present');
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.detect_operational_alerts\(\)/);
  assert.match(mig, /v_cap integer := public\.tribe_capacity_limit\(\)/, 'cap from SSOT declared');
});

test('#1351: emits the tribe_request_pending alert with actionable fields', () => {
  assert.ok(block, 'tribe_request_pending block present');
  for (const field of ['invitation_id', 'tribe_full', 'slot_count', "'cap'", 'days_pending', 'requester_name', 'expires_at']) {
    assert.ok(block.includes(field), `alert carries ${field}`);
  }
});

test('#1351: severity escalates to high when the tribe is full or the request is stale', () => {
  assert.match(block, /CASE WHEN sub\.tribe_full OR sub\.days_pending > 5 THEN 'high'/, 'full or >5d -> high');
});

test('#1351: slot formula matches the other tribe gates (leader counts)', () => {
  assert.match(block, /operational_role NOT IN \('sponsor', 'chapter_liaison', 'guest', 'none'\)/);
  assert.match(block, /sc\.slot_count >= v_cap AS tribe_full/, 'tribe_full derived from cap');
});

test('#1351: only pending self-requests (invitee == inviter)', () => {
  assert.match(block, /ii\.status = 'pending' AND ii\.invitee_member_id = ii\.inviter_member_id/);
});

test('#1351: alert message carries no em-dash / en-dash (deliverable rule)', () => {
  // guard only the new block (older alert comments in the function legitimately contain em-dashes)
  assert.ok(!/[—–]/.test(block), 'no em-dash/en-dash in the tribe_request_pending block');
});
