/**
 * #693 defect 1 — HARD terminal VEP status must be honored in the selection
 * funnel: no selection_applications row may sit at an ACTIVE/in-flight status
 * while its vep_status_raw is a hard terminal VEP decision (OfferNotExtended /
 * Declined / Withdrawn / Expired / OfferExpired / Removed).
 *
 * Background: the worker re-import path (#472) deliberately FREEZES a mid-pipeline
 * candidate against VEP exits, because VEP emits 'Submitted' for every in-flight
 * app and is blind to the platform pipeline. But that freeze also swallowed
 * EXPLICIT terminal decisions, so a VEP-declined application lingered at e.g.
 * 'screening' and the candidate surfaced under the wrong, dead application (live
 * case: Ana Sofia Pires Pacheco, leader app OfferNotExtended stuck at screening).
 *
 * Fix surface:
 *   - cloudflare-workers/pmi-vep-sync/src/db.ts resolveReimportStatus (3rd arg
 *     vepStatusRaw) — locked by p472-vep-reimport-status-freeze (static).
 *   - migration 20260805000171 reconcile_vep_terminal_status — idempotent heal.
 *
 * This test asserts the live INVARIANT (DB-aware) + the reconciler's idempotency.
 * Skips offline (no DB creds) like the other behavioural contract tests.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000171_693_reconcile_vep_terminal_status.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// VEP raw statuses that are a hard, per-application terminal decision (lowercased).
const VEP_HARD_TERMINAL = ['offernotextended', 'declined', 'withdrawn', 'expired', 'offerexpired', 'removed'];
// platform statuses that count as terminal (NOT active in the funnel).
const PLATFORM_TERMINAL = ['approved', 'rejected', 'converted', 'withdrawn', 'cancelled', 'waitlist', 'interview_noshow'];

// ── STATIC ──────────────────────────────────────────────────────────────────
test('#693 static: migration 20260805000171 exists and defines the reconciler', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000171 present');
  const src = readFileSync(MIG, 'utf8');
  assert.match(src, /CREATE OR REPLACE FUNCTION public\.reconcile_vep_terminal_status\(/,
    'reconcile_vep_terminal_status defined');
  assert.match(src, /SECURITY DEFINER/, 'SECURITY DEFINER');
  assert.match(src, /REVOKE ALL ON FUNCTION public\.reconcile_vep_terminal_status[\s\S]*?FROM PUBLIC, anon/,
    'anon must be revoked');
});

// ── DB-AWARE INVARIANT ────────────────────────────────────────────────────────
test('#693 invariant: no ACTIVE row carries a hard-terminal vep_status_raw', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // pull every row with a non-null vep_status_raw and check in JS (avoids relying
  // on a server-side helper; the set is small — ~100 rows).
  const { data, error } = await sb
    .from('selection_applications')
    .select('id, applicant_name, status, vep_status_raw')
    .not('vep_status_raw', 'is', null);
  assert.ok(!error, `query failed: ${error?.message}`);

  const violations = (data ?? []).filter(r =>
    VEP_HARD_TERMINAL.includes(String(r.vep_status_raw).toLowerCase()) &&
    !PLATFORM_TERMINAL.includes(r.status)
  );
  assert.equal(
    violations.length, 0,
    `rows with hard-terminal VEP status still ACTIVE in the funnel: ` +
      JSON.stringify(violations.map(v => ({ name: v.applicant_name, status: v.status, vep: v.vep_status_raw })))
  );
});

// Assumes the population has already been reconciled (the one-time heal ran at
// fix time, and the daily cron `_selection_status_recompute_cron` keeps it
// converged). If a future fixture seeds an ACTIVE row with a hard-terminal
// vep_status_raw, this asserts the reconciler would catch it (changed>0) — i.e.
// a failure here means a real un-healed drift, not a flaky test.
test('#693 reconciler: dry-run is idempotent over the full population (changed=0 post-heal)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // service_role → no JWT context → reconciler runs the cron/self-heal path.
  const { data, error } = await sb.rpc('reconcile_vep_terminal_status', { p_application_id: null, p_dry_run: true });
  assert.ok(!error, `rpc failed: ${error?.message}`);
  assert.equal(data?.success, true, 'reconciler returned success');
  assert.equal(data?.changed, 0,
    `dry-run still proposes ${data?.changed} change(s) — the heal is not converged: ` +
      JSON.stringify(data?.changes));
});
