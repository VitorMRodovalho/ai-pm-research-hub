import test from 'node:test';
import assert from 'node:assert/strict';
import { credlyTierFromPoints, aggregateCredlyByMember } from '../src/lib/gamification.js';

test('credlyTierFromPoints maps known tier values', () => {
  assert.equal(credlyTierFromPoints(50), 1);
  assert.equal(credlyTierFromPoints(25), 2);
  assert.equal(credlyTierFromPoints(15), 3);
  assert.equal(credlyTierFromPoints(10), 4);
  assert.equal(credlyTierFromPoints(30), 0);
});

test('aggregateCredlyByMember groups totals and tier counters', () => {
  const rows = [
    { member_id: 'a', points: 50, reason: 'Credly: PMP' },
    { member_id: 'a', points: 25, reason: 'Credly: CAPM' },
    { member_id: 'a', points: 15, reason: 'Credly: Trail' },
    { member_id: 'b', points: 10, reason: 'Credly: Other' },
  ];
  const aggregated = aggregateCredlyByMember(rows);
  assert.deepEqual(aggregated.a, { total: 90, badges: 3, t1: 1, t2: 1, t3: 1, t4: 0 });
  assert.deepEqual(aggregated.b, { total: 10, badges: 1, t1: 0, t2: 0, t3: 0, t4: 1 });
});
