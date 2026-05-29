/**
 * Contract: p277 — Attendance ranking visibility model C+B
 * (metric-disparity audit, follow-up to D2).
 *
 * After D2 masked the dropout_risk BOOLEAN for non-leaders, the raw combined_pct stayed
 * visible — and the flag is just `combined_pct < 50`, so any member could re-derive
 * "who is at risk" by eye. Model C+B (PM-chosen) closes that:
 *   C  non-privileged caller gets ONLY their own row + an ANONYMOUS cohort aggregate
 *      (cohort_avg_pct, cohort_percentile, cohort_size). Leadership (manage_event) + GP
 *      see the full nominal ranking. No peer names/% for rank-and-file.
 *   B  the gamification opt-out keeps its XP-leaderboard meaning; leaders retain operational
 *      attendance visibility (legitimate interest) — opt-out does NOT blind a leader.
 *
 * The cohort aggregate is computed from the existing `computed` CTE — NO new inline
 * attendance formula is introduced (ADR-0100 discipline). Signature gains 3 nullable
 * columns -> DROP + CREATE (GC-097). The leftover anon/PUBLIC execute grant is revoked.
 *
 * Migration: supabase/migrations/20260805000056_p277_attendance_ranking_visibility_cb.sql
 *
 * Cross-ref: audit `docs/audit/METRIC_DISPARITY_AUDIT_2026-05-28.md` (D2) · ADR-0100 ·
 *   migration 20260805000055 (D2 gate this builds on) · ADR-0050 (gamification opt-out).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATION_FILE = resolve(
  ROOT,
  'supabase/migrations/20260805000056_p277_attendance_ranking_visibility_cb.sql'
);
const FRONTEND_FILE = resolve(ROOT, 'src/pages/attendance.astro');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIGRATION_FILE) ? readFileSync(MIGRATION_FILE, 'utf8') : '';
const fe = existsSync(FRONTEND_FILE) ? readFileSync(FRONTEND_FILE, 'utf8') : '';

// ===================================================================
// STATIC migration body assertions
// ===================================================================

test('p277: migration file exists', () => {
  assert.ok(existsSync(MIGRATION_FILE), `Migration must exist at ${MIGRATION_FILE}`);
});

test('p277: uses DROP + CREATE (column-count change, GC-097)', () => {
  assert.match(body, /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.get_attendance_panel\(date,\s*date\)/i, 'must DROP the old signature');
  assert.match(body, /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.get_attendance_panel/i, 'must re-CREATE');
});

test('p277 C: RETURNS TABLE gains the 3 anonymous-aggregate columns', () => {
  assert.match(body, /cohort_avg_pct\s+numeric/i);
  assert.match(body, /cohort_percentile\s+numeric/i);
  assert.match(body, /cohort_size\s+integer/i);
});

test('p277 C: non-privileged caller is restricted to their own row', () => {
  // final SELECT row filter
  assert.match(body, /FROM\s+computed\s+c\s+WHERE\s+v_privileged\s+OR\s+c\.id\s*=\s*v_caller_id/i, 'final SELECT must restrict non-privileged to self row');
});

test('p277 C: cohort columns populated ONLY on self row when NOT privileged', () => {
  const guards = (body.match(/NOT\s+v_privileged\s+AND\s+c\.id\s*=\s*v_caller_id/g) || []).length;
  assert.ok(guards >= 3, `each of the 3 cohort columns must be guarded by NOT v_privileged AND self; found ${guards}`);
});

test('p277 ADR-0100: aggregate reuses the computed CTE — no new inline attendance formula', () => {
  assert.match(body, /cohort\s+AS\s*\(\s*SELECT\s+ROUND\(AVG\(c\.c_pct\)/i, 'cohort avg must read c.c_pct FROM computed');
  assert.match(body, /caller\s+AS\s*\([\s\S]*?FROM\s+computed\s+c\s+WHERE\s+c\.id\s*=\s*v_caller_id/i, 'caller percentile must read from computed');
  // forward-defense: the mandatory-attendance primitive must appear the SAME number of times as
  // the original (gscores x2 + tscores x2). A 5th occurrence means a new inline formula crept in.
  const occ = (body.match(/is_event_mandatory_for_member/g) || []).length;
  assert.equal(occ, 4, `expected exactly 4 is_event_mandatory_for_member uses (no new formula); found ${occ}`);
});

test('p277 D2 preserved: dropout_risk/typology still masked to privileged-or-self', () => {
  const masks = (body.match(/v_privileged\s+OR\s+c\.id\s*=\s*v_caller_id/g) || []).length;
  // 2 masks (dropout_risk + typology) + 1 final-SELECT row filter = 3 occurrences minimum
  assert.ok(masks >= 3, `D2 masks + self-row filter expected; found ${masks}`);
  assert.match(body, /IF\s+v_caller_id\s+IS\s+NULL\s+THEN\s+RETURN;/i, 'anon gate preserved');
});

test('p277: anon/PUBLIC execute revoked, only authenticated + service_role granted', () => {
  assert.match(body, /REVOKE\s+EXECUTE\s+ON\s+FUNCTION\s+public\.get_attendance_panel\(date,\s*date\)\s+FROM\s+PUBLIC,\s*anon/i, 'must revoke PUBLIC + anon');
  assert.match(body, /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.get_attendance_panel\(date,\s*date\)\s+TO\s+authenticated,\s*service_role/i, 'must grant authenticated + service_role');
  assert.ok(!/GRANT\s+EXECUTE[\s\S]*?TO[^;]*\banon\b/i.test(body), 'must NOT grant anon');
});

test('p277: SECDEF + pinned search_path + date defaults preserved + NOTIFY', () => {
  assert.match(body, /SECURITY DEFINER/i);
  assert.match(body, /SET search_path TO 'public', 'pg_temp'/i);
  assert.match(body, /p_cycle_start date DEFAULT '2026-01-01'[\s\S]*?p_cycle_end date DEFAULT '2026-06-30'/i);
  assert.match(body, /NOTIFY\s+pgrst/i);
});

// ===================================================================
// FRONTEND assertions (Ranking tab branches to the private standing card)
// ===================================================================

test('p277 FE: Ranking tab renders a private standing card for non-privileged callers', () => {
  assert.match(fe, /function\s+renderStandingCard\s*\(/, 'renderStandingCard helper must exist');
  assert.match(fe, /RANKING_DATA\.find\(\(r:\s*any\)\s*=>\s*r\.cohort_size\s*!=\s*null\)/, 'loadRanking must branch on cohort_size to detect non-privileged self+aggregate');
  assert.match(fe, /if\s*\(\s*standingRow\s*\)\s*\{\s*renderStandingCard\(standingRow\);\s*return;\s*\}/, 'must render the standing card and skip the nominal list');
  // standing card hides the nominal filters (no peer list to filter)
  assert.match(fe, /ranking-role-filter[\s\S]*?style\.display\s*=\s*'none'/, 'role filter hidden in standing mode');
});

// ===================================================================
// DB-gated live behavior
// ===================================================================

test('p277 DB: service-role/no-auth still gets 0 rows (D2 gate intact)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_attendance_panel');
  assert.ok(!error, `rpc should not error: ${error?.message}`);
  assert.equal((data || []).length, 0, 'no-auth caller must get zero rows');
});
