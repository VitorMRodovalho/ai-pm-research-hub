/**
 * ADR-0016 Amendment 2 C9 — Unit tests para resolve_default_gates(p_doc_type)
 *
 * Valida matriz gate-per-doc-type não regride em future sessions:
 *   - cooperation_agreement / cooperation_addendum: 6 gates (inclui chapter_witness + president_others)
 *   - volunteer_term_template / volunteer_addendum: 5 gates (inclui volunteers_in_role_active; sem chapter_witness, sem president_others)
 *   - policy: 5 gates (sem chapter_witness; com president_others; sem member_ratification)
 *   - executive_summary: NULL (fora do workflow)
 *
 * Padrão de invariante: curator sempre primeiro gate com threshold="all" (governance PM decision p35).
 *
 * Requires: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY. Skipped otherwise.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

async function callResolveGates(docType) {
  const url = `${SUPABASE_URL}/rest/v1/rpc/resolve_default_gates`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'apikey': SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({ p_doc_type: docType }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`RPC failed (${docType}): HTTP ${res.status} — ${text}`);
  }
  return await res.json();
}

function assertCuratorFirstGateAll(gates, docType) {
  assert.ok(Array.isArray(gates), `${docType}: gates should be array`);
  assert.ok(gates.length >= 1, `${docType}: gates should be non-empty`);
  assert.equal(gates[0].kind, 'curator', `${docType}: first gate should be curator`);
  assert.equal(gates[0].order, 1, `${docType}: curator order should be 1`);
  assert.equal(gates[0].threshold, 'all', `${docType}: curator threshold should be "all" (governance)`);
}

function findGate(gates, kind) {
  return gates.find((g) => g.kind === kind);
}

// ─── cooperation_agreement ───
test(
  canRun ? 'resolve_default_gates cooperation_agreement returns 6 gates matrix' : skipMsg,
  { skip: !canRun },
  async () => {
    const gates = await callResolveGates('cooperation_agreement');
    assertCuratorFirstGateAll(gates, 'cooperation_agreement');
    assert.equal(gates.length, 6, 'cooperation_agreement should have 6 gates');
    assert.ok(findGate(gates, 'leader_awareness'), 'must include leader_awareness');
    assert.ok(findGate(gates, 'submitter_acceptance'), 'must include submitter_acceptance');
    assert.ok(findGate(gates, 'chapter_witness'), 'must include chapter_witness');
    assert.ok(findGate(gates, 'president_go'), 'must include president_go');
    assert.ok(findGate(gates, 'president_others'), 'must include president_others');
    assert.equal(findGate(gates, 'president_others').threshold, 4, 'president_others threshold=4 (4 outros capítulos)');
    assert.equal(findGate(gates, 'chapter_witness').threshold, 5, 'chapter_witness threshold=5');
    assert.equal(
      findGate(gates, 'member_ratification'), undefined,
      'cooperation_agreement should NOT have member_ratification (fecha com presidências)'
    );
  }
);

// ─── cooperation_addendum ───
test(
  canRun ? 'resolve_default_gates cooperation_addendum matches cooperation_agreement matrix' : skipMsg,
  { skip: !canRun },
  async () => {
    const gates = await callResolveGates('cooperation_addendum');
    assertCuratorFirstGateAll(gates, 'cooperation_addendum');
    assert.equal(gates.length, 6, 'cooperation_addendum should have 6 gates (same as cooperation_agreement)');
    assert.ok(findGate(gates, 'chapter_witness'), 'must include chapter_witness');
    assert.ok(findGate(gates, 'president_others'), 'must include president_others');
  }
);

// ─── volunteer_term_template ───
test(
  canRun ? 'resolve_default_gates volunteer_term_template returns 5 gates (no chapter_witness, no president_others)' : skipMsg,
  { skip: !canRun },
  async () => {
    const gates = await callResolveGates('volunteer_term_template');
    assertCuratorFirstGateAll(gates, 'volunteer_term_template');
    assert.equal(gates.length, 5, 'volunteer_term_template should have 5 gates');
    assert.ok(findGate(gates, 'president_go'), 'must include president_go');
    assert.ok(findGate(gates, 'volunteers_in_role_active'), 'must include volunteers_in_role_active (novo gate_kind)');
    assert.equal(findGate(gates, 'volunteers_in_role_active').threshold, 'all', 'volunteers_in_role_active threshold="all"');
    assert.equal(
      findGate(gates, 'chapter_witness'), undefined,
      'volunteer_term_template should NOT have chapter_witness (bilateral voluntário↔PMI-GO)'
    );
    assert.equal(
      findGate(gates, 'president_others'), undefined,
      'volunteer_term_template should NOT have president_others (instrumento interno PMI-GO)'
    );
  }
);

// ─── volunteer_addendum ───
test(
  canRun ? 'resolve_default_gates volunteer_addendum matches volunteer_term_template matrix' : skipMsg,
  { skip: !canRun },
  async () => {
    const gates = await callResolveGates('volunteer_addendum');
    assertCuratorFirstGateAll(gates, 'volunteer_addendum');
    assert.equal(gates.length, 5, 'volunteer_addendum should have 5 gates (same as volunteer_term_template)');
    assert.ok(findGate(gates, 'volunteers_in_role_active'), 'must include volunteers_in_role_active');
    assert.equal(findGate(gates, 'chapter_witness'), undefined);
    assert.equal(findGate(gates, 'president_others'), undefined);
  }
);

// ─── policy ───
test(
  canRun ? 'resolve_default_gates policy returns 5 gates (with president_others, no chapter_witness, no member_ratification)' : skipMsg,
  { skip: !canRun },
  async () => {
    const gates = await callResolveGates('policy');
    assertCuratorFirstGateAll(gates, 'policy');
    assert.equal(gates.length, 5, 'policy should have 5 gates');
    assert.ok(findGate(gates, 'president_go'), 'must include president_go');
    assert.ok(findGate(gates, 'president_others'), 'must include president_others');
    assert.equal(
      findGate(gates, 'chapter_witness'), undefined,
      'policy should NOT have chapter_witness (aprovada pelas presidências, sem testemunhas)'
    );
    assert.equal(
      findGate(gates, 'member_ratification'), undefined,
      'policy should NOT have member_ratification (voluntários vinculam via remissão Termo/Adendo)'
    );
    assert.equal(
      findGate(gates, 'volunteers_in_role_active'), undefined,
      'policy should NOT have volunteers_in_role_active (legal-counsel p35 decision)'
    );
  }
);

// ─── executive_summary (fora do workflow) ───
test(
  canRun ? 'resolve_default_gates executive_summary returns NULL (outside workflow)' : skipMsg,
  { skip: !canRun },
  async () => {
    const gates = await callResolveGates('executive_summary');
    assert.equal(gates, null, 'executive_summary should return NULL — not in IP workflow (PM decision p35)');
  }
);

// ─── unknown doc_type returns NULL ───
test(
  canRun ? 'resolve_default_gates unknown doc_type returns NULL' : skipMsg,
  { skip: !canRun },
  async () => {
    const gates = await callResolveGates('nonexistent_type');
    assert.equal(gates, null, 'unknown doc_type should return NULL (ELSE branch)');
  }
);

// ─── invariant: all gates have required fields ───
test(
  canRun ? 'resolve_default_gates: every gate has {kind, order, threshold} keys (ADR-0016 C9 shape)' : skipMsg,
  { skip: !canRun },
  async () => {
    const docTypes = ['cooperation_agreement', 'cooperation_addendum', 'volunteer_term_template', 'volunteer_addendum', 'policy'];
    for (const dt of docTypes) {
      const gates = await callResolveGates(dt);
      for (const g of gates) {
        assert.ok('kind' in g, `${dt}: gate missing 'kind'`);
        assert.ok('order' in g, `${dt}: gate missing 'order'`);
        assert.ok('threshold' in g, `${dt}: gate missing 'threshold'`);
        assert.equal(typeof g.order, 'number', `${dt}: order should be number`);
        assert.ok(g.order >= 1, `${dt}: order >= 1`);
        // threshold is number OR 'all'
        assert.ok(
          typeof g.threshold === 'number' || g.threshold === 'all',
          `${dt}: threshold should be number or "all" (got ${typeof g.threshold} ${g.threshold})`
        );
      }
    }
  }
);

// ─── invariant: gate orders form 1..N without gaps ───
test(
  canRun ? 'resolve_default_gates: gate orders are sequential 1..N without gaps' : skipMsg,
  { skip: !canRun },
  async () => {
    const docTypes = ['cooperation_agreement', 'cooperation_addendum', 'volunteer_term_template', 'volunteer_addendum', 'policy'];
    for (const dt of docTypes) {
      const gates = await callResolveGates(dt);
      const orders = gates.map((g) => g.order).sort((a, b) => a - b);
      for (let i = 0; i < orders.length; i++) {
        assert.equal(orders[i], i + 1, `${dt}: order sequence should be 1..${orders.length}, got ${orders}`);
      }
    }
  }
);
