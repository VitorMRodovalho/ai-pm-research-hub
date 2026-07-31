/**
 * Contract: #1551 — ACL sweep over SECURITY DEFINER functions reachable by anon/PUBLIC.
 *
 * #1543 established the shape of a cron-context function: no auth.uid() gate (there is no JWT
 * under pg_cron), which makes the ACL the ONLY protection. Where the REVOKE never followed the
 * gate removal, a writing function stayed open. Confirmed live before the fix, not inferred: an
 * anonymous POST to /rest/v1/rpc/record_milestone returned HTTP 204.
 *
 * This guard locks the sweep in BOTH directions, because each direction has a real failure mode:
 *   - Under-revoking: a closed function regains anon/authenticated EXECUTE.
 *   - Over-revoking: a future "tighten everything" pass silently kills the public blog counters
 *     or the visitor lead form, which are anon-reachable BY DESIGN.
 *
 * Layers: (A) static migration-file guard, offline safe. (B) DB-aware probes through
 * _audit_function_execute_acl, which reports EFFECTIVE privilege rather than proacl text.
 *
 * Two authoring traps this file exists to not repeat (both burned a guard the same week):
 *   - assert.match is existential. A universal invariant ("every one of these is closed") must
 *     iterate the set; matching once passes while the other members drift.
 *   - A textual guard must strip SQL comments first. This migration NAMES the functions it
 *     deliberately left alone, so a naive substring check reads a comment as a statement.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATION_PATH = join(__dirname, '../../supabase/migrations/20260805000500_1551_cron_family_acl_sweep.sql');
const HELPER_PATH = join(__dirname, '../../supabase/migrations/20260805000501_1551_audit_function_execute_acl_helper.sql');

const readSql = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');

/** Drop `-- …` line comments so a name mentioned in prose is never read as a statement. */
const stripSqlComments = (s) => s.replace(/--[^\n]*/g, '');

const sqlRaw = readSql(MIGRATION_PATH);
const sql = stripSqlComments(sqlRaw);
const helperSql = stripSqlComments(readSql(HELPER_PATH));

// Closed to postgres + service_role. Ungated writers whose only callers are other SECURITY
// DEFINER functions (EXECUTE is checked as the OWNER), pg_cron (runs as postgres), or a
// service_role client.
const CLOSED = [
  '_compute_pert_cutoff_core(p_cycle_id uuid, p_role text, p_filter_active_only boolean, p_score_column text, p_actor_id uuid)',
  '_enqueue_engagement_welcome(p_engagement_id uuid)',
  '_log_gate_attempt(p_application_id uuid, p_rpc_name text, p_caller_id uuid, p_gate_passed boolean, p_gate_failed_code text, p_gate_failed_reason text, p_bypass_requested boolean, p_bypass_granted boolean, p_payload jsonb, p_organization_id uuid)',
  '_recompute_application_pert(p_application_id uuid)',
  '_refresh_preview_gate_eligibles_for_member(p_member_id uuid)',
  '_sync_interview_to_event(p_interview_id uuid)',
  'recompute_all_active_pert_cutoffs()',
  'record_milestone(p_member_id uuid, p_milestone_key text, p_source_type text, p_source_id uuid, p_metadata jsonb)',
  'log_cron_run_start(p_worker_name text, p_scheduled_for timestamp with time zone, p_metrics jsonb)',
  'log_cron_run_complete(p_run_id uuid, p_status text, p_metrics jsonb, p_errors jsonb)',
  'detect_credly_unmapped_cron()',
  'detect_recurrence_stockout_cron()',
  'generate_weekly_member_digest_cron()',
];

// Gated admin RPCs that also carried a PUBLIC/anon grant. authenticated is KEPT: they are
// reached from the admin UI and from the MCP edge function, whose client is the anon key plus
// the caller JWT, so revoking authenticated would break them.
const PUBLIC_REVOKED_AUTH_KEPT = [
  'detect_and_notify_detractors()',
  'detect_operational_alerts()',
  'generate_agenda_template(p_tribe_id integer)',
];

// anon EXECUTE is the point: public blog and publications pages. Narrowed from PUBLIC to an
// explicit grantee list, same reachability.
const ANON_BY_DESIGN = [
  'increment_blog_view(p_slug text)',
  'increment_publication_view(p_id uuid)',
];

const nameOf = (sig) => sig.slice(0, sig.indexOf('('));

// ─────────────────────────────────────────────────────────────────────────
// (A) Static migration-file guard — always runs
// ─────────────────────────────────────────────────────────────────────────

test('#1551 (A1) every closed function is revoked from PUBLIC, anon AND authenticated', () => {
  assert.ok(sqlRaw, `migration file missing at expected path: ${MIGRATION_PATH}`);
  // Universal, not existential: assert each member, and report which one failed.
  for (const sig of CLOSED) {
    assert.ok(
      sql.includes(`REVOKE ALL ON FUNCTION public.${sig} FROM PUBLIC, anon, authenticated;`),
      `${nameOf(sig)} must be revoked from PUBLIC, anon and authenticated`,
    );
    assert.ok(
      sql.includes(`GRANT EXECUTE ON FUNCTION public.${sig} TO service_role;`),
      `${nameOf(sig)} must keep service_role`,
    );
  }
  // The set must not shrink silently: a deleted REVOKE would otherwise just stop being checked.
  const revokes = (sql.match(/REVOKE ALL ON FUNCTION public\.[^;]+FROM PUBLIC, anon, authenticated;/g) || []).length;
  assert.equal(revokes, CLOSED.length, `expected ${CLOSED.length} full REVOKEs, found ${revokes}`);
});

test('#1551 (A2) gated admin RPCs lose PUBLIC and anon but KEEP authenticated', () => {
  for (const sig of PUBLIC_REVOKED_AUTH_KEPT) {
    assert.ok(
      sql.includes(`REVOKE ALL ON FUNCTION public.${sig} FROM PUBLIC, anon;`),
      `${nameOf(sig)} must be revoked from PUBLIC and anon`,
    );
    assert.ok(
      sql.includes(`GRANT EXECUTE ON FUNCTION public.${sig} TO authenticated, service_role;`),
      `${nameOf(sig)} must keep authenticated (admin UI + MCP call it)`,
    );
    // Over-revoking authenticated here breaks the admin surface, so forbid that spelling.
    assert.ok(
      !sql.includes(`REVOKE ALL ON FUNCTION public.${sig} FROM PUBLIC, anon, authenticated;`),
      `${nameOf(sig)} must NOT have authenticated revoked`,
    );
  }
});

test('#1551 (A3) public-by-design counters keep an EXPLICIT anon grant', () => {
  for (const sig of ANON_BY_DESIGN) {
    assert.ok(
      sql.includes(`REVOKE ALL ON FUNCTION public.${sig} FROM PUBLIC;`),
      `${nameOf(sig)} narrows away from the PUBLIC grant`,
    );
    assert.ok(
      sql.includes(`GRANT EXECUTE ON FUNCTION public.${sig} TO anon, authenticated, service_role;`),
      `${nameOf(sig)} must keep anon explicitly — the public page calls it`,
    );
  }
});

test('#1551 (A4) the audit probe is itself closed to service_role', () => {
  assert.ok(helperSql, `helper migration missing at expected path: ${HELPER_PATH}`);
  assert.ok(
    helperSql.includes('REVOKE ALL ON FUNCTION public._audit_function_execute_acl(p_names text[]) FROM PUBLIC, anon, authenticated;'),
    'the probe must not be reachable by anon/authenticated — it is the invariant it enforces',
  );
  assert.ok(
    helperSql.includes('GRANT EXECUTE ON FUNCTION public._audit_function_execute_acl(p_names text[]) TO service_role;'),
    'the probe must be callable by service_role',
  );
});

// ─────────────────────────────────────────────────────────────────────────
// (B) DB-aware guard — effective privilege, read through the audit probe
// ─────────────────────────────────────────────────────────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_KEY);
const skipMsg = 'SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1551 (B) live EXECUTE privilege matches the reviewed classification', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  const expectClosed = CLOSED.map(nameOf).concat(['_audit_function_execute_acl']);
  const expectAuthOnly = PUBLIC_REVOKED_AUTH_KEPT.map(nameOf);
  const expectAnon = ANON_BY_DESIGN.map(nameOf).concat(['capture_visitor_lead']);
  const allNames = [...expectClosed, ...expectAuthOnly, ...expectAnon];

  const { data, error } = await sb.rpc('_audit_function_execute_acl', { p_names: allNames });
  // A probe failure must never be scored as a clean world. An error, or a short result, is a
  // failure of the measurement — report it as such instead of letting it read as "all closed".
  assert.ok(!error, `audit probe failed: ${error?.message}`);
  assert.ok(Array.isArray(data), 'audit probe must return rows');

  const byName = new Map(data.map((r) => [r.proname, r]));
  for (const n of allNames) {
    assert.ok(byName.has(n), `probe returned no row for ${n} — function missing or renamed`);
  }

  for (const n of expectClosed) {
    const r = byName.get(n);
    assert.equal(r.anon_exec, false, `${n} must NOT be executable by anon`);
    assert.equal(r.authenticated_exec, false, `${n} must NOT be executable by authenticated`);
  }
  for (const n of expectAuthOnly) {
    const r = byName.get(n);
    assert.equal(r.anon_exec, false, `${n} must NOT be executable by anon`);
    assert.equal(r.authenticated_exec, true, `${n} must stay executable by authenticated (admin UI + MCP)`);
  }
  for (const n of expectAnon) {
    const r = byName.get(n);
    assert.equal(r.anon_exec, true, `${n} is anon-reachable by design — revoking it breaks a public page`);
  }
});
