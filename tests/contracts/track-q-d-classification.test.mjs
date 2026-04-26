/**
 * Track Q-D classification contract — canonical regex correctness.
 *
 * The original p55 detection regex caused 9 false-positive "no-gate"
 * classifications during Q-D triage because it failed to recognize
 * `can(person_id, ...)` patterns without `public.` prefix as V4_can.
 * The mistake led to 9 already-V4-compliant fns being incorrectly
 * flagged for REVOKE in batches 3a.3 + 3a.6 (caught by per-fn body
 * review, not by automation).
 *
 * This contract test asserts that the canonical helper RPC
 * `_audit_classify_function_gate(text)` correctly classifies known
 * fns into their expected gate_kind. Catches future regex regressions
 * before they reach Q-D batch design.
 *
 * Test cases include:
 *   - V4_can_by_member: positive cases (the canonical pattern)
 *   - V4_can: positive cases incl. previously-missed `v_caller_person_id`,
 *     `p.id` patterns
 *   - V3_legacy: positive cases (operational_role / is_superadmin)
 *   - CUSTOM_auth_uid: positive (auth.uid() gates outside V3/V4)
 *   - NO_GATE: positive (helpers without authority check)
 *
 * Requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY for DB-aware
 * assertions. Skips gracefully when env vars missing.
 *
 * Run locally:
 *   SUPABASE_URL=https://…supabase.co SUPABASE_SERVICE_ROLE_KEY=eyJ… \
 *   node --test tests/contracts/track-q-d-classification.test.mjs
 */
import test from 'node:test';
import assert from 'node:assert/strict';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

// Known fixtures — fn name → expected gate_kind
// These represent the 9 V4-discovered surplus from p58/p59 + canonical examples
const FIXTURES = [
  // V4_can_by_member — canonical pattern (catches admin gate via member ID)
  { fn: 'get_chain_audit_report',         expected: 'V4_can_by_member' },
  { fn: 'get_curation_dashboard',         expected: 'V4_can_by_member' },
  { fn: 'get_governance_change_log',      expected: 'V4_can_by_member' },

  // V4_can — was p55 false-positive ("NO_GATE") because regex missed
  // `can(v_caller_person_id, ...)` pattern
  { fn: 'get_initiative_member_contacts', expected: 'V4_can' },

  // V3_legacy — uses operational_role / is_superadmin
  { fn: 'admin_manage_comms_channel',     expected: 'V3_legacy' },
  { fn: 'get_change_requests',            expected: 'V3_legacy' },

  // CUSTOM_auth_uid — uses auth.uid() but is RLS helper, not V3/V4
  { fn: 'rls_can',                        expected: 'CUSTOM_auth_uid' },
  { fn: 'rls_is_member',                  expected: 'CUSTOM_auth_uid' },

  // NO_GATE — truly no authority check (V4 core or pure helper/dead)
  { fn: 'tribe_impact_ranking',           expected: 'NO_GATE' },
  { fn: 'can_by_member',                  expected: 'NO_GATE' },  // IS the gate, no internal check
];

async function classify(functionName) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/_audit_classify_function_gate`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({ p_function_name: functionName }),
  });
  if (!res.ok) {
    throw new Error(`classify RPC failed for ${functionName}: ${res.status} ${await res.text()}`);
  }
  return res.json();
}

test(
  'Track Q-D: canonical classification regex correctly identifies all known fixtures',
  { skip: !canRun && skipMsg },
  async () => {
    const failures = [];

    for (const { fn, expected } of FIXTURES) {
      const result = await classify(fn);
      const actual = result?.gate_kind ?? 'MISSING';

      if (actual !== expected) {
        failures.push({ fn, expected, actual });
      }
    }

    if (failures.length > 0) {
      const lines = failures.map(
        f => `  ${f.fn.padEnd(40)} expected=${f.expected.padEnd(20)} actual=${f.actual}`
      );
      assert.fail(
        `Q-D classification regex regressed on ${failures.length} fixtures.\n\n` +
          `If these failures are intentional (pattern intentionally re-shaped),\n` +
          `update FIXTURES in this test. Otherwise, fix the regex in the\n` +
          `_audit_classify_function_gate() helper migration.\n\n` +
          `Failures:\n${lines.join('\n')}`
      );
    }
  }
);

test(
  'Track Q-D: classification helper returns expected jsonb shape',
  { skip: !canRun && skipMsg },
  async () => {
    const result = await classify('can_by_member');
    assert.equal(typeof result, 'object');
    assert.equal(typeof result.proname, 'string');
    assert.equal(typeof result.sig, 'string');
    assert.equal(typeof result.gate_kind, 'string');
    assert.equal(typeof result.is_secdef, 'boolean');
    assert.equal(typeof result.body_chars, 'number');

    const validGateKinds = ['V4_can_by_member', 'V4_can', 'V3_legacy', 'CUSTOM_auth_uid', 'NO_GATE'];
    assert.ok(
      validGateKinds.includes(result.gate_kind),
      `gate_kind '${result.gate_kind}' is not one of ${validGateKinds.join(', ')}`
    );
  }
);
