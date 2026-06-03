/**
 * Contract: #492 — recurring-series modal sends a DB-valid events.type + supports tribe selection.
 *
 * Root cause: RecurringModal had a hidden `rec-type` defaulting to the LEGACY value
 * 'general_meeting'; createRecurring passed it raw to create_recurring_weekly_events, which inserts
 * type = p_type and only translates 'tribe_meeting'→'tribo' — so 'general_meeting' (and other legacy
 * values) violated events_type_check (23514). The modal also had no tribe-picker, and p_tribe_id used
 * a dead `type === 'tribe_meeting'` condition (always null, using the caller's own tribe).
 *
 * Fix: rec-type defaults to 'geral'; createRecurring normalizes to a constraint-valid type
 * (VALID_TYPES / legacy map, force 'tribo' for tribe audience) and passes the SELECTED tribe via a
 * new rec-tribe-select revealed when audience='tribe'.
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

// events_type_check allowed set (kept in sync with the migration constraint).
const VALID = ['geral','tribo','iniciativa','lideranca','kickoff','comms','parceria','entrevista','1on1','evento_externo','webinar'];

test('#492 static: rec-type defaults to a DB-valid type (not legacy general_meeting)', () => {
  assert.match(modalRaw, /id="rec-type"\s+value="geral"/, 'rec-type default is the valid "geral"');
  assert.doesNotMatch(modalRaw, /id="rec-type"\s+value="general_meeting"/, 'no legacy general_meeting default');
});

test('#492 static: recurring modal has a tribe-picker', () => {
  assert.match(modalRaw, /id="rec-tribe-wrap"/, 'tribe-picker wrapper exists');
  assert.match(modalRaw, /id="rec-tribe-select"/, 'tribe select exists');
});

test('#492 static: createRecurring normalizes to a constraint-valid events.type', () => {
  assert.match(attRaw, /const VALID_TYPES\s*=/, 'declares the valid-type allowlist');
  // the allowlist must equal the DB constraint set
  for (const tpe of VALID) assert.ok(attRaw.includes(`'${tpe}'`), `VALID_TYPES includes ${tpe}`);
  // the recurring RPC call must pass the normalized dbType (the single-event create_event still
  // legitimately uses `p_type: type` with its valid ev-type select, so we don't ban that globally).
  assert.match(attRaw, /p_type:\s*dbType/, 'recurring call passes the normalized dbType, not the raw rec-type');
});

test('#492 static: p_tribe_id comes from the selected tribe, not the dead type check', () => {
  assert.doesNotMatch(attRaw, /p_tribe_id:\s*type === 'tribe_meeting'/, 'dead tribe_meeting condition removed');
  assert.match(attRaw, /p_tribe_id:\s*tribeId/, 'p_tribe_id uses the chosen tribe');
});

test('#492 static: tribe-picker is populated + toggled by audience', () => {
  assert.match(attRaw, /'rec-tribe-select'/, 'rec-tribe-select is populated by ensureTribesLoaded');
  assert.match(attRaw, /function toggleRecTribePicker/, 'toggleRecTribePicker exists');
  assert.match(attRaw, /target\.id === 'rec-audience'/, 'audience change toggles the picker');
});
