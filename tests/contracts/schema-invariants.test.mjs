/**
 * ADR-0012 B10 — Query-based schema invariants (anti-drift, live DB)
 *
 * Static analysis tests (rpc-v4-auth, authority-derivation) check migration
 * text. This test calls check_schema_invariants() against the live database
 * and asserts that every invariant returns violation_count = 0.
 *
 * Any non-zero count means drift that triggers did not catch — typically
 * introduced via service_role direct UPDATE that bypassed BEFORE triggers,
 * or an edge case in a trigger (e.g. engagement_kinds.requires_agreement
 * changed without a corresponding re-sync).
 *
 * Requires: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY. Skipped otherwise.
 *
 * Run locally:
 *   SUPABASE_URL=https://…supabase.co SUPABASE_SERVICE_ROLE_KEY=eyJ… \
 *   node --test tests/contracts/schema-invariants.test.mjs
 *
 * In CI: set the two env vars as secrets (read-only: RPC only SELECTs).
 */
import test from 'node:test';
import assert from 'node:assert/strict';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

async function callInvariantRpc() {
  const url = `${SUPABASE_URL}/rest/v1/rpc/check_schema_invariants`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'apikey': SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({}),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`RPC failed: HTTP ${res.status} — ${text}`);
  }
  return res.json();
}

// Single-call, multi-assert: one RPC hit, one row per invariant.
test('ADR-0012 B10: schema invariants report', { skip: !canRun && skipMsg }, async (t) => {
  const rows = await callInvariantRpc();

  assert.ok(Array.isArray(rows), 'RPC must return an array');
  assert.ok(rows.length >= 8, `Expected 8+ invariants, got ${rows.length}`);

  const byName = Object.fromEntries(rows.map(r => [r.invariant_name, r]));
  const expected = [
    'A1_alumni_role_consistency',
    'A2_observer_role_consistency',
    'A3_active_role_engagement_derivation',
    'B_is_active_status_mismatch',
    'C_designations_in_terminal_status',
    'D_auth_id_mismatch_person_member',
    'E_engagement_active_with_terminal_member',
    'F_initiative_legacy_tribe_orphan',
  ];

  for (const name of expected) {
    await t.test(`${name} — 0 violations`, () => {
      const row = byName[name];
      assert.ok(row, `Invariant ${name} missing from RPC output`);
      if (row.violation_count !== 0) {
        const samples = Array.isArray(row.sample_ids) ? row.sample_ids.join(', ') : '';
        assert.fail(
          `${name} (${row.severity}): ${row.violation_count} violation(s)\n` +
          `  ${row.description}\n` +
          `  sample IDs: ${samples}\n` +
          `  Query locally to investigate: SELECT * FROM public.check_schema_invariants();`
        );
      }
      assert.strictEqual(row.violation_count, 0);
    });
  }
});

test('ADR-0012 B10: invariant output shape', { skip: !canRun && skipMsg }, async () => {
  const rows = await callInvariantRpc();
  for (const row of rows) {
    assert.ok(typeof row.invariant_name === 'string', 'invariant_name must be string');
    assert.ok(typeof row.description === 'string', 'description must be string');
    assert.ok(['high', 'medium', 'low'].includes(row.severity),
      `severity must be high|medium|low, got: ${row.severity}`);
    assert.ok(Number.isInteger(row.violation_count), 'violation_count must be integer');
    assert.ok(row.violation_count >= 0, 'violation_count must be non-negative');
  }
});
