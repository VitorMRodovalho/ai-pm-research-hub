import test from 'node:test';
import assert from 'node:assert/strict';
import { buildTrailProgressByMember } from '../src/lib/trail-progress.js';

test('buildTrailProgressByMember aggregates unique course status per member', () => {
  const rows = [
    { member_id: 'a', course_id: 'c1', status: 'in_progress' },
    { member_id: 'a', course_id: 'c1', status: 'completed' },
    { member_id: 'a', course_id: 'c2', status: 'in_progress' },
    { member_id: 'a', course_id: 'c3', status: 'completed' },
    { member_id: 'b', course_id: 'c1', status: 'completed' },
    { member_id: 'b', course_id: 'c2', status: 'completed' },
    { member_id: 'b', course_id: 'c3', status: 'ignored_status' },
  ];

  const out = buildTrailProgressByMember(rows, 8);
  assert.deepEqual(out.get('a'), { completed: 2, inProgress: 1, pct: 25 });
  assert.deepEqual(out.get('b'), { completed: 2, inProgress: 0, pct: 25 });
});
