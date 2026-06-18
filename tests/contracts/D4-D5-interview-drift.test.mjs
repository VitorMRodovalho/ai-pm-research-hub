/**
 * Contract: ÉPICO D — D4/D5 drift candidatura↔entrevista (linha de entrevista órfã na remarcação).
 * Migration: 20260805000210. SPEC: docs/specs/SPEC_D4_D5_INTERVIEW_DRIFT.md.
 *
 * GROUNDED (live, cycle4-2026): the PM-greenlit "detect app.status<->interview drift" found ZERO lost
 * candidates. The divergence (linha_sem_status=4) was entirely a prior interview row left OPEN
 * (scheduled/rescheduled) when the candidate re-books — sync_calendar_booking_to_interview /
 * schedule_interview INSERT a new 'scheduled' row WITHOUT closing the prior open one.
 *
 * FIX (PM chose: root-cause + backfill + invariant):
 *   - AFTER INSERT trigger trg_supersede_prior_open_interviews cancels the application's OTHER open rows
 *     when a new open row is inserted (path-agnostic; exempts import_historical/mirror — they insert 'completed').
 *   - Backfill cancels the orphan open rows (open AND not the newest interview row), global, fail-loud assert.
 *   - Invariant AF_open_interview_is_newest_row (32 -> 33).
 *
 * Council: data-architect GO-with-changes (0 blockers; fail-loud assert, array_agg pattern, notes 2-newline,
 * directional gap accepted as defense-in-depth). DB assertions are READ-ONLY.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');
const MIG = read('supabase/migrations/20260805000210_d4_d5_supersede_open_interviews.sql');

// Slice the supersede trigger function body, anchored on CREATE FUNCTION (not ROLLBACK comments
// that name a DROP — sediment: comment-naming a function breaks naive slicing).
const FN = (() => {
  const m = MIG.match(/CREATE OR REPLACE FUNCTION public\._trg_supersede_prior_open_interviews[\s\S]*?\$fn\$([\s\S]*?)\$fn\$/);
  return m ? m[1] : '';
})();

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── Offline: migration shape ───────────────────────────────────────────────────
test('migration exists; trigger fn is SECURITY DEFINER + search_path empty', () => {
  assert.ok(MIG, 'migration 20260805000210 exists');
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\._trg_supersede_prior_open_interviews\(\)/);
  assert.match(MIG, /SECURITY DEFINER/);
  assert.match(MIG, /SET search_path = ''/);
});

test('trigger: AFTER INSERT, WHEN NEW.status IN (scheduled,rescheduled) only', () => {
  // AFTER (not BEFORE) — it touches SIBLING rows, not NEW.
  assert.match(MIG, /AFTER INSERT ON public\.selection_interviews/);
  assert.match(MIG, /FOR EACH ROW\s*\n?\s*WHEN \(NEW\.status IN \('scheduled', 'rescheduled'\)\)/);
  // The WHEN must NOT fire on terminal inserts (import_historical/mirror insert 'completed').
  assert.ok(!/WHEN \([^)]*'completed'/.test(MIG), 'WHEN must not match completed/terminal inserts');
});

test('trigger body cancels OTHER open rows of the same application (not NEW)', () => {
  assert.match(FN, /UPDATE public\.selection_interviews/);
  assert.match(FN, /SET status = 'cancelled'/);
  assert.match(FN, /WHERE application_id = NEW\.application_id/);
  assert.match(FN, /AND id <> NEW\.id/);
  assert.match(FN, /AND status IN \('scheduled', 'rescheduled'\)/);
});

test('backfill cancels orphan open rows (open AND not the newest), with EXISTS newer-row predicate', () => {
  assert.match(MIG, /UPDATE public\.selection_interviews si/);
  assert.match(MIG, /SET status = 'cancelled'/);
  // the orphan predicate: open AND a newer interview row exists for the same app
  assert.match(MIG, /WHERE si\.status IN \('scheduled', 'rescheduled'\)/);
  assert.match(MIG, /x\.application_id = si\.application_id\s*\n?\s*AND x\.created_at > si\.created_at/);
});

test('backfill has a fail-loud sanity assert (RAISE EXCEPTION if any orphan survives)', () => {
  assert.match(MIG, /D4\/D5 backfill sanity FAIL/);
  assert.match(MIG, /RAISE EXCEPTION/);
});

test('invariant AF_open_interview_is_newest_row appended to check_schema_invariants', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.check_schema_invariants\(\)/);
  assert.match(MIG, /'AF_open_interview_is_newest_row'::text/);
  // AF uses interview_id (uuid) as the sample column, mirroring AA-AE array_agg pattern
  assert.match(MIG, /array_agg\(interview_id ORDER BY interview_id\)/);
  // the AE invariant (the prior tail) must still be present — proof the body was reproduced, not truncated
  assert.match(MIG, /'AE_profile_complete_milestone_has_profile_completed_at'::text/);
});

test('grounding: no live cohort numbers hardcoded as facts (the 4 / cycle counts)', () => {
  // The fix is structural; the only integer literal expected in the trigger body is none.
  assert.ok(!/\b(51|27|4)\b/.test(FN), 'no live cohort numbers in the trigger body');
});

// ── DB-gated: live shape, READ-ONLY ──────────────────────────────────────────────
test('DB: invariant AF is live and reports 0 violations', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('check_schema_invariants');
  assert.ok(!error, error?.message);
  const af = (data || []).find((r) => r.invariant_name === 'AF_open_interview_is_newest_row');
  assert.ok(af, 'AF invariant present in check_schema_invariants output');
  assert.equal(af.violation_count, 0, 'AF must report 0 orphan open interview rows post-fix');
});

test('DB: no orphan open interview rows (open row that is not the newest of its application)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // Pull all interview rows (id, app, status, created_at) and compute the invariant in JS — read-only,
  // independent of the RPC. An open row must be the max(created_at) for its application.
  const { data, error } = await sb.from('selection_interviews')
    .select('id, application_id, status, created_at');
  assert.ok(!error, error?.message);
  const newestByApp = new Map();
  for (const r of data) {
    const cur = newestByApp.get(r.application_id);
    if (!cur || r.created_at > cur) newestByApp.set(r.application_id, r.created_at);
  }
  const orphans = (data || []).filter(
    (r) => ['scheduled', 'rescheduled'].includes(r.status) && r.created_at < newestByApp.get(r.application_id)
  );
  assert.equal(orphans.length, 0, `expected 0 orphan open rows, found ${orphans.length}: ${orphans.map((o) => o.id).join(',')}`);
});
