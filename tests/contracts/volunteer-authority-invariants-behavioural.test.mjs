/**
 * V4 volunteer authority invariants — BEHAVIOURAL forward-defense
 *
 * Origin: GAP-204.B (p204 council Tier 1 carry, p206 close — Issue #213).
 * Companion to the static contract suite at
 *   tests/contracts/volunteer-authority-invariants.test.mjs
 * which parses the migration SQL (text matching) but never exercises the
 * function at runtime.
 *
 * Why behavioural matters:
 *   - The static suite confirms `check_schema_invariants()` *declares* R and
 *     S rows with the expected CTE shape. It does NOT confirm:
 *       (a) those rows are returned with violation_count=0 in production
 *           today (deploy-state invariant), nor
 *       (b) the CTE actually detects a real breach if one is introduced
 *           (forward-defense regression catcher).
 *   - This suite covers (a) + (b) via service_role HTTP calls to PostgREST.
 *
 * Forward-defense pattern (mirrors p186 OPP-185.A):
 *   - Tests #3 + #4 call the test-only helper RPC
 *     `_test_invariants_with_synthetic_breach(p_breach text)` which seeds a
 *     synthetic R or S violation inside a single PostgREST request.
 *   - Caller adds `Prefer: tx=rollback` so PostgREST rolls back the entire
 *     transaction at request end — the synthetic rows never persist.
 *   - Belt-and-suspenders: the helper has `SECURITY DEFINER` + GRANT EXECUTE
 *     scoped to `service_role` only (REVOKE FROM anon, authenticated, PUBLIC).
 *     Even if `Prefer: tx=rollback` were misused by an authenticated caller,
 *     the GRANT scope prevents the helper from running at all under that role.
 *
 * Requires: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY. Skipped otherwise.
 *
 * Test ordering dependency (council Tier 1 code-reviewer HIGH, p206):
 *   Tests #3 + #4 include a post-test "LEAK DETECTED" assertion that re-reads
 *   the live invariants and expects R=0 + S=0. This assertion correctly
 *   discriminates "tx=rollback failed (leak)" from "real prod violation"
 *   ONLY IF tests #1 + #2 have run first and confirmed baseline=0. node:test
 *   defaults to in-file declaration order, so the four tests in this file
 *   run #1 → #2 → #3 → #4 sequentially. If a future runner shuffles them or
 *   tests run in isolation (e.g., `--test-name-pattern`), the post-test
 *   assertions may misidentify a pre-existing prod R/S violation as a
 *   helper leak. Treat that as a discovery, not a leak — verify against
 *   tests #1/#2 in the same session.
 *
 * Related:
 *   - PR #199 / Issue #180: defined R + S in `check_schema_invariants()`.
 *   - PR #198 / Issue #179: canonical `approve_selection_application` whose
 *     bypass these invariants are designed to detect.
 *   - Migration `20260731000000_p206_gap_204_b_invariant_breach_helper.sql`.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

const R_NAME = 'R_approved_application_has_member';
const S_NAME = 'S_approved_member_has_person_id';

async function callCheckInvariants() {
  // Calls `check_schema_invariants()` via PostgREST service_role. Returns the
  // full 18-row array (caller filters for R/S).
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
    throw new Error(`check_schema_invariants RPC failed: HTTP ${res.status} — ${text}`);
  }
  return await res.json();
}

async function callBreachHelper(breach) {
  // Calls `_test_invariants_with_synthetic_breach(p_breach)` via PostgREST
  // service_role with `Prefer: tx=rollback` so the helper's INSERTs into
  // selection_applications (and, for S, members) are rolled back at request
  // end. Returns the R+S rows from check_schema_invariants() captured after
  // the seed but before the rollback.
  const url = `${SUPABASE_URL}/rest/v1/rpc/_test_invariants_with_synthetic_breach`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'apikey': SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      'Prefer': 'tx=rollback',
    },
    body: JSON.stringify({ p_breach: breach }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`breach helper failed (breach=${breach}): HTTP ${res.status} — ${text}`);
  }
  return await res.json();
}

function findInvariant(rows, name) {
  if (!Array.isArray(rows)) {
    throw new Error(`Expected array of invariant rows, got: ${JSON.stringify(rows)}`);
  }
  const row = rows.find((r) => r.invariant_name === name);
  if (!row) {
    throw new Error(`Invariant row '${name}' missing from response — only got: ${rows.map(r => r.invariant_name).join(', ')}`);
  }
  return row;
}

// ───────────────────────────────────────────────────────────────────────────
// Test #1 — R at deploy
// ───────────────────────────────────────────────────────────────────────────
test(
  canRun
    ? 'invariant R (approved_application_has_member) reports violation_count=0 at deploy'
    : skipMsg,
  { skip: !canRun },
  async () => {
    const rows = await callCheckInvariants();
    const r = findInvariant(rows, R_NAME);
    assert.equal(
      r.violation_count, 0,
      `R has ${r.violation_count} violation(s) at deploy — approved selection_applications exist without matching members row. ` +
      `Sample ids: ${JSON.stringify(r.sample_ids ?? [])}. Likely cause: bypass of approve_selection_application() canonical RPC (Issue #179) ` +
      `or import_vep_applications creating an approved row without orchestrating member creation.`
    );
    assert.equal(r.severity, 'high', 'R severity should be high');
    // sample_ids is null when count=0, array when count>0
    assert.ok(
      r.sample_ids === null || (Array.isArray(r.sample_ids) && r.sample_ids.length === 0),
      `R has count=0 but sample_ids is non-empty: ${JSON.stringify(r.sample_ids)}`
    );
  }
);

// ───────────────────────────────────────────────────────────────────────────
// Test #2 — S at deploy
// ───────────────────────────────────────────────────────────────────────────
test(
  canRun
    ? 'invariant S (approved_member_has_person_id) reports violation_count=0 at deploy'
    : skipMsg,
  { skip: !canRun },
  async () => {
    const rows = await callCheckInvariants();
    const s = findInvariant(rows, S_NAME);
    assert.equal(
      s.violation_count, 0,
      `S has ${s.violation_count} violation(s) at deploy — members tied to approved applications exist with person_id IS NULL. ` +
      `Sample ids: ${JSON.stringify(s.sample_ids ?? [])}. Likely cause: legacy member created before V4 person_id linking ` +
      `(canonical approve_selection_application always links person_id post-approval, so any drift here = pre-V4 path).`
    );
    assert.equal(s.severity, 'high', 'S severity should be high');
  }
);

// ───────────────────────────────────────────────────────────────────────────
// Test #3 — R correctly detects synthetic missing-member breach
// ───────────────────────────────────────────────────────────────────────────
test(
  canRun
    ? 'invariant R correctly detects synthetic breach (forward-defense)'
    : skipMsg,
  { skip: !canRun },
  async () => {
    // Helper inserts a synthetic selection_applications row with
    // status='approved' and an email that does NOT match any existing member.
    // The R CTE should flag this row as a violation. tx=rollback at
    // request end drops the synthetic row before this test's transaction
    // commits — zero leakage into prod data.
    const breachRows = await callBreachHelper('R');
    const r = findInvariant(breachRows, R_NAME);
    const s = findInvariant(breachRows, S_NAME);

    // Behavioural assertion: R should now flag at least the synthetic row.
    assert.ok(
      r.violation_count >= 1,
      `R failed to detect synthetic breach — violation_count=${r.violation_count} (expected >= 1). ` +
      `CTE may have drifted from the documented semantics (Issue #180). ` +
      `Helper seeded an approved application with unique email matching no member.`
    );
    assert.ok(
      Array.isArray(r.sample_ids) && r.sample_ids.length >= 1,
      `R reported count=${r.violation_count} but sample_ids is empty: ${JSON.stringify(r.sample_ids)}`
    );

    // S should NOT detect anything from the R breach (the synthetic app has
    // no matching member, so the S join produces no rows).
    assert.equal(
      s.violation_count, 0,
      `S incorrectly counts ${s.violation_count} for R-only breach — the synthetic app has no matching member ` +
      `so S CTE should produce 0 rows. Sample ids: ${JSON.stringify(s.sample_ids ?? [])}.`
    );

    // Post-test verification: confirm tx=rollback dropped the synthetic row.
    // (If this fails, we have a leak — the helper should have left zero trace.)
    const postRows = await callCheckInvariants();
    const postR = findInvariant(postRows, R_NAME);
    assert.equal(
      postR.violation_count, 0,
      `LEAK DETECTED: post-test R violation_count=${postR.violation_count} (expected 0). ` +
      `Prefer: tx=rollback failed to revert the synthetic application. Sample ids: ${JSON.stringify(postR.sample_ids ?? [])}.`
    );
  }
);

// ───────────────────────────────────────────────────────────────────────────
// Test #4 — S correctly detects synthetic NULL-person_id breach
// ───────────────────────────────────────────────────────────────────────────
test(
  canRun
    ? 'invariant S correctly detects synthetic breach (forward-defense)'
    : skipMsg,
  { skip: !canRun },
  async () => {
    // Helper inserts a synthetic approved application AND a member with
    // matching email + person_id=NULL. The S CTE should flag the member.
    // R should NOT flag because the member exists (the join finds it).
    const breachRows = await callBreachHelper('S');
    const r = findInvariant(breachRows, R_NAME);
    const s = findInvariant(breachRows, S_NAME);

    assert.ok(
      s.violation_count >= 1,
      `S failed to detect synthetic breach — violation_count=${s.violation_count} (expected >= 1). ` +
      `CTE may have drifted from the documented semantics (Issue #180). ` +
      `Helper seeded an approved application + matching member with person_id=NULL.`
    );
    assert.ok(
      Array.isArray(s.sample_ids) && s.sample_ids.length >= 1,
      `S reported count=${s.violation_count} but sample_ids is empty: ${JSON.stringify(s.sample_ids)}`
    );

    // R should NOT flag for an S-only breach — the synthetic member matches
    // the synthetic app's email, so R's NOT EXISTS check finds the member.
    assert.equal(
      r.violation_count, 0,
      `R incorrectly counts ${r.violation_count} for S-only breach — the synthetic member exists with matching email ` +
      `so R CTE should produce 0 rows. Sample ids: ${JSON.stringify(r.sample_ids ?? [])}.`
    );

    // Post-test verification: confirm tx=rollback dropped both synthetic rows.
    const postRows = await callCheckInvariants();
    const postR = findInvariant(postRows, R_NAME);
    const postS = findInvariant(postRows, S_NAME);
    assert.equal(
      postR.violation_count, 0,
      `LEAK DETECTED: post-test R violation_count=${postR.violation_count}. tx=rollback failed.`
    );
    assert.equal(
      postS.violation_count, 0,
      `LEAK DETECTED: post-test S violation_count=${postS.violation_count}. tx=rollback failed.`
    );
  }
);
