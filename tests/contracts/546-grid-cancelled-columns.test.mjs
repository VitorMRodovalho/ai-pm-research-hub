/**
 * #546 contract test — attendance smart-grid retains cancelled-event columns.
 *
 * Bug (grid half of #157): SmartTribeSection.relevantEvents filtered out events
 * where ALL cells are 'na'. A cancelled event is correctly all-'na' (the grid RPC
 * short-circuits status='cancelled' -> 'na'), so it vanished entirely from the
 * default smart grid — no column, no 🚫. (Roster modal half was fixed by PR #158.)
 *
 * Fix (frontend-only — the grid RPC get_attendance_grid already returns is_cancelled):
 *   - GridEvent.is_cancelled declared + consumed.
 *   - relevantEvents retains evt.is_cancelled even when all-'na'.
 *   - cancelled column header marked (line-through + cancelled title).
 *   - cancelled cells render a non-clickable 🚫 with no toggle/⋮ affordance, so
 *     attendance rates stay unaffected (RPC already excludes 'na' from denominators).
 *
 * Static-only (regression lock on the source); no DB needed.
 *
 * Cross-ref: #546, #157 (parent), #158 (roster half).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const SRC = readFileSync(
  resolve(process.cwd(), 'src/components/attendance/AttendanceGridTab.tsx'),
  'utf8',
);

test('#546: GridEvent interface declares is_cancelled', () => {
  assert.match(SRC, /interface GridEvent\s*\{[\s\S]*?is_cancelled:\s*boolean;[\s\S]*?\}/);
});

test('#546: relevantEvents retains cancelled events even when all cells are na', () => {
  assert.match(
    SRC,
    /relevantEvents\s*=\s*useMemo\([\s\S]*?allEvents\.filter\(\(evt\)\s*=>\s*evt\.is_cancelled\s*\|\|\s*rows\.some/,
    'relevantEvents filter must keep evt.is_cancelled events',
  );
});

test('#546: cancelled cells short-circuit to a non-clickable marker (no toggle)', () => {
  // the cancelled branch must return BEFORE the data-toggle-event cell is built
  assert.match(
    SRC,
    /if\s*\(ev\.is_cancelled\)\s*\{[\s\S]*?return\s*\([\s\S]*?<td[\s\S]*?🚫[\s\S]*?<\/td>[\s\S]*?\);[\s\S]*?\}/,
    'cancelled events must render a non-interactive 🚫 cell and return early',
  );
});

test('#546: cancelled column header is visually distinguished', () => {
  assert.match(
    SRC,
    /ev\.is_cancelled\s*\?\s*t\('attendance\.roster\.cancelled'/,
    'cancelled header must use the attendance.roster.cancelled label',
  );
  assert.match(SRC, /ev\.is_cancelled\s*\?\s*' line-through opacity-60'/, 'cancelled header abbr must be struck through');
});
