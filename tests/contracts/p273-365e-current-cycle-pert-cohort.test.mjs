import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const MIGRATION_PATH = 'supabase/migrations/20260805000050_p273_365e_current_cycle_pert_cohort.sql';
const SQL = readFileSync(MIGRATION_PATH, 'utf8');

describe('p273 #365e — CR-042 current-cycle PERT cohort correction', () => {
  it('preserves _compute_pert_cutoff_core 5-arg signature and defaults', () => {
    assert.match(
      SQL,
      /CREATE OR REPLACE FUNCTION public\._compute_pert_cutoff_core\(\s*p_cycle_id uuid,\s*p_role text DEFAULT 'researcher'::text,\s*p_filter_active_only boolean DEFAULT true,\s*p_score_column text DEFAULT 'objective_score_avg'::text,\s*p_actor_id uuid DEFAULT NULL::uuid\s*\) RETURNS jsonb/,
      'must preserve function identity and all defaults for existing callers'
    );
  });

  it('switches cohort source to current-cycle applications scoped by role', () => {
    assert.match(SQL, /FROM public\.selection_applications sa\s*WHERE sa\.cycle_id = p_cycle_id\s*AND sa\.role_applied = p_role/);
    assert.doesNotMatch(SQL, /WITH prior_cycles AS/i);
    assert.doesNotMatch(SQL, /sa\.cycle_id IN \(SELECT id FROM prior_cycles\)/i);
    assert.doesNotMatch(SQL, /created_at < \(SELECT created_at FROM public\.selection_cycles/i);
  });

  it('removes historical approved-active volunteer gate from the cutoff cohort', () => {
    assert.doesNotMatch(SQL, /sa\.status = 'approved'/);
    assert.doesNotMatch(SQL, /JOIN public\.engagements e/);
    assert.doesNotMatch(SQL, /e\.kind = 'volunteer'/);
    assert.doesNotMatch(SQL, /e\.status = 'active'/);
    assert.match(SQL, /'filter_active_only_legacy_arg', p_filter_active_only/);
  });

  it('keeps CR-042 PERT formula unchanged', () => {
    assert.match(SQL, /v_target := \(2 \* v_cohort\.s_min \+ 4 \* v_cohort\.s_avg \+ 2 \* v_cohort\.s_max\) \/ 8;/);
  });

  it('uses complete final-score components for final_score cohort', () => {
    assert.match(SQL, /WHEN 'final_score' THEN\s*sa\.final_score IS NOT NULL\s*AND sa\.interview_score IS NOT NULL\s*AND \(\s*p_role != 'leader'\s*OR sa\.leader_extra_pert_score IS NOT NULL\s*\)/);
  });

  it('keeps objective/research/leader-extra score-dimension filters intact', () => {
    assert.match(SQL, /WHEN 'objective_score_avg' THEN sa\.objective_score_avg IS NOT NULL/);
    assert.match(SQL, /WHEN 'research_score' THEN sa\.research_score IS NOT NULL/);
    assert.match(SQL, /WHEN 'leader_extra_pert_score' THEN sa\.leader_extra_pert_score IS NOT NULL/);
  });

  it('does not auto-decide candidates while recalibrating cutoffs', () => {
    assert.doesNotMatch(SQL, /UPDATE public\.selection_applications\s+SET\s+status\s*=/i);
    assert.doesNotMatch(SQL, /status\s*=\s*'(approved|rejected|converted|waitlisted)'/i);
  });

  it('runs retroactive recompute through the existing batch RPC', () => {
    assert.match(SQL, /PERFORM public\.recompute_all_active_pert_cutoffs\(\);/);
    assert.match(SQL, /NOTIFY pgrst, 'reload schema';/);
  });

  it('documents current-cycle cohort scope in audit and function comment', () => {
    assert.match(SQL, /'cohort_scope', 'current_cycle_applications_by_role'/);
    assert.match(SQL, /COMMENT ON FUNCTION public\._compute_pert_cutoff_core\(uuid, text, boolean, text, uuid\) IS\s*'p273 #365e: CR-042 current-cycle PERT cutoff core/);
  });
});
