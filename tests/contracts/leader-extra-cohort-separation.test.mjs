/**
 * Forward-defense: #229 Phase 1 — leader_extra cohort separation.
 *
 * Origin: Issue #229 filed p209. A2 "minimal" isolation shipped fe80842c (p209,
 * 2026-05-21) stopped `submit_evaluation` leader_extra branch from MUTATING
 * `objective_score_avg`. Phase 1 (this migration, p219) completes the schema
 * + RPC plumbing for separate cohort PERT tracking:
 *
 *   - 6 dedicated columns (leader_extra_pert_target/band_lower/band_upper/
 *     calc_at/cohort_n/cutoff_method) on selection_applications
 *   - _compute_pert_cutoff_core extended to accept 'leader_extra_pert_score'
 *     and route UPDATEs to dedicated columns (vs shared pert_*)
 *   - recompute_all_active_pert_cutoffs cron extends to ALSO process leader_extra
 *   - Backfill leader_extra_pert_score for 15 NULL apps with >=2 submitted evals
 *
 * NOT in scope (Phase 2 / later):
 *   - Cleanup of pre-fe80842c inflated objective_score_avg
 *   - Frontend /admin/selection 2-cutoff band display
 *   - Analytics + MCP tool updates
 *
 * Cross-ref:
 *   - supabase/migrations/20260803000005_p219_229_phase1_leader_extra_cohort_separation.sql
 *   - supabase/migrations/20260802000002 + 20260802000003 (A1 fix, p209)
 *   - commit fe80842c (A2 minimal isolation, p209)
 *   - GH #229
 *   - P162 #150 (this Phase 1)
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATION_FILE = resolve(
  ROOT,
  'supabase/migrations/20260803000005_p219_229_phase1_leader_extra_cohort_separation.sql'
);

test('#229 Phase 1 migration adds 6 dedicated leader_extra_pert_* columns', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // ALTER TABLE adds 6 specific columns (target + band_lower + band_upper + calc_at + cohort_n + cutoff_method)
  const requiredColumns = [
    'leader_extra_pert_target numeric',
    'leader_extra_pert_band_lower numeric',
    'leader_extra_pert_band_upper numeric',
    'leader_extra_pert_calc_at timestamp with time zone',
    'leader_extra_pert_cohort_n int',
    'leader_extra_pert_cutoff_method text',
  ];
  for (const col of requiredColumns) {
    const pattern = new RegExp(`ADD COLUMN IF NOT EXISTS ${col.replace(/\s+/g, '\\s+')}`, 'i');
    assert.match(body, pattern, `Migration must ADD COLUMN ${col}`);
  }

  // ALTER TABLE targets selection_applications
  assert.match(body, /ALTER TABLE public\.selection_applications/i,
    'ALTER TABLE must target public.selection_applications');
});

test('#229 Phase 1 migration extends _compute_pert_cutoff_core to accept leader_extra_pert_score', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // allowed list includes leader_extra_pert_score
  assert.match(body, /p_score_column NOT IN \([^)]*'leader_extra_pert_score'[^)]*\)/i,
    '_compute_pert_cutoff_core must whitelist leader_extra_pert_score in p_score_column check');

  // CASE branch in cohort SELECT for leader_extra_pert_score
  assert.match(body, /WHEN 'leader_extra_pert_score' THEN sa\.leader_extra_pert_score/i,
    'cohort_apps CTE CASE must include leader_extra_pert_score branch');

  // v_is_leader_extra flag derived from p_score_column
  assert.match(body, /v_is_leader_extra := \(p_score_column = 'leader_extra_pert_score'\)/i,
    'function must compute v_is_leader_extra boolean from p_score_column');

  // UPDATE branched on v_is_leader_extra to route to dedicated columns
  assert.match(body, /IF v_is_leader_extra THEN\s+UPDATE public\.selection_applications\s+SET leader_extra_pert_target/i,
    'UPDATE must branch when v_is_leader_extra=true to set leader_extra_pert_target (not pert_target_score)');
  assert.match(body, /leader_extra_pert_band_lower = v_band_lower/i,
    'leader_extra branch UPDATEs leader_extra_pert_band_lower');
  assert.match(body, /leader_extra_pert_band_upper = v_band_upper/i,
    'leader_extra branch UPDATEs leader_extra_pert_band_upper');
});

test('#229 Phase 1 migration extends recompute_all_active_pert_cutoffs cron to process leader_extra', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // recompute_all_active_pert_cutoffs body
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.recompute_all_active_pert_cutoffs\(\)/i,
    'Migration must CREATE OR REPLACE recompute_all_active_pert_cutoffs');

  // Now processes BOTH objective + leader_extra dimensions
  assert.match(body, /_compute_pert_cutoff_core\(v_cycle\.id,\s*'researcher',\s*true,\s*'objective_score_avg',\s*NULL\)/i,
    'cron must call _compute_pert_cutoff_core for objective_score_avg');
  assert.match(body, /_compute_pert_cutoff_core\(v_cycle\.id,\s*'leader',\s*true,\s*'leader_extra_pert_score',\s*NULL\)/i,
    'cron must ALSO call _compute_pert_cutoff_core for leader_extra_pert_score with role=leader');

  // Result jsonb has BOTH branches
  assert.match(body, /'objective_result',\s*v_result_obj/i,
    'audit result must include objective_result');
  assert.match(body, /'leader_extra_result',\s*v_result_le/i,
    'audit result must include leader_extra_result');
});

test('#229 Phase 1 backfill targets only apps with >=min_evaluators leader_extra evals + NULL leader_extra_pert_score', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // Backfill scope guard
  assert.match(body, /WHERE sa\.leader_extra_pert_score IS NULL/i,
    'Backfill must filter to leader_extra_pert_score IS NULL (idempotency + scope)');
  assert.match(body, /evaluation_type = 'leader_extra'/i,
    'Backfill must reference leader_extra evaluations');
  assert.match(body, /AND se\.submitted_at IS NOT NULL/i,
    'Backfill must filter to submitted evaluations only');

  // min_evaluators threshold from selection_cycles
  assert.match(body, /array_length\(v_subtotals, 1\) < v_app\.min_evaluators/i,
    'Backfill must skip apps where submitted evals < cycle min_evaluators');

  // PERT formula (β-PERT: 2*min + 4*avg + 2*max) / 8 — matches submit_evaluation
  assert.match(body, /ROUND\(\(2 \* v_min_sub \+ 4 \* v_avg_sub \+ 2 \* v_max_sub\) \/ 8, 2\)/i,
    'Backfill PERT formula must match submit_evaluation (2*min + 4*avg + 2*max) / 8 rounded to 2 decimals');
});

test('#229 Phase 1 backfill writes admin_audit_log entries with before/after + reason', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  assert.match(body, /'p219_229_phase1_leader_extra_pert_score_backfill'/i,
    'Audit action key must identify the migration backfill');
  assert.match(body, /'leader_extra_pert_score_before',\s*NULL/i,
    'Audit must capture before value (NULL)');
  assert.match(body, /'leader_extra_pert_score_after',\s*v_pert/i,
    'Audit must capture after value (computed PERT)');
  assert.match(body, /'migration',\s*'20260803000005'/i,
    'Audit changes payload must reference migration version');
});

test('#229 Phase 1 sanity DO block fails loud if orphan apps remain', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  assert.match(body, /RAISE EXCEPTION '#229 Phase 1 sanity FAIL:[^']*applications still have NULL leader_extra_pert_score/i,
    'Migration must RAISE EXCEPTION if any app still NULL leader_extra_pert_score with >=2 submitted evals');
});

test('#229 Phase 1 migration file is registered per timestamp pattern', () => {
  const dir = resolve(ROOT, 'supabase/migrations');
  const files = readdirSync(dir).filter(f => f.startsWith('20260803000005_'));
  assert.equal(files.length, 1,
    'Exactly one migration file must exist for version 20260803000005 (p219 #229 Phase 1)');
  assert.match(files[0], /^20260803000005_p219_229_phase1_leader_extra_cohort_separation\.sql$/,
    'Migration filename must follow `<timestamp>_<descriptive_name>.sql` per CLAUDE.md GC-097');
});

test('#229 Phase 1 migration reloads PostgREST schema cache', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /NOTIFY pgrst,\s*'reload schema'/i,
    'Migration must NOTIFY pgrst reload schema (CLAUDE.md GC-097)');
});

test('#229 Phase 1 scope: NOT in scope items explicitly documented in header', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // Header must explicitly call out NOT-in-scope items so future sessions know to pick up Phase 2
  assert.match(body, /NOT in scope \(Phase 2/i,
    'Header must call out Phase 2 deferred items explicitly');
  assert.match(body, /Cleanup of pre-fe80842c inflated objective_score_avg/i,
    'Header must reference deferred obj_score_avg cleanup');
  assert.match(body, /Frontend \/admin\/selection 2-cutoff band display/i,
    'Header must reference deferred frontend work');
});
