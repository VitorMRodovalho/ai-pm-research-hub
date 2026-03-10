import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = '/home/vitormrodovalho/Desktop/ai-pm-research-hub';
const ATTENDANCE_FILES = [
  'src/pages/attendance.astro',
  'src/components/attendance/NewEventModal.astro',
  'src/components/attendance/RecurringModal.astro',
  'src/components/attendance/EditEventModal.astro',
  'src/components/attendance/RosterModal.astro',
];

test('attendance modal cluster does not use inline handlers', () => {
  for (const relativePath of ATTENDANCE_FILES) {
    const content = readFileSync(resolve(ROOT, relativePath), 'utf8');
    assert.equal(/on(click|change|input)=/.test(content), false, `${relativePath} should not contain inline handlers`);
  }
});

test('recurring modal template no longer hardcodes cycle_3 copy', () => {
  const content = readFileSync(resolve(ROOT, 'src/components/attendance/RecurringModal.astro'), 'utf8');
  assert.equal(content.includes('Ciclo 3'), false);
});
