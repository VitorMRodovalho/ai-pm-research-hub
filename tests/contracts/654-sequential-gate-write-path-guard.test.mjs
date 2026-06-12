/**
 * #654 — sequential gate ordering enforced on the WRITE path of IP ratification.
 *
 * The read-path (#653) hides out-of-order gates from get_pending_ratifications.
 * This locks the WRITE-path twin: sign_ip_ratification now rejects a signature for
 * a gate whose lower-ordered gates have not met their threshold, via two shared
 * predicates introduced by migration 20260805000154:
 *   - _gate_threshold_met(chain, gate_jsonb)  — single source for "is this gate met?"
 *   - _prior_gates_satisfied(chain, gate_kind) — the ordering guard the RPC calls.
 *
 * Without the guard, a member eligible for a LATER gate (e.g. volunteers_in_role_active,
 * order 5) could sign before submitter_acceptance/president_go and — because that gate
 * sets v_is_member_ratify=true — mint a premature IPRAT certificate + signature record.
 *
 * Tested at the predicate boundary (same convention as cert-director-go-gate.test.mjs,
 * which exercises the `_`-prefixed authority helpers directly; the full sign flow needs
 * auth.uid() and would mutate prod). Everything is derived from LIVE state — no hardcoded
 * member/chain UUIDs — so it survives roster changes and gate signing progress.
 *
 * Requires: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY. Skipped otherwise.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

const ANY_UUID = '00000000-0000-0000-0000-000000000000';

function headers() {
  return {
    'Content-Type': 'application/json',
    apikey: SERVICE_ROLE_KEY,
    Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
  };
}

async function rpc(fn, args) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify(args),
  });
  if (!res.ok) throw new Error(`rpc ${fn} HTTP ${res.status}: ${await res.text()}`);
  return res.json();
}

async function getRows(query) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${query}`, { headers: headers() });
  if (!res.ok) throw new Error(`query ${query} HTTP ${res.status}: ${await res.text()}`);
  return res.json();
}

// ── _gate_threshold_met branch logic (hermetic — uses a non-existent chain/kind) ──
test(canRun ? '_gate_threshold_met: threshold-0 acknowledge gate is trivially met' : skipMsg, { skip: !canRun }, async () => {
  const met = await rpc('_gate_threshold_met', { p_chain_id: ANY_UUID, p_gate: { kind: 'no_such_gate_kind', threshold: 0 } });
  assert.equal(met, true, 'a threshold-0 gate requires nothing → met (does not block downstream gates)');
});

test(canRun ? '_gate_threshold_met: numeric threshold with zero signoffs is NOT met (fail-closed)' : skipMsg, { skip: !canRun }, async () => {
  const met = await rpc('_gate_threshold_met', { p_chain_id: ANY_UUID, p_gate: { kind: 'no_such_gate_kind', threshold: 1 } });
  assert.equal(met, false, '0 signoffs < threshold 1 → not met');
});

test(canRun ? "_gate_threshold_met: 'all' with zero eligible signers is vacuously met" : skipMsg, { skip: !canRun }, async () => {
  const met = await rpc('_gate_threshold_met', { p_chain_id: ANY_UUID, p_gate: { kind: 'no_such_gate_kind', threshold: 'all' } });
  assert.equal(met, true, "0 signoffs >= 0 eligible → 'all' vacuously met (byte-equivalent to legacy inline counting)");
});

// ── _prior_gates_satisfied ordering enforcement — the #654 fix ──
test(canRun ? 'out-of-order signature is REJECTED: every gate after the first-unmet gate is ordering-blocked' : skipMsg, { skip: !canRun }, async () => {
  // The volunteer-term chain is the canonical #654 case (volunteers_in_role_active, order 5).
  const chains = await getRows('approval_chains?status=eq.review&select=id,gates');
  const chain = chains.find((c) => Array.isArray(c.gates) && c.gates.some((g) => g.kind === 'volunteers_in_role_active'));
  assert.ok(chain, 'expected a review chain carrying a volunteers_in_role_active gate');

  const gates = [...chain.gates].sort((a, b) => Number(a.order) - Number(b.order));

  // met-state per gate, from the single-source helper.
  const met = [];
  for (const g of gates) {
    met.push(await rpc('_gate_threshold_met', { p_chain_id: chain.id, p_gate: g }));
  }
  const firstUnmet = met.findIndex((m) => m === false);
  assert.ok(firstUnmet >= 0, 'expected at least one unmet gate (the chain is mid-flight, not fully approved)');

  // Invariant 1 (the fix): every gate strictly after the first-unmet gate is blocked.
  for (let i = firstUnmet + 1; i < gates.length; i++) {
    const ok = await rpc('_prior_gates_satisfied', { p_chain_id: chain.id, p_gate_kind: gates[i].kind });
    assert.equal(ok, false,
      `gate '${gates[i].kind}' (order ${gates[i].order}) must be blocked — prior gate '${gates[firstUnmet].kind}' (order ${gates[firstUnmet].order}) is unmet`);
  }

  // Invariant 2 (no false positives): the first-unmet gate and everything before it
  // have all strictly-lower gates met → must stay signable.
  for (let i = 0; i <= firstUnmet; i++) {
    const ok = await rpc('_prior_gates_satisfied', { p_chain_id: chain.id, p_gate_kind: gates[i].kind });
    assert.equal(ok, true,
      `gate '${gates[i].kind}' (order ${gates[i].order}) has all lower gates met → must stay signable (no false-positive block)`);
  }
});

// ── consistency: the write guard agrees with "all lower-ordered gates met" everywhere ──
// This is the encoded differential that lets get_pending_ratifications (read) and the
// sign_ip_ratification guard (write) share _prior_gates_satisfied without divergence.
test(canRun ? '_prior_gates_satisfied == "all lower-ordered gates met" for every gate on every active chain' : skipMsg, { skip: !canRun }, async () => {
  const chains = await getRows('approval_chains?status=in.(review,approved)&select=id,gates');
  let checked = 0;
  for (const chain of chains) {
    if (!Array.isArray(chain.gates)) continue;
    const gates = [...chain.gates].sort((a, b) => Number(a.order) - Number(b.order));

    const metByKind = {};
    for (const g of gates) {
      metByKind[g.kind] = await rpc('_gate_threshold_met', { p_chain_id: chain.id, p_gate: g });
    }
    for (const g of gates) {
      const expected = gates
        .filter((p) => Number(p.order) < Number(g.order))
        .every((p) => metByKind[p.kind] === true);
      const actual = await rpc('_prior_gates_satisfied', { p_chain_id: chain.id, p_gate_kind: g.kind });
      assert.equal(actual, expected,
        `chain ${chain.id} gate '${g.kind}': _prior_gates_satisfied=${actual} but lower-gates-all-met=${expected}`);
      checked++;
    }
  }
  assert.ok(checked > 0, 'expected at least one active chain with gates to check');
});
