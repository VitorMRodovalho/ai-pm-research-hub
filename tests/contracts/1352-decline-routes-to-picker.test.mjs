/**
 * Contract: #1352 requester-side journey — a declined tribe request routes the requester to the
 * picker (/workspace), not to the tribe that rejected them; the body names the next step.
 *
 * Migration: supabase/migrations/20260805000433_1352_decline_notification_routes_to_picker.sql
 *
 * Before: review_tribe_request set the outcome notification link to '/tribe/<legacy_tribe_id>' for
 * BOTH approve and decline. On decline that dead-ended the requester at the rejecting tribe with no
 * path to re-pick. The picker (TribeRequestBlock) lives at /workspace.
 *
 * Invariants (static — proven live via a rolled-back DO block in the PR: a decline produced a
 * notification with link=/workspace and body ending "Você pode escolher outra tribo no seu painel.";
 * review_tribe_request is auth.uid()-gated so it can't be driven from a service-role client):
 *  - migration re-captures review_tribe_request;
 *  - the notification link is a decision CASE: approve -> /tribe/<id>, decline -> /workspace;
 *  - the decline body names the next step (choose another tribe);
 *  - the picker route /workspace exists (+ its locale variants), so the link resolves.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000433_1352_decline_notification_routes_to_picker.sql');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

test('#1352: migration re-captures review_tribe_request', () => {
  assert.ok(existsSync(MIG), 'migration present');
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.review_tribe_request\(/);
});

test('#1352: notification link is a decision CASE (approve -> tribe, decline -> /workspace)', () => {
  // the link expression: approve keeps /tribe/<id>, decline routes to the picker
  assert.match(
    mig,
    /CASE WHEN p_decision = 'approve'\s*\n\s*THEN '\/tribe\/' \|\| v_initiative\.legacy_tribe_id::text\s*\n\s*ELSE '\/workspace'\s*\n\s*END,/,
    'link routes approve->/tribe/<id>, decline->/workspace'
  );
});

test('#1352: decline body names the next step (choose another tribe)', () => {
  assert.match(mig, /Você pode escolher outra tribo no seu painel\./, 'decline body has the call to action');
});

test('#1352: approve path still routes to the tribe (unchanged)', () => {
  assert.match(mig, /THEN '\/tribe\/' \|\| v_initiative\.legacy_tribe_id::text/, 'approve keeps the tribe link');
});

test('#1352: the picker route /workspace exists (+ locale variants)', () => {
  for (const p of ['src/pages/workspace.astro', 'src/pages/en/workspace.astro', 'src/pages/es/workspace.astro']) {
    assert.ok(existsSync(resolve(ROOT, p)), `${p} exists (the decline link target)`);
  }
});
