/**
 * ADR-0016 Amendment 3 contract — preview_gate_eligibles_cache equivalence.
 *
 * Asserts that for every (cacheable_doc_type × cacheable_gate_kind) combo,
 * the cache count matches the live `_can_sign_gate` count. Drift would mean
 * the cache is silently lying about who is eligible to sign — a governance
 * compliance hazard.
 *
 * Backed by SECDEF helper `_audit_preview_gate_eligibles_drift()` which
 * does the comparison server-side and returns jsonb array. The test calls
 * via service-role REST (helper REVOKEs anon/authenticated).
 *
 * Skip when SUPABASE_SERVICE_ROLE_KEY is absent (offline runs).
 */
import test from 'node:test';
import assert from 'node:assert/strict';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

async function callAuditDrift() {
  const url = `${SUPABASE_URL}/rest/v1/rpc/_audit_preview_gate_eligibles_drift`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({}),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`audit RPC failed: HTTP ${res.status} — ${text}`);
  }
  return await res.json();
}

async function callPreviewRpc(docType, submitterId) {
  const url = `${SUPABASE_URL}/rest/v1/rpc/preview_gate_eligibles`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({ p_doc_type: docType, p_submitter_id: submitterId }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`preview RPC failed: HTTP ${res.status} — ${text}`);
  }
  return await res.json();
}

const CACHEABLE_DOC_TYPES = [
  'cooperation_agreement',
  'cooperation_addendum',
  'volunteer_term_template',
  'volunteer_addendum',
  'policy',
];

test(
  canRun ? 'preview_gate_eligibles cache matches live for all cacheable (doc_type, gate)' : skipMsg,
  { skip: !canRun },
  async () => {
    const drift = await callAuditDrift();
    assert.ok(Array.isArray(drift), 'audit RPC should return array');
    assert.ok(drift.length > 0, 'audit RPC should return at least one row');

    const mismatches = drift.filter((r) => r.mismatch === true);
    if (mismatches.length > 0) {
      const lines = mismatches.map(
        (m) => `  ${m.doc_type}/${m.gate_kind}: cache=${m.cache_count} live=${m.live_count}`,
      );
      assert.fail(
        `Cache↔live drift detected on ${mismatches.length} (doc_type, gate) tuples:\n${lines.join('\n')}\n\nLikely root cause: trigger missed an invalidation path, or a recent migration changed _can_sign_gate semantics without rebuilding cache. Run refresh_preview_gate_eligibles_cache_all() and re-test.`,
      );
    }

    // Sanity: every cacheable doc_type appeared at least once
    const docTypesSeen = new Set(drift.map((r) => r.doc_type));
    for (const dt of CACHEABLE_DOC_TYPES) {
      assert.ok(
        docTypesSeen.has(dt),
        `audit must include doc_type "${dt}" (helper _cacheable_preview_doc_types() drifted?)`,
      );
    }

    // Sanity: submitter_acceptance never present (it's not cacheable)
    const submitterRows = drift.filter((r) => r.gate_kind === 'submitter_acceptance');
    assert.equal(
      submitterRows.length,
      0,
      'submitter_acceptance must not appear in cache audit — it is per-call-only',
    );
  },
);

test(
  canRun ? 'preview_gate_eligibles RPC reports source field per gate' : skipMsg,
  { skip: !canRun },
  async () => {
    const result = await callPreviewRpc('cooperation_agreement', null);
    assert.ok(Array.isArray(result), 'preview RPC should return array');
    assert.ok(result.length >= 1, 'preview RPC should return at least one gate row');

    for (const gate of result) {
      assert.ok(
        ['cache', 'live', 'live_fallback'].includes(gate.source),
        `gate ${gate.gate_kind} has invalid source "${gate.source}"`,
      );
      // submitter_acceptance is always live
      if (gate.gate_kind === 'submitter_acceptance') {
        assert.equal(
          gate.source,
          'live',
          'submitter_acceptance must report source=live (per-call dependency)',
        );
      }
    }
  },
);

test(
  canRun
    ? 'preview_gate_eligibles returns NULL for non-cacheable doc_types (executive_summary)'
    : skipMsg,
  { skip: !canRun },
  async () => {
    const result = await callPreviewRpc('executive_summary', null);
    assert.equal(
      result,
      null,
      'doc_types without resolve_default_gates entry must return NULL',
    );
  },
);
