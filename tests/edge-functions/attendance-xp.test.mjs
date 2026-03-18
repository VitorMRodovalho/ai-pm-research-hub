import test from 'node:test';
import assert from 'node:assert/strict';
import { POINTS_PER_ATTENDANCE, ATTENDANCE_CATEGORY } from '../../supabase/functions/_shared/attendance-xp.ts';

test('POINTS_PER_ATTENDANCE is 10', () => {
  assert.equal(POINTS_PER_ATTENDANCE, 10);
});

test('ATTENDANCE_CATEGORY is attendance', () => {
  assert.equal(ATTENDANCE_CATEGORY, 'attendance');
});

test('constants are numbers and strings respectively', () => {
  assert.equal(typeof POINTS_PER_ATTENDANCE, 'number');
  assert.equal(typeof ATTENDANCE_CATEGORY, 'string');
});
