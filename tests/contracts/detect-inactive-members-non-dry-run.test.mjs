/**
 * detect_inactive_members non-dry-run pre-cron safety contract
 *
 * Forward-defense for the cron-scheduled non-dry-run execution that will run
 * for the first time at sat 2026-05-23 09:30 BRT (5 days after p185 boot).
 *
 * Context:
 *   - p179 introduced detect_inactive_members(p_dry_run boolean DEFAULT true)
 *     with `INSERT INTO admin_audit_log (..., target_type, ...) VALUES (..., NULL, ...)`.
 *     The fn only ran with p_dry_run=true in prod (skips the INSERT block), so
 *     the latent bug (23502 NOT NULL violation on admin_audit_log.target_type)
 *     was invisible at runtime.
 *   - p180 council mid-sweep caught the latent bug via static review.
 *     Migration 20260690000000 fixed: NULL → 'system_event' explicit.
 *   - The fix has NEVER been exercised at runtime — every call so far is dry_run=true.
 *
 * Runtime exercise (one-time, p185 boot 2026-05-17 via MCP execute_sql):
 *   BEGIN; UPDATE site_config SET value='0'::jsonb WHERE key='inactivity_threshold_days';
 *   SELECT detect_inactive_members(false); ROLLBACK;
 *   → candidates_count=49, managers_notified=2, success=true, ZERO constraint errors.
 *   Confirmed INSERTs into notifications + admin_audit_log (target_type='system_event')
 *   work correctly. ROLLBACK reverted threshold to 180 + 0 persisted rows.
 *   Cron sat 2026-05-23 09:30 BRT is now GREEN for first multi-leader V4 execution.
 *
 * Coverage gap (p185) → CLOSED p186 (OPP-185.A):
 *   Originally, with production threshold=180, candidates_count may be 0 at CI
 *   time, skipping the IF block and bypassing INSERT-path coverage. p186 added
 *   the test helper RPC _test_detect_inactive_with_threshold(int) which forces
 *   candidates>0 by lowering the threshold within a tx=rollback request. Test #3
 *   below uses it to deterministically exercise the INSERT branch in CI.
 *
 * What this test does:
 *   1. Calls detect_inactive_members(p_dry_run := true) via service_role:
 *      validates response shape (candidates array, counters, no errors).
 *   2. Calls detect_inactive_members(p_dry_run := false) with `Prefer: tx=rollback`
 *      header so all INSERT side effects (notifications + admin_audit_log) are
 *      rolled back at request end. PostgREST honors tx=rollback for stateless
 *      RPC calls when the role can use it (service_role permitted).
 *   3. Calls _test_detect_inactive_with_threshold(0) with `Prefer: tx=rollback`:
 *      forces candidates>0 so the INSERT branch executes deterministically in CI.
 *      Asserts managers_notified>0 and candidates_count>0 — hermetic INSERT-path
 *      coverage that doesn't depend on prod state at test time.
 *   In all three cases, if the contract breaks at runtime the test fails BEFORE
 *   the next scheduled cron run (no 23502, no other constraint violation, no
 *   Unauthorized given service_role bypass).
 *
 * Why tx=rollback (not actual INSERT + cleanup):
 *   - notifications INSERT could trigger downstream consumers (realtime/email).
 *     Rolling back the transaction means consumers never see the rows.
 *   - admin_audit_log INSERT is append-only; the row exists momentarily but is
 *     never committed.
 *   - PostgREST docs: https://docs.postgrest.org/en/v12/references/transactions.html
 *
 * Requires: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY. Skipped otherwise.
 *
 * Origin: WATCH-180.F closure (handoff p184 TIER A).
 */
import test from 'node:test';
import assert from 'node:assert/strict';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

async function callDetectInactive(dryRun, options = {}) {
  const url = `${SUPABASE_URL}/rest/v1/rpc/detect_inactive_members`;
  const headers = {
    'Content-Type': 'application/json',
    'apikey': SERVICE_ROLE_KEY,
    'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
  };
  if (options.rollback) headers['Prefer'] = 'tx=rollback';

  const res = await fetch(url, {
    method: 'POST',
    headers,
    body: JSON.stringify({ p_dry_run: dryRun }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`RPC failed (dryRun=${dryRun}, rollback=${!!options.rollback}): HTTP ${res.status} — ${text}`);
  }
  return await res.json();
}

async function callTestHelperWithThreshold(threshold) {
  // p186 OPP-185.A: helper RPC that forces candidates>0 by temporarily
  // overriding site_config.inactivity_threshold_days. Must be invoked with
  // Prefer: tx=rollback to guarantee zero persisted side effects.
  const url = `${SUPABASE_URL}/rest/v1/rpc/_test_detect_inactive_with_threshold`;
  const headers = {
    'Content-Type': 'application/json',
    'apikey': SERVICE_ROLE_KEY,
    'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
    'Prefer': 'tx=rollback',
  };
  const res = await fetch(url, {
    method: 'POST',
    headers,
    body: JSON.stringify({ p_threshold: threshold }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Helper RPC failed (threshold=${threshold}): HTTP ${res.status} — ${text}`);
  }
  return await res.json();
}

test(
  canRun ? 'detect_inactive_members dry_run=true returns valid shape' : skipMsg,
  { skip: !canRun },
  async () => {
    const result = await callDetectInactive(true);
    assert.equal(result.success, true, 'success flag should be true');
    assert.equal(result.dry_run, true, 'dry_run flag should echo true');
    assert.equal(typeof result.threshold_days, 'number', 'threshold_days should be number');
    assert.ok(result.threshold_days > 0, 'threshold_days should be positive');
    assert.equal(typeof result.candidates_count, 'number', 'candidates_count should be number');
    assert.ok(result.candidates_count >= 0, 'candidates_count should be non-negative');
    assert.ok(Array.isArray(result.candidates), 'candidates should be array');
    assert.equal(result.managers_notified, 0, 'dry_run skips INSERT block → managers_notified must be 0');
  }
);

test(
  canRun ? 'detect_inactive_members dry_run=false with tx=rollback executes without constraint errors' : skipMsg,
  { skip: !canRun },
  async () => {
    // Pre-cron safety: validates that the runtime INSERT path (notifications +
    // admin_audit_log) does not throw 23502 or any other constraint violation.
    // All side effects rolled back by PostgREST Prefer: tx=rollback.
    const result = await callDetectInactive(false, { rollback: true });
    assert.equal(result.success, true, 'success flag should be true (no INSERT errors)');
    assert.equal(result.dry_run, false, 'dry_run flag should echo false');
    assert.equal(typeof result.candidates_count, 'number', 'candidates_count should be number');
    assert.equal(typeof result.managers_notified, 'number', 'managers_notified should be number');
    assert.ok(result.managers_notified >= 0, 'managers_notified should be non-negative');

    // If there ARE inactive candidates, the function should notify at least one
    // manager (assuming the install has at least one member with manage_platform
    // capability — which is required for the platform to be operational at all).
    if (result.candidates_count > 0) {
      assert.ok(
        result.managers_notified > 0,
        `candidates_count=${result.candidates_count} but managers_notified=0 — manage_platform capability may be missing or filter logic broken`
      );
    }
  }
);

test(
  canRun
    ? 'detect_inactive_members INSERT path hermetically exercised via _test helper (threshold=0)'
    : skipMsg,
  { skip: !canRun },
  async () => {
    // p186 OPP-185.A: hermetic INSERT-path coverage. The previous tx=rollback
    // test only exercises the INSERT block if prod has candidates_count > 0
    // at CI time. This test calls _test_detect_inactive_with_threshold(0)
    // which forces every active member to qualify as a candidate (last
    // attendance > 0 days ago is trivially true), guaranteeing v_count > 0
    // and the IF NOT p_dry_run AND v_count > 0 branch executes. The helper
    // restores site_config.inactivity_threshold_days defensively before
    // returning AND tx=rollback drops every persisted row at request end.
    const result = await callTestHelperWithThreshold(0);

    assert.equal(result.success, true, 'success flag should be true');
    assert.equal(result.dry_run, false, 'dry_run must echo false (helper passes false)');
    assert.equal(result.threshold_days, 0, 'threshold_days should reflect the override value (0)');
    assert.ok(result.candidates_count > 0, 'threshold=0 must produce at least one candidate');
    assert.ok(Array.isArray(result.candidates), 'candidates should be array');
    assert.ok(
      result.managers_notified > 0,
      `INSERT path coverage requires managers_notified > 0 (got ${result.managers_notified}) — ` +
      'either manage_platform capability is missing or notifications INSERT branch silently failed'
    );
  }
);
