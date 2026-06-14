/**
 * #651 — Governance gates sharing the same `order` are parallel.
 *
 * Contracts:
 * - UI eligibility depends on all mandatory gates with lower order, not on the
 *   previous array item.
 * - Informational threshold=0 gates do not block later orders.
 * - DB notifications enqueue every gate in the active order, not a single
 *   ORDER BY ... LIMIT 1 gate.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const reviewChain = readFileSync(resolve(ROOT, 'src/components/governance/ReviewChainIsland.tsx'), 'utf8');
const pipelineBar = readFileSync(resolve(ROOT, 'src/components/governance/GovernancePipelineBar.tsx'), 'utf8');
const documentsPage = readFileSync(resolve(ROOT, 'src/pages/admin/governance/documents.astro'), 'utf8');
const migration = readFileSync(
  resolve(ROOT, 'supabase/migrations/20260805000159_fix_parallel_governance_gate_notifications.sql'),
  'utf8',
);

function threshold(g) {
  const s = String(g.threshold);
  if (s === 'all') return { isAll: true, isInformational: false, num: 0 };
  if (s === '0') return { isAll: false, isInformational: true, num: 0 };
  return { isAll: false, isInformational: false, num: Number(s) };
}

function satisfied(g) {
  const t = threshold(g);
  if (t.isInformational) return false;
  if (t.isAll) return Number(g.signed_count) > 0 && (g.eligible_pending || []).length === 0;
  return Number(g.signed_count) >= t.num;
}

function priorMandatoryOrdersSatisfied(gates, order) {
  return gates
    .filter(g => g.order < order && !threshold(g).isInformational)
    .every(satisfied);
}

function activeEligibleGates(gates, memberId) {
  return [...gates]
    .sort((a, b) => a.order - b.order)
    .filter(g => {
      const priorOK = priorMandatoryOrdersSatisfied(gates, g.order);
      const inEligible = (g.eligible_pending || []).some(p => p.id === memberId);
      return priorOK && inEligible && (threshold(g).isInformational || !satisfied(g));
    })
    .map(g => g.kind);
}

test('#651 behaviour: same-order mandatory gates are eligible together', () => {
  const gates = [
    { kind: 'curator', order: 1, threshold: 1, signed_count: 1, eligible_pending: [] },
    { kind: 'president_go', order: 2, threshold: 1, signed_count: 0, eligible_pending: [{ id: 'a' }] },
    { kind: 'cert_director_go', order: 2, threshold: 1, signed_count: 0, eligible_pending: [{ id: 'b' }] },
    { kind: 'member_ratification', order: 3, threshold: 1, signed_count: 0, eligible_pending: [{ id: 'c' }] },
  ];

  assert.deepEqual(activeEligibleGates(gates, 'a'), ['president_go']);
  assert.deepEqual(activeEligibleGates(gates, 'b'), ['cert_director_go']);
  assert.deepEqual(activeEligibleGates(gates, 'c'), [], 'next order waits for all order-2 mandatory gates');
});

test('#651 behaviour: informational gates do not block next mandatory order', () => {
  const gates = [
    { kind: 'curator', order: 1, threshold: 1, signed_count: 1, eligible_pending: [] },
    { kind: 'leader_awareness', order: 2, threshold: 0, signed_count: 0, eligible_pending: [{ id: 'leader' }] },
    { kind: 'president_go', order: 3, threshold: 1, signed_count: 0, eligible_pending: [{ id: 'president' }] },
  ];

  assert.deepEqual(activeEligibleGates(gates, 'leader'), ['leader_awareness']);
  assert.deepEqual(activeEligibleGates(gates, 'president'), ['president_go']);
});

test('#651 UI files use lower-order mandatory satisfaction, not item-by-item prevOK', () => {
  for (const [name, content] of [
    ['ReviewChainIsland', reviewChain],
    ['GovernancePipelineBar', pipelineBar],
    ['documents.astro', documentsPage],
  ]) {
    assert.match(content, /priorMandatoryOrdersSatisfied/, `${name} must gate by lower order groups`);
    assert.match(content, /isInformational/, `${name} must preserve threshold=0 non-blocking handling`);
  }

  assert.doesNotMatch(reviewChain, /let prevOK = true/, 'ReviewChainIsland must not serialise same-order gates');
  assert.doesNotMatch(pipelineBar, /let prevOK = true/, 'GovernancePipelineBar must not serialise same-order gates');
  assert.doesNotMatch(documentsPage, /var prevOK = true/, 'documents.astro must not serialise same-order gates');
});

test('#651 DB notification function iterates all gates in the active order', () => {
  assert.match(migration, /CREATE OR REPLACE FUNCTION public\._enqueue_gate_notifications/i);
  assert.match(migration, /SELECT MIN\(\(g->>'order'\)::int\) INTO v_next_order/i);
  assert.match(migration, /FOR v_gate IN\s+SELECT g FROM jsonb_array_elements\(v_chain\.gates\) g\s+WHERE \(g->>'order'\)::int = v_next_order/is);
  assert.match(migration, /v_current_order/i, 'gate_advanced must anchor from the satisfied gate order');
  assert.doesNotMatch(migration, /ORDER BY \(g->>'order'\)::int ASC LIMIT 1/i);
});
