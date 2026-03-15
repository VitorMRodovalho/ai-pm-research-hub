import test from 'node:test';
import assert from 'node:assert/strict';
import { credlyTierFromPoints, aggregateCredlyByMember } from '../src/lib/gamification.js';

test('credlyTierFromPoints maps known tier values', () => {
  // W143: ranges instead of exact values
  assert.equal(credlyTierFromPoints(50), 1);  // cert_pmi_senior
  assert.equal(credlyTierFromPoints(45), 1);  // cert_cpmai
  assert.equal(credlyTierFromPoints(40), 2);  // cert_pmi_mid
  assert.equal(credlyTierFromPoints(35), 2);  // cert_pmi_practitioner
  assert.equal(credlyTierFromPoints(30), 2);  // cert_pmi_entry
  assert.equal(credlyTierFromPoints(25), 2);  // specialization
  assert.equal(credlyTierFromPoints(20), 3);  // trail / knowledge_ai_pm
  assert.equal(credlyTierFromPoints(15), 3);  // course
  assert.equal(credlyTierFromPoints(10), 4);  // badge
  assert.equal(credlyTierFromPoints(5), 0);   // unknown
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
