/**
 * ADR-0016 Amendment 4 — gate_kind `cert_director_go` (Diretoria de Certificação PMI-GO)
 *
 * Locks the end-to-end DB contract introduced by migration
 * 20260805000152_adr0016_amendment_4_cert_director_go:
 *   - _validate_gates_shape accepts the new kind (so a chain can carry it) and still
 *     rejects an unknown kind (allowlist is enforced, not bypassed).
 *   - _can_sign_gate eligibility predicate: PMI-GO + certificacao_director designation,
 *     doc_type-scoped to project_charter; non-cert PMI-GO members are denied; the scope
 *     denies non-charter doc_types.
 *   - _ip_ratify_cta_link routes the gate to the member-facing /governance/documents/ page
 *     (non-admin signers), NOT the /admin/ surface.
 *
 * Predicate is asserted by DESIGNATION lookup (not a hard-coded member UUID) so the test
 * survives roster changes.
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

async function findMember(query) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/members?${query}`, { headers: headers() });
  if (!res.ok) throw new Error(`members query HTTP ${res.status}: ${await res.text()}`);
  const rows = await res.json();
  return rows[0]?.id ?? null;
}

// ── _validate_gates_shape ──────────────────────────────────────────────────
test(canRun ? 'cert_director_go: _validate_gates_shape accepts the kind' : skipMsg, { skip: !canRun }, async () => {
  const ok = await rpc('_validate_gates_shape', {
    p_gates: [{ kind: 'cert_director_go', order: 3, threshold: 1 }],
  });
  assert.equal(ok, true, 'cert_director_go must be in the gates-shape allowlist');
});

test(canRun ? '_validate_gates_shape still rejects an unknown kind' : skipMsg, { skip: !canRun }, async () => {
  const ok = await rpc('_validate_gates_shape', {
    p_gates: [{ kind: 'definitely_not_a_gate', order: 1, threshold: 1 }],
  });
  assert.equal(ok, false, 'allowlist must still reject unknown kinds (not a wildcard)');
});

// ── _can_sign_gate eligibility predicate ────────────────────────────────────
test(canRun ? 'cert_director_go: certificacao_director (PMI-GO) is eligible on project_charter' : skipMsg, { skip: !canRun }, async () => {
  const certDir = await findMember('chapter=eq.PMI-GO&is_active=eq.true&designations=cs.%7Bcertificacao_director%7D&select=id&limit=1');
  assert.ok(certDir, 'expected at least one active PMI-GO member with certificacao_director designation');

  const onCharter = await rpc('_can_sign_gate', {
    p_member_id: certDir, p_chain_id: null, p_gate_kind: 'cert_director_go',
    p_doc_type: 'project_charter', p_submitter_id: null,
  });
  assert.equal(onCharter, true, 'cert director must be eligible on project_charter');

  // doc_type scoping: NOT eligible on a non-charter doc_type
  const onPolicy = await rpc('_can_sign_gate', {
    p_member_id: certDir, p_chain_id: null, p_gate_kind: 'cert_director_go',
    p_doc_type: 'policy', p_submitter_id: null,
  });
  assert.equal(onPolicy, false, 'cert_director_go is doc_type-scoped to project_charter (policy must deny)');
});

test(canRun ? 'cert_director_go: a PMI-GO member WITHOUT the designation is denied' : skipMsg, { skip: !canRun }, async () => {
  const nonCert = await findMember('chapter=eq.PMI-GO&is_active=eq.true&designations=not.cs.%7Bcertificacao_director%7D&select=id&limit=1');
  assert.ok(nonCert, 'expected at least one active PMI-GO member without certificacao_director');

  const elig = await rpc('_can_sign_gate', {
    p_member_id: nonCert, p_chain_id: null, p_gate_kind: 'cert_director_go',
    p_doc_type: 'project_charter', p_submitter_id: null,
  });
  assert.equal(elig, false, 'a member without certificacao_director must NOT be eligible (fail-closed)');
});

// ── _ip_ratify_cta_link routing ─────────────────────────────────────────────
test(canRun ? 'cert_director_go: CTA routes to the member-facing /governance/documents/ page' : skipMsg, { skip: !canRun }, async () => {
  const link = await rpc('_ip_ratify_cta_link', { p_chain_id: ANY_UUID, p_gate_kind: 'cert_director_go' });
  assert.match(String(link), /^\/governance\/documents\//, 'cert_director_go signer is non-admin → member route, not /admin/');
});
