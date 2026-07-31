import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const ATTENDANCE = readFileSync(resolve(ROOT, 'src/pages/attendance.astro'), 'utf8');

/**
 * Drop whole-line `//` comments and `/* *\/` blocks before counting call sites. A guard that
 * cannot tell code from prose fires on the comment that documents it — which is how a guard
 * teaches people to relax it. Trailing comments on a code line are deliberately KEPT, so
 * `openEditEvent(ev); // legacy` still counts as the call it is.
 */
const stripComments = (src) => src
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .split('\n').filter((l) => !/^\s*(\/\/|\*)/.test(l)).join('\n');

/**
 * #1545 — clicking ✏️ on an event did NOTHING: no modal, no toast, no console line.
 *
 * The reason was not one bug but a SHAPE. `openEditEvent` is `async` and populates 23 DOM
 * nodes, two remote caches and the tag picker BEFORE `openModal` runs on its last line; every
 * call site invoked it fire-and-forget. Any throw in that path became an unhandled rejection,
 * which is indistinguishable from a dead button. `guardedSubmit` had the same shape on the
 * Save side, and the handlers it runs read the DOM outside their own try.
 *
 * These guards defend the INVARIANT — "no exit from the event-edit path is silent" — not the
 * particular root cause, which was never reproduced. The failure had no observable signal at
 * all, so a guard that waits for a repro would never have been written.
 */

// ── 1) every openEditEvent call site goes through the reporting wrapper ────
test('#1545 openEditEvent is never called fire-and-forget', () => {
  // The wrapper itself is the single legitimate caller.
  const WRAPPER_BODY = /function openEditEventSafe\(ev: any\) \{[\s\S]*?\n  \}/;
  const wrapper = ATTENDANCE.match(WRAPPER_BODY);
  assert.ok(wrapper, 'openEditEventSafe must exist — it is the only reporting call path');

  const outsideWrapper = stripComments(ATTENDANCE).replace(WRAPPER_BODY, '')
    // the declaration is not a call site
    .replace(/async function openEditEvent\(/g, 'async function OPEN_EDIT_EVENT_DECL(');

  const bare = [...outsideWrapper.matchAll(/openEditEvent\s*\(/g)];
  assert.equal(
    bare.length, 0,
    `openEditEvent must be reached only via openEditEventSafe; found ${bare.length} bare call(s). ` +
    'A bare call swallows the rejection and the ✏️ button goes dead with no signal (#1545).',
  );
});

// ── 2) the wrapper actually reports BOTH silent exits ──────────────────────
test('#1545 openEditEventSafe reports a missing event AND a rejected open', () => {
  const wrapper = ATTENDANCE.match(/function openEditEventSafe\(ev: any\) \{[\s\S]*?\n  \}/)?.[0] || '';

  assert.match(
    wrapper, /if \(!ev\)[\s\S]*?toast\(/,
    'a missing __attendanceEventsById entry must toast, not return quietly',
  );
  assert.match(
    wrapper, /\.catch\(/,
    'the async open must have a catch — without it a throw is an unhandled rejection',
  );
  assert.match(
    wrapper, /console\.error\(/,
    'the catch must log: the toast tells the user, the console tells whoever debugs it',
  );
});

// ── 3) guardedSubmit reports instead of dropping the rejection ─────────────
test('#1545 guardedSubmit catches — a throw in a submit handler must surface', () => {
  const guarded = ATTENDANCE.match(/async function guardedSubmit\([\s\S]*?\n    \}/)?.[0] || '';
  assert.ok(guarded, 'guardedSubmit must exist');

  assert.match(
    guarded, /catch\s*\(/,
    'guardedSubmit must catch. Nobody awaits it, so a bare try/finally drops the rejection and ' +
    'the Save button appears to do nothing (#1545).',
  );
  assert.match(
    guarded, /toast\(/,
    'the catch must toast — a console-only report is invisible to the person clicking Save',
  );
  // The finally must survive the added catch, or the double-submit lock from #1538 leaks.
  assert.match(
    guarded, /finally\s*\{[\s\S]*?submitsInFlight\.delete\(formId\)[\s\S]*?btn\.disabled = false/,
    '#1538 lock release must stay in finally, not move into the catch',
  );
});

// ── 4) the new strings exist in ALL THREE dictionaries ─────────────────────
test('#1545 the new i18n keys have full 3-dictionary parity', () => {
  const KEYS = ['attendance.msg.eventEditOpenError', 'attendance.msg.eventNotLoaded'];
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const src = readFileSync(resolve(ROOT, `src/i18n/${dict}.ts`), 'utf8');
    for (const key of KEYS) {
      assert.ok(src.includes(`'${key}'`), `${dict}.ts is missing ${key}`);
    }
  }
  // And the page must expose them, or the client falls back to `undefined` in the toast.
  for (const prop of ['msgEventEditOpenError', 'msgEventNotLoaded']) {
    const uses = [...ATTENDANCE.matchAll(new RegExp(`${prop}:`, 'g'))].length;
    assert.equal(
      uses, 2,
      `${prop} must appear twice in attendance.astro: the server I18N map and the client fallback literal`,
    );
  }
});
