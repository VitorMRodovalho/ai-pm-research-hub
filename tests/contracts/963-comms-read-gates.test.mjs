/**
 * Contract test for issue #963 — ungated comms-read SECURITY DEFINER RPCs reachable by
 * any authenticated caller. The three gateable comms-read RPCs must all sit behind
 * can_view_comms_analytics() (= view_internal_analytics OR manage_comms OR the
 * comms_leader/comms_member designation), per ADR-0106 (the boundary is the in-RPC gate,
 * not the /admin/comms client guard):
 *
 *   1. webinars_pending_comms()      — HIGH: returned meeting_link (live conf URLs)   (PR #964, mig …296)
 *   2. broadcast_history()           — broadcast subjects / sender / recipient counts (PR #966, mig …297)
 *   3. comms_check_token_expiry()    — writer+reader; which channels have expiring tokens (mig …310, this PR)
 *
 * Finding #4 (board_items direct PostgREST read) is a visibility DESIGN question, tracked
 * separately — not asserted here.
 *
 * Two layers:
 *   (A) Static migration-body guard (always runs, hard-fails offline): the LATEST captured
 *       body of each of the three RPCs references the gate. This is non-no-op — before the
 *       #963-#3 migration, comms_check_token_expiry()'s latest body carried no gate, so the
 *       assertion failed against it.
 *   (B) DB-aware deny-path check (skipped without SUPABASE_URL + SERVICE_ROLE_KEY): a
 *       no-identity service-role caller (auth.uid() IS NULL → gate returns false) gets the
 *       empty/zero-shape from all three, confirming the gate's deny path works live and
 *       does not error. NOTE: Layer B is a live sanity check, NOT a live-body regression
 *       guard — with no near-expiry channel data it would pass against an ungated body too.
 *       The gate-presence regression guard is Layer A (which reads the migration source).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function loadAllMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  return files.map((f) => readFileSync(join(MIGRATIONS_DIR, f), 'utf8'));
}
const allSQL = loadAllMigrations().join('\n');

// Reused verbatim from 991-verify-certificate-no-pii-leak.test.mjs — the escape set
// includes backslash, so the RegExp is fully sanitized (no js/incomplete-sanitization).
function latestFunctionBody(funcName) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi',
  );
  const matches = [...allSQL.matchAll(regex)];
  return matches.length > 0 ? matches[matches.length - 1][2] : null;
}

const GATED_COMMS_READ_RPCS = ['webinars_pending_comms', 'broadcast_history', 'comms_check_token_expiry'];

// ── Layer A: static migration-body guard ─────────────────────────────────────
test('#963 static: all three comms-read RPCs are gated behind can_view_comms_analytics()', () => {
  for (const fn of GATED_COMMS_READ_RPCS) {
    const body = latestFunctionBody(fn);
    assert.ok(body, `${fn} must be defined in a migration`);
    assert.ok(
      body.includes('can_view_comms_analytics'),
      `${fn} latest body must reference the can_view_comms_analytics() gate`,
    );
  }
});

test('#963 static: comms_check_token_expiry gate precedes the write loop + returns a zero-shape when denied', () => {
  const body = latestFunctionBody('comms_check_token_expiry');
  assert.ok(body, 'comms_check_token_expiry must be defined in a migration');

  const gateIdx = body.indexOf('can_view_comms_analytics');
  const firstInsertIdx = body.indexOf('INSERT INTO public.comms_token_alerts');
  assert.ok(gateIdx >= 0, 'gate must be present');
  assert.ok(firstInsertIdx >= 0, 'the write (INSERT) must still be present for allowed callers');
  assert.ok(gateIdx < firstInsertIdx, 'the gate must run BEFORE any write (a denied caller performs no writes)');

  // Denied return is the empty shape the /admin/comms page tolerates (hides the section).
  assert.ok(
    /RETURN\s+jsonb_build_object\(\s*'alerts_created'\s*,\s*0/.test(body),
    "denied path must RETURN jsonb_build_object('alerts_created', 0, 'active_alerts', '[]')",
  );
});

// ── Layer B: DB-aware deny-path check (skip offline) ──────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#963 runtime: a no-identity caller gets the empty/zero denied shape from all three RPCs', { skip: dbGated ? false : skipMsg }, async () => {
  const { createClient } = await import('@supabase/supabase-js');
  // service_role → auth.uid() IS NULL → can_view_comms_analytics() returns false → deny path.
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  const { data: webinars, error: wErr } = await sb.rpc('webinars_pending_comms');
  assert.equal(wErr, null, wErr?.message);
  assert.deepEqual(webinars, [], 'webinars_pending_comms must return [] for a no-identity caller (meeting_link not leaked)');

  const { data: broadcasts, error: bErr } = await sb.rpc('broadcast_history');
  assert.equal(bErr, null, bErr?.message);
  assert.deepEqual(broadcasts, [], 'broadcast_history must return [] for a no-identity caller');

  const { data: tokens, error: tErr } = await sb.rpc('comms_check_token_expiry');
  assert.equal(tErr, null, tErr?.message);
  assert.deepEqual(
    tokens,
    { alerts_created: 0, active_alerts: [] },
    'comms_check_token_expiry must return the zero-shape (no writes, no reads) for a no-identity caller',
  );
});
