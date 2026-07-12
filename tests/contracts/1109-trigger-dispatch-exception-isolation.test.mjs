// tests/contracts/1109-trigger-dispatch-exception-isolation.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json
// (SEDIMENT-186.C) before running. (Enforced by 1109-contract-whitelist-completeness.)
/**
 * Guard 1 (#1109, wave-9 harvest from LL #588) — trigger-dispatch EXCEPTION isolation.
 *
 * CLASS: a trigger function that fires an external dispatch (net.http_post, or PERFORM
 * of a *_dispatch function) INSIDE the primary transaction propagates a vault/pg_net
 * failure into the primary write's rollback. Worst case: offboard (which also runs the
 * LGPD Art.18 delete) breaks entirely because the dispatch was down. The correct pattern
 * wraps the dispatch so the side-effect fails SOFT:
 *   BEGIN <vault read + net.http_post> EXCEPTION WHEN OTHERS THEN <log> END;
 *
 * GUARD: the live sweep _audit_trigger_dispatch_without_handler() returns the identities
 * of public trigger functions whose body dispatches externally WITHOUT an
 * EXCEPTION WHEN OTHERS handler. This ratchet asserts that set equals the allowlist
 * (empty at ship — the codebase is currently clean; all 4 dispatch triggers isolate).
 *
 * WHY LIVE (not a static migration grep): dropped/superseded captures in old migrations
 * still contain the pattern (e.g. _trg_video_ai_analysis_on_upload, dropped in p207) —
 * only the CURRENT live bodies matter (same rationale as #730). Skipped without DB creds.
 *
 * PRECISION: "has EXCEPTION WHEN OTHERS" is body-presence, not proof the handler wraps
 * the dispatch — the guard errs toward false-NEGATIVE (a clean function is never flagged),
 * the safe direction for a CI gate.
 *
 * To make this pass when a NEW dispatch trigger appears: wrap the dispatch in an
 * EXCEPTION WHEN OTHERS handler (it leaves the sweep), OR — only if a bare dispatch is
 * genuinely by-design — add its name to ALLOWLIST below WITH a justification comment.
 */

import test from 'node:test';
import assert from 'node:assert/strict';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

// Trigger functions allowed to dispatch externally WITHOUT a handler (by-design).
// Empty at ship — keep it that way. Each entry needs a justification comment.
const ALLOWLIST = new Set([]);

async function callAuditRpc() {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/rpc/_audit_trigger_dispatch_without_handler`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      },
      body: JSON.stringify({}),
    },
  );
  if (!res.ok)
    throw new Error(`audit RPC failed: HTTP ${res.status} — ${await res.text()}`);
  return res.json();
}

test(
  '#1109 Guard 1: every trigger that dispatches externally isolates it with EXCEPTION WHEN OTHERS',
  { skip: canRun ? false : skipMsg },
  async () => {
    const rows = await callAuditRpc();
    const offenders = rows
      .map((r) => r.proname)
      .filter((name) => !ALLOWLIST.has(name));
    assert.deepEqual(
      offenders,
      [],
      `Trigger function(s) dispatch externally (net.http_post / PERFORM *_dispatch) ` +
        `without an EXCEPTION WHEN OTHERS handler — a dispatch failure would roll back ` +
        `the primary write. Wrap the dispatch in BEGIN ... EXCEPTION WHEN OTHERS THEN ` +
        `<log> END, or (if by-design) add to ALLOWLIST with justification. ` +
        `Offenders: ${JSON.stringify(offenders)}`,
    );
  },
);
