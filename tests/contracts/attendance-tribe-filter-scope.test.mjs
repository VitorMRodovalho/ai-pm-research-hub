/**
 * p122c — Attendance tribe-filter scope guard.
 *
 * Static contract: assert that the auto-applied tribe filter in
 * `src/pages/attendance.astro` only excludes events whose `type === 'tribo'`.
 *
 * Why this exists
 * ----------------
 * `populateTribeDropdown()` defaults the tribe-filter to the member's own
 * tribe for non-GP accounts. ADR-0015 Phase 3e (commit 4d2a10d, 2026-04-18)
 * dropped `events.tribe_id`, so `get_events_with_attendance` now derives
 * `tribe_id` via `JOIN initiatives.legacy_tribe_id`. Cross-cutting events
 * (geral / kickoff / lideranca / webinar / evento_externo) have no
 * `initiative_id`, so they come back with `tribe_id = null`.
 *
 * Before p122c the filter was `if (tribeF && ev.tribe_id != tribeF) return false`,
 * which silently excluded every cross-cutting event for ~50 active non-GP
 * members for ~3 weeks until a tribe leader (João Uzejka, Radar PMI-RS)
 * reported it.
 *
 * Fix: scope the filter to `ev.type === 'tribo'`. This test fails if the
 * scope guard is removed.
 *
 * Related guard: AttendanceGridTab.tsx already protects general events via
 * `if (ev.tribe_id !== null && ...)` — different surface, same intent.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';

const ATTENDANCE_PATH = path.resolve('src/pages/attendance.astro');

test('p122c: attendance.astro tribe filter must scope to type=tribo events', async () => {
  const src = await fs.readFile(ATTENDANCE_PATH, 'utf-8');

  // Required pattern: filter that includes type guard before tribe_id check.
  // Tolerates whitespace + comment variations but must include both:
  //   - tribeF guard
  //   - ev.type === 'tribo' check
  //   - ev.tribe_id != tribeF rejection
  const scopedFilterRegex =
    /if\s*\(\s*tribeF\s*&&\s*ev\.type\s*===\s*['"]tribo['"]\s*&&\s*ev\.tribe_id\s*!=\s*tribeF\s*\)\s*return\s+false\s*;/;

  assert.match(
    src,
    scopedFilterRegex,
    [
      'attendance.astro tribe filter must scope to ev.type === "tribo".',
      'Without this guard, the auto-applied tribe filter (line ~677, populateTribeDropdown)',
      'hides geral/kickoff/lideranca/webinar/evento_externo events for every non-GP member',
      'because Phase 3e (ADR-0015) made tribe_id NULL for cross-cutting events.',
      'See issue log entry "p122c (2026-05-08 fim de tarde)".',
    ].join('\n  ')
  );

  // Also assert the unscoped form is gone (regression guard).
  const unscopedAntiPattern =
    /if\s*\(\s*tribeF\s*&&\s*ev\.tribe_id\s*!=\s*tribeF\s*\)\s*return\s+false\s*;/;
  assert.doesNotMatch(
    src,
    unscopedAntiPattern,
    'attendance.astro must NOT contain the unscoped tribe filter (regression of p122c).'
  );
});

test('p122c: attendance.astro must surface auto-applied tribe filter as a clearable pill', async () => {
  const src = await fs.readFile(ATTENDANCE_PATH, 'utf-8');

  // Pill must exist in markup
  assert.match(
    src,
    /id=["']auto-tribe-filter-pill["']/,
    'attendance.astro must contain #auto-tribe-filter-pill element so the implicit filter is visible to non-GP members.'
  );

  // Clear handler must be wired
  assert.match(
    src,
    /case\s+['"]clear-auto-tribe-filter['"]/,
    'attendance.astro must handle data-action="clear-auto-tribe-filter" so members can opt out of the auto-filter.'
  );

  // populateTribeDropdown must show the pill when auto-applying
  assert.match(
    src,
    /pill\.classList\.remove\(['"]hidden['"]\)/,
    'populateTribeDropdown must un-hide the auto-tribe-filter pill when it auto-sets the filter.'
  );
});

test('p122c: i18n keys for auto tribe filter pill must exist in all three dictionaries', async () => {
  const required = [
    'attendance.autoTribeFilter.label',
    'attendance.autoTribeFilter.clear',
    'attendance.autoTribeFilter.clearAria',
    'attendance.autoTribeFilter.clearTitle',
  ];

  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const src = await fs.readFile(path.resolve(`src/i18n/${dict}.ts`), 'utf-8');
    for (const key of required) {
      assert.ok(
        src.includes(`'${key}'`),
        `i18n key '${key}' missing in ${dict}. All 3 dictionaries must define it (per project i18n rule).`
      );
    }
  }
});
