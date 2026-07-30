import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const PAGE = 'src/pages/attendance.astro';
const MODAL = 'src/components/attendance/RecurringModal.astro';

/**
 * Two defects found by auditing who schedules meetings (2026-07-30), both in the recurring-series flow.
 *
 * 1) DERIVED TITLE. The modal shipped `Reunião Geral — Núcleo IA & GP | Semana {n}` hardcoded, and
 *    createRecurring() rewrites the TYPE to 'tribo' the moment a tribe audience is chosen (#492). So
 *    the type came out right while the title kept announcing a Núcleo-wide meeting. Measured in prod:
 *    6 events with type='tribo' whose title was the UNTOUCHED default "Reunião Geral — Núcleo IA & GP |
 *    Semana N", all on the Radar Tecnológico tribe.
 *
 *    ⚠️ Correction worth keeping: an earlier read of this counted 18 events across two leaders. That was
 *    wrong. The other 11 (Fluência em IA) read "[Núcleo IA & GP] Tribo 14 - Reunião Quinzenal | Semana N"
 *    — that operator EDITED the title and named their tribe, so they only matched a loose grep on the
 *    "Núcleo IA & GP" substring. The defect is proven by the CODE (a fixed institutional default plus the
 *    #492 type-forcing), not by a population count.
 *
 * 2) DOUBLE-SUBMIT. createRecurring() was called straight from the submit handler with no in-flight
 *    lock and no button disable, so a second click during the RPC created a COMPLETE second series.
 *    Measured in prod: recurrence_group a1772307 and 640e4959 created 6 seconds apart (2026-07-06
 *    23:52:38 / :44), duplicating every week of the series and double-counting attendance on the weeks
 *    that actually happened.
 *
 * These guards assert the MECHANISM exists and is wired, not the exact copy of any template string, so
 * rewording a title stays legal while removing the derivation does not.
 */

const page = readFileSync(resolve(ROOT, PAGE), 'utf8');
const modal = readFileSync(resolve(ROOT, MODAL), 'utf8');

test('#1535 the recurring title is derived from the audience, with a per-audience template map', () => {
  assert.match(page, /REC_TITLE_TEMPLATES/, 'the audience→title template map must exist');
  for (const audience of ['all', 'tribe', 'initiative', 'leadership', 'curators']) {
    assert.match(
      page,
      new RegExp(`${audience}\\s*:`),
      `REC_TITLE_TEMPLATES must cover the '${audience}' audience, otherwise that scope silently falls ` +
        'back to the institutional default that caused the bug',
    );
  }
  // The tribe/initiative templates must interpolate the scope label, not hardcode a name.
  assert.match(
    page,
    /tribe:\s*\(label\)\s*=>[^\n]*\$\{label\}/,
    "the 'tribe' template must interpolate the selected tribe label",
  );
});

test('#1535 derivation is wired to open, audience change and scope change', () => {
  assert.match(page, /function syncRecTitleDefault\s*\(/, 'syncRecTitleDefault must exist');
  // Wired on scope-select change.
  assert.match(
    page,
    /rec-tribe-select'\s*\|\|\s*target\.id\s*===\s*'rec-initiative-select'\)\s*syncRecTitleDefault\(\)/,
    'changing the tribe/initiative select must re-derive the title',
  );
  // Wired inside the audience toggle.
  const toggle = page.slice(page.indexOf('function toggleRecAudiencePickers'), page.indexOf('function openRecurringModal'));
  assert.match(toggle, /syncRecTitleDefault/, 'toggleRecAudiencePickers must re-derive the title');
  // Wired on modal open, and the dirty flag reset there.
  const open = page.slice(page.indexOf('function openRecurringModal'), page.indexOf('async function createRecurring'));
  assert.match(open, /syncRecTitleDefault/, 'opening the modal must derive the default title');
  assert.match(open, /delete .*dataset\.userEdited/, 'opening the modal must clear the userEdited flag');
});

test('#1535 an operator-typed title is never clobbered by derivation', () => {
  assert.match(
    page,
    /rec-title'\)\s*target\.dataset\.userEdited\s*=\s*'1'/,
    "typing in rec-title must mark the field as user-edited",
  );
  assert.match(
    page,
    /dataset\.userEdited\s*===\s*'1'\)\s*return/,
    'syncRecTitleDefault must bail out when the operator typed their own title',
  );
});

test('#1535 the modal markup carries no scope-specific hardcoded default', () => {
  // The 'all'/institutional seed is allowed in markup; a tribe/initiative-specific string is not,
  // because it would reintroduce exactly the mismatch this fixes.
  const titleInput = modal.slice(modal.indexOf('id="rec-title"'), modal.indexOf('id="rec-title"') + 260);
  assert.doesNotMatch(
    titleInput,
    /Reunião Semanal|Tribo \d|Radar|Fluência/,
    'the markup default must not name a tribe or a tribe-shaped meeting; derivation owns that',
  );
});

test('#1535 the three creation forms go through a double-submit guard', () => {
  assert.match(page, /function guardedSubmit\s*\(/, 'guardedSubmit must exist');
  assert.match(page, /submitsInFlight/, 'an in-flight registry must exist');
  // Released in a finally, or a failed submit locks the form forever.
  const guard = page.slice(page.indexOf('async function guardedSubmit'), page.indexOf("document.addEventListener('submit'"));
  assert.match(guard, /finally\s*\{/, 'the in-flight lock must be released in a finally block');
  assert.match(guard, /disabled = false/, 'the submit button must be re-enabled after the attempt');

  // Every creation/edit submit must be routed through it — an unguarded one is the whole bug.
  const dispatch = page.slice(page.indexOf("document.addEventListener('submit'"));
  for (const formId of ['new-event-form', 'recurring-event-form', 'edit-event-form']) {
    const stanza = dispatch.slice(dispatch.indexOf(formId), dispatch.indexOf(formId) + 200);
    assert.match(
      stanza,
      /guardedSubmit\(/,
      `${formId} must submit through guardedSubmit; a bare call re-runs on the second click`,
    );
  }
});
