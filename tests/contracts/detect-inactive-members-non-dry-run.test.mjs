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
 * Coverage gap acknowledged:
 *   With production threshold=180, candidates_count may be 0 at CI time, in which
 *   case the IF NOT p_dry_run AND v_count > 0 gate skips the INSERT block and this
 *   test does NOT directly exercise the INSERT path. Test still catches:
 *     - response shape regressions
 *     - dispatch errors (syntax breakage in function body)
 *     - auth gate regressions
 *     - non-zero candidate path constraint violations (when prod has candidates)
 *   To get hermetic INSERT-path coverage, a future test helper RPC could force
 *   candidates>0 inside a tx=rollback request. Out of scope for p185 (WATCH-180.F
 *   already closed by runtime exercise above).
 *
 * What this test does:
 *   1. Calls detect_inactive_members(p_dry_run := true) via service_role:
 *      validates response shape (candidates array, counters, no errors).
 *   2. Calls detect_inactive_members(p_dry_run := false) with `Prefer: tx=rollback`
 *      header so all INSERT side effects (notifications + admin_audit_log) are
 *      rolled back at request end. PostgREST honors tx=rollback for stateless
 *      RPC calls when the role can use it (service_role permitted).
 *   3. Asserts the call returns successfully (no 23502, no other constraint
 *      violation, no Unauthorized given service_role bypass). If the contract
 *      breaks at runtime, this test fails BEFORE the next scheduled cron run.
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
