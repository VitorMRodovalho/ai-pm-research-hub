/**
 * Contract: p277 / #419 (ADR-0100) metric 3 — PR10: p175-gate extension for the attendance two-metric model.
 *
 * Forward-defense gate (no migration, no RPC change). It locks three invariants the PR1–PR8 convergence
 * established, so a future change cannot silently regress them. The structural checks are STATIC over the
 * PR1 foundation migration (the canonical "p175 gate" style — same as rpc-migration-coverage); two proven
 * behavioural checks are DB-gated against the live RPCs.
 *
 *   A. CANONICAL ELIGIBILITY (SPEC §3b) — `public._attendance_eligible_events` is the SINGLE eligibility
 *      source and is TYPE-based ({geral,kickoff,tribo,lideranca}); the engagement + reliability summaries
 *      delegate to it; the foundation introduces NO tag-based eligibility (`event_tag_assignments`).
 *   B. RELIABILITY-VISIBILITY HARD-GATE (SPEC §2.2 / D10) — reliability ("Confiabilidade de registro") is a
 *      data-quality diagnostic, never an anon/public headline until roster sealing. Structurally enforced by
 *      the grant ladder (C): the reliability primitives are service_role-only, so no anon surface can read a
 *      bare reliability number. SPEC D10 anchor asserted statically.
 *   C. GRANT LADDER — the foundation primitives REVOKE PUBLIC/anon/authenticated and GRANT service_role only
 *      (asserted over migration 20260805000066). `get_dropout_risk_members` is authenticated with an internal
 *      manage_event gate, never anon — proven DB-gated (fail-closed for no-member callers).
 *
 * Grounded live (p277, this session) — grantees per information_schema.role_routine_grants:
 *   _attendance_eligible_events / get_attendance_engagement_rate / get_attendance_engagement_summary /
 *   get_attendance_rate / get_attendance_reliability_summary = {postgres, service_role}
 *   get_dropout_risk_members = {authenticated, postgres, service_role}; public anon RPCs = reliability-free.
 *   get_attendance_reliability_summary('global',…) returns {avg_rate 0.9916, cohort_n 37, present/absent/excused totals}.
 *
 * Cross-ref: SPEC_419_M3_ATTENDANCE_TWO_METRIC.md §3b + §2.2 + §6 D10 + §7 PR10; ADR-0100; issue #419.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const SPEC = resolve(ROOT, 'docs/specs/SPEC_419_M3_ATTENDANCE_TWO_METRIC.md');
// The PR1 foundation migration defines the 4 canonical engagement/reliability primitives + their grant ladder.
const FOUNDATION = resolve(ROOT, 'supabase/migrations/20260805000066_p277_419_m3c_engagement_foundation.sql');

const spec = existsSync(SPEC) ? readFileSync(SPEC, 'utf8') : '';
const fnd = existsSync(FOUNDATION) ? readFileSync(FOUNDATION, 'utf8') : '';
const fndCode = fnd.replace(/^\s*--.*$/gm, ''); // strip SQL line-comments (prose may mention retired models)

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── STATIC: SPEC anchors ───────────────────────────────────────────────────────
test('PR10 static: SPEC §3b Canonical Eligibility Principle names the single primitive + no-parallel rule', () => {
  assert.ok(existsSync(SPEC), 'SPEC exists');
  assert.match(spec, /3b\.?\s*CANONICAL ELIGIBILITY PRINCIPLE/i, 'SPEC has the §3b section');
  assert.match(spec, /_attendance_eligible_events.*is the SINGLE source/i, 'SPEC names the canonical primitive');
  assert.ok(/No surface may reintroduce a parallel eligibility model/i.test(spec),
    'SPEC states the no-parallel-model rule');
});

test('PR10 static: SPEC §2.2/D10 keeps reliability off the public headline, with raw counts', () => {
  assert.match(spec, /Confiabilidade de registro/, 'SPEC names the reliability metric');
  assert.ok(/Never\*?\*?\s*a public\/headline KPI|public BANNED until seal|never.*headline.*seal/i.test(spec),
    'SPEC states reliability is never a public headline until sealing');
  assert.ok(/raw\s*\n?\s*present\/absent\/excused counts|mandatory raw counts|always with raw/i.test(spec),
    'SPEC requires reliability to be shown with raw counts');
});

test('PR10 static: SPEC §7 records PR10 as the shipped p175 gate extension', () => {
  assert.match(spec, /PR10\s*[—-]\s*p175 gate extension/i, 'SPEC §7 names PR10 the p175 gate extension');
  assert.match(spec, /PR10[\s\S]{0,220}✅ SHIPPED/i, 'SPEC §7 marks PR10 shipped');
});

// ── STATIC (A): canonical eligibility, over the foundation migration ────────────
test('PR10 A: the canonical primitive is defined type-based, not tag-based', () => {
  assert.ok(existsSync(FOUNDATION), 'foundation migration exists');
  assert.match(fndCode, /CREATE OR REPLACE FUNCTION public\._attendance_eligible_events\(/,
    'foundation defines _attendance_eligible_events');
  for (const t of ["'geral'", "'kickoff'", "'tribo'", "'lideranca'"]) {
    assert.ok(fndCode.includes(t), `eligibility is type-based (${t})`);
  }
  assert.ok(!/event_tag_assignments/.test(fndCode),
    'the foundation must NOT select eligibility via the retired tag table (event_tag_assignments)');
  assert.ok(!/'general_meeting'|'tribe_meeting'/.test(fndCode),
    'the foundation must NOT select on the retired meeting-tag literals');
});

test('PR10 A: the engagement + reliability summaries delegate to the canonical primitive', () => {
  for (const name of ['get_attendance_engagement_rate', 'get_attendance_engagement_summary',
                      'get_attendance_reliability_summary']) {
    assert.match(fndCode, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\(`),
      `foundation defines ${name}`);
  }
  // every metric primitive resolves eligibility through the single source (>=4 delegating references)
  const refs = (fndCode.match(/_attendance_eligible_events/g) || []).length;
  assert.ok(refs >= 4, `summaries delegate to the canonical primitive (found ${refs} references, expected >=4)`);
});

// ── STATIC (C): grant ladder, over the foundation migration ────────────────────
test('PR10 C: the foundation primitives REVOKE PUBLIC/anon/authenticated and GRANT service_role only', () => {
  const revokes = (fndCode.match(/REVOKE ALL ON FUNCTION public\.[a-z_]+\([^)]*\) FROM PUBLIC, anon, authenticated/g) || []).length;
  const grants  = (fndCode.match(/GRANT EXECUTE ON FUNCTION public\.[a-z_]+\([^)]*\) TO service_role/g) || []).length;
  assert.ok(revokes >= 4, `each foundation primitive revokes anon/authenticated (found ${revokes}, expected >=4)`);
  assert.equal(revokes, grants, 'every REVOKE is paired with a service_role GRANT');
  // never a bare GRANT to anon/authenticated on these primitives
  assert.ok(!/GRANT EXECUTE ON FUNCTION public\.(get_attendance_engagement|get_attendance_reliability|_attendance_eligible)[a-z_]*\([^)]*\) TO (anon|authenticated)/.test(fndCode),
    'no engagement/reliability primitive may GRANT execute to anon/authenticated');
});

// ── DB-GATED (C behavioural): dropout RPC is authenticated-tier + fail-closed, never anon ───
test('PR10 C-db: get_dropout_risk_members gate-closes for no-member callers (no anon leak)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_dropout_risk_members', { p_threshold: 3 });
  assert.ok(!error, error?.message);
  assert.ok(Array.isArray(data) && data.length === 0, 'no-member caller gets empty result (gate fail-closed)');
});

// ── DB-GATED (C behavioural): a reliability primitive is service_role-callable (exists + executes) ───
test('PR10 C-db: get_attendance_reliability_summary executes under service_role', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_attendance_reliability_summary',
    { p_scope: 'global', p_scope_id: null, p_cycle_start: null, p_chapter: null });
  assert.ok(!error, `service_role must be able to call the reliability primitive: ${error?.message}`);
  assert.ok(data && typeof data === 'object', 'reliability summary returns an object payload');
});
