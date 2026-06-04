/**
 * Contract: #494 Part A — the recurring-series modal can scope a series to an initiative.
 *
 * Background: the single-event modal already supports `type='iniciativa'` (NewEventModal:
 * ev-type → ev-initiative-select), linking via the "p169" post-create UPDATE because create_event
 * only accepts p_tribe_id. The recurring modal (post-#492) only had a tribe-picker.
 *
 * Fix (frontend-only, no RPC change): extend the rec-audience scope select with an `initiative`
 * option that reveals a rec-initiative-select picker (parity with the #492 tribe path). On submit,
 * createRecurring creates the series with type='iniciativa' / no tribe / p_audience_level='initiative',
 * then batch-UPDATEs every returned event_id's initiative_id — exact parity with the single-event path.
 *
 * create_recurring_weekly_events takes only p_tribe_id (verified live), so the post-create UPDATE is
 * required; this test guards that the wiring stays in place.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MODAL = resolve(ROOT, 'src/components/attendance/RecurringModal.astro');
const ATT = resolve(ROOT, 'src/pages/attendance.astro');
const modalRaw = existsSync(MODAL) ? readFileSync(MODAL, 'utf8') : '';
const attRaw = existsSync(ATT) ? readFileSync(ATT, 'utf8') : '';

test('#494 static: recurring modal offers an "initiative" audience scope + a picker', () => {
  assert.ok(modalRaw, 'RecurringModal.astro readable');
  assert.match(modalRaw, /<option value="initiative"/, 'rec-audience has an initiative option');
  assert.match(modalRaw, /id="rec-initiative-wrap"/, 'initiative-picker wrapper exists');
  assert.match(modalRaw, /id="rec-initiative-select"/, 'initiative select exists');
});

test('#494 static: the scope toggle + initiatives cache cover the recurring initiative picker', () => {
  assert.ok(attRaw, 'attendance.astro readable');
  // unified toggle reveals the initiative wrap and lazy-loads the cache for the initiative scope
  assert.match(attRaw, /function toggleRecAudiencePickers/, 'toggleRecAudiencePickers exists');
  assert.match(attRaw, /rec-initiative-wrap/, 'toggle references the initiative wrapper');
  // ensureInitiativesLoaded must populate the recurring select (alongside the single + edit selects)
  assert.match(
    attRaw,
    /\[\s*'edit-ev-initiative-select',\s*'ev-initiative-select',\s*'rec-initiative-select'\s*\]/,
    'ensureInitiativesLoaded populates rec-initiative-select',
  );
});

test('#494 static: createRecurring handles the initiative scope (type + validated picker)', () => {
  // initiative scope forces a constraint-valid type and reads the picker
  assert.match(attRaw, /audience === 'initiative'/, 'createRecurring branches on the initiative scope');
  assert.match(attRaw, /dbType = 'iniciativa'/, "initiative scope creates type='iniciativa'");
  assert.match(attRaw, /rec-initiative-select/, 'createRecurring reads the chosen initiative');
});

test('#494 static: the series links initiative_id via a post-create UPDATE over event_ids (p169 parity)', () => {
  // mirror of the single-event pattern, but batched across the whole series via .in('id', event_ids)
  assert.match(
    attRaw,
    /\.update\(\{\s*initiative_id:\s*initiativeId\s*\}\)\s*\n?\s*\.in\('id',\s*data\.event_ids\)/,
    'createRecurring batch-UPDATEs initiative_id over the returned event_ids',
  );
  // audience flows to the RPC so audience_level='initiative' is written server-side
  assert.match(attRaw, /p_audience_level:\s*audience/, 'recurring call forwards the audience as audience_level');
});

test('#494 review-fix: initiative series writes the same audience rule as the single-event path (parity)', () => {
  // review finding #1/#3: buildAudienceRules has no 'initiative' branch → a tagged initiative series
  // would write no event_audience rule, diverging from createEvent's 'all_active_operational'. The fix
  // maps the initiative scope to 'all_active_operational' in the recurring tag loop so self-checkin
  // (register_own_presence) gates identically for single + recurring initiative events.
  assert.match(
    attRaw,
    /audience === 'initiative'\s*\?\s*'all_active_operational'\s*:\s*audience/,
    "createRecurring maps the initiative scope to the single-event 'all_active_operational' rule",
  );
});

test('#494 review-fix: openRecurringModal resets the scope selects so a stale selection cannot bind a new series', () => {
  // review finding #2: <select>s are not form-reset and closeModal only toggles CSS, so an abandoned
  // prior selection persisted. openRecurringModal must reset rec-audience (the gating control).
  assert.match(
    attRaw,
    /getElementById\('rec-audience'\)[^\n]*\)\.value = 'all'/,
    'openRecurringModal resets rec-audience to all on open',
  );
});

test('#494 guard: the single-event p169 initiative path is NOT regressed', () => {
  // the single-event create still links its one event — parity source of truth must stay intact
  assert.match(attRaw, /type === 'iniciativa'\s*\?\s*\(document\.getElementById\('ev-initiative-select'\)/, 'single-event still reads ev-initiative-select');
  assert.match(attRaw, /audience_level:\s*'initiative'/, "single-event still sets audience_level='initiative'");
});
