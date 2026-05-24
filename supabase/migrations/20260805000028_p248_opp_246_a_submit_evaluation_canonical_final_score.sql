-- ============================================================================
-- p248 OPP-246.A — submit_evaluation canonical final_score (drop naïve sum race)
-- ============================================================================
--
-- WHAT
-- 1. CREATE OR REPLACE FUNCTION submit_evaluation: remove inline naïve-sum
--    `final_score = obj + interview + leader_extra` from leader_extra +
--    interview branches; add explicit PERFORM compute_application_scores()
--    in both branches for defense-in-depth (the AFTER-INSERT trigger
--    trg_recompute_application_scores already invokes compute, but the
--    inline UPDATE was overriding its canonical write — see audit doc
--    docs/audit/OPP_246_A_FRANCISLEILA_FINAL_SCORE_DRIFT.md).
--    Signature preserved exactly (6 args, 3 with DEFAULT NULL); SECDEF +
--    search_path=public preserved (matches live state — not bumping to
--    'public', 'pg_temp' to keep minimum-diff per scope match).
--
-- 2. PM Option B cleanup: PERFORM compute_application_scores on Francisleila's
--    application (cycle4-2026 leader, the only row in the entire DB with this
--    drift class) to reconcile final_score from naïve 309.00 → canonical
--    158.30 (= leader_score per CR-047). Plus an admin_audit_log row
--    documenting the canonical reconciliation.
--
-- 3. Sanity DO block: RAISE if any leader has final_score IS DISTINCT FROM
--    COALESCE(leader_score, research_score) after the refactor. Catches both
--    pre-existing drifts (today's audit showed Francisleila is the only one,
--    and Step 2 fixes her) AND any new drift snuck in between migration write
--    and apply.
--
-- WHY
-- - `submit_evaluation` has had a structural race since its inception: it
--   INSERTs a new selection_evaluations row, which fires
--   `_trg_recompute_application_scores` → `compute_application_scores` →
--   canonical `final_score = COALESCE(leader_score, research_score)` (CR-047
--   weighted). Then submit_evaluation's own UPDATE on selection_applications
--   wrote `final_score = obj + interview + leader_extra` (naïve sum),
--   OVERRIDING the canonical value. For most apps this self-heals via
--   `submit_interview_scores` (modern interview path explicitly calls
--   `compute_application_scores`), but apps stuck pre-interview after a
--   `submit_evaluation('leader_extra')` call retain the naïve sum.
--
-- - The drift surfaced visibly on /admin/selection in p247 (#229b Frontend)
--   when the per-candidate Final régua chip rendered Francisleila with
--   `final_score=309` versus declared composite formula expectation 158.30
--   (PM call-out 2026-05-24 post-p246 close).
--
-- - Audit (`docs/audit/OPP_246_A_FRANCISLEILA_FINAL_SCORE_DRIFT.md`) found
--   drift isolated to 1 row (Francisleila, cycle4 leader, screening); approved
--   leader cohort (8 apps all-time) all clean. PM ratified Option C+B = fix
--   structural bug AND clean up immediate visible drift.
--
-- ROLLBACK
-- - The CREATE OR REPLACE is reversible by restoring the prior body
--   (preserved verbatim in `submit_evaluation` history via the audit doc
--   block above + the original migration file capturing the introducing
--   commit). A future "revert" migration would CREATE OR REPLACE with the
--   prior body to re-introduce the naïve-sum UPDATE. NOTE: any rows updated
--   by Step 2 (Francisleila's final_score = 158.30) would NOT be reverted by
--   that rollback — they'd stay canonical, since canonical IS the truth per
--   CR-047. The rollback only restores the bug class.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.submit_evaluation(
  p_application_id uuid,
  p_evaluation_type text,
  p_scores jsonb,
  p_notes text DEFAULT NULL::text,
  p_criterion_notes jsonb DEFAULT NULL::jsonb,
  p_ai_suggestion_id uuid DEFAULT NULL::uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_committee record;
  v_criteria jsonb;
  v_criterion jsonb;
  v_key text;
  v_score numeric;
  v_weight numeric;
  v_max numeric;
  v_weighted_sum numeric := 0;
  v_eval_id uuid;
  v_total_evaluators int;
  v_submitted_count int;
  v_all_subtotals numeric[];
  v_pert_score numeric;
  v_min_sub numeric;
  v_max_sub numeric;
  v_avg_sub numeric;
  v_cutoff numeric;
  v_median numeric;
  v_new_status text;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN RAISE EXCEPTION 'Application not found'; END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  SELECT * INTO v_committee FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;
  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.selection_evaluations
    WHERE application_id = p_application_id
      AND evaluator_id = v_caller.id
      AND evaluation_type = p_evaluation_type
      AND submitted_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Evaluation already submitted and locked';
  END IF;

  v_criteria := CASE p_evaluation_type
    WHEN 'objective' THEN v_cycle.objective_criteria
    WHEN 'interview' THEN v_cycle.interview_criteria
    WHEN 'leader_extra' THEN v_cycle.leader_extra_criteria
    ELSE '[]'::jsonb
  END;

  FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_criteria)
  LOOP
    v_key := v_criterion ->> 'key';
    v_weight := COALESCE((v_criterion ->> 'weight')::numeric, 1);
    v_max := COALESCE((v_criterion ->> 'max')::numeric, 10);
    IF NOT (p_scores ? v_key) THEN RAISE EXCEPTION 'Missing score for criterion: %', v_key; END IF;
    v_score := (p_scores ->> v_key)::numeric;
    IF v_score IS NULL THEN RAISE EXCEPTION 'Score for % must be numeric', v_key; END IF;
    IF v_score < 0 OR v_score > v_max THEN
      RAISE EXCEPTION 'Score % for criterion "%" must be between 0 and % (schema max)', v_score, v_key, v_max;
    END IF;
    v_weighted_sum := v_weighted_sum + (v_weight * v_score);
  END LOOP;

  INSERT INTO public.selection_evaluations (
    application_id, evaluator_id, evaluation_type,
    scores, weighted_subtotal, notes, criterion_notes, submitted_at
  ) VALUES (
    p_application_id, v_caller.id, p_evaluation_type,
    p_scores, ROUND(v_weighted_sum, 2), p_notes,
    COALESCE(p_criterion_notes, '{}'::jsonb), now()
  )
  ON CONFLICT (application_id, evaluator_id, evaluation_type)
  DO UPDATE SET
    scores = EXCLUDED.scores,
    weighted_subtotal = EXCLUDED.weighted_subtotal,
    notes = EXCLUDED.notes,
    criterion_notes = EXCLUDED.criterion_notes,
    submitted_at = now()
  RETURNING id INTO v_eval_id;

  SELECT COUNT(*) INTO v_total_evaluators FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND role IN ('evaluator', 'lead');

  SELECT COUNT(*) INTO v_submitted_count FROM public.selection_evaluations
  WHERE application_id = p_application_id AND evaluation_type = p_evaluation_type AND submitted_at IS NOT NULL;

  IF v_submitted_count >= v_cycle.min_evaluators THEN
    SELECT ARRAY_AGG(weighted_subtotal ORDER BY weighted_subtotal) INTO v_all_subtotals
    FROM public.selection_evaluations
    WHERE application_id = p_application_id AND evaluation_type = p_evaluation_type AND submitted_at IS NOT NULL;

    v_min_sub := v_all_subtotals[1];
    v_max_sub := v_all_subtotals[array_upper(v_all_subtotals, 1)];
    SELECT AVG(unnest) INTO v_avg_sub FROM unnest(v_all_subtotals);
    v_pert_score := ROUND((2 * v_min_sub + 4 * v_avg_sub + 2 * v_max_sub) / 8, 2);

    IF p_evaluation_type = 'objective' THEN
      UPDATE public.selection_applications SET objective_score_avg = v_pert_score, updated_at = now() WHERE id = p_application_id;
      SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY objective_score_avg) INTO v_median
      FROM public.selection_applications WHERE cycle_id = v_app.cycle_id AND objective_score_avg IS NOT NULL;
      v_cutoff := ROUND(COALESCE(v_median, 0) * 0.75, 2);
      IF v_pert_score < v_cutoff AND v_cutoff > 0 THEN v_new_status := 'objective_cutoff'; ELSE v_new_status := 'interview_pending'; END IF;
      UPDATE public.selection_applications SET status = v_new_status, updated_at = now()
      WHERE id = p_application_id AND status IN ('submitted', 'screening', 'objective_eval');
    ELSIF p_evaluation_type = 'interview' THEN
      -- p248 OPP-246.A: final_score derivation moved to canonical compute_application_scores
      -- (CR-047 weighted formula). Trigger trg_recompute_application_scores on the
      -- selection_evaluations INSERT above already invokes it; the inline naive-sum UPDATE
      -- (final_score = obj + interview + leader_extra) was overriding that canonical write.
      -- Defense-in-depth: explicit PERFORM after our status='final_eval' UPDATE.
      UPDATE public.selection_applications
        SET interview_score = v_pert_score,
            status = 'final_eval',
            updated_at = now()
      WHERE id = p_application_id;
      PERFORM public.compute_application_scores(p_application_id);
    ELSIF p_evaluation_type = 'leader_extra' THEN
      -- p248 OPP-246.A: final_score derivation moved to canonical compute_application_scores
      -- (see interview branch comment above for full context).
      UPDATE public.selection_applications
        SET leader_extra_pert_score = v_pert_score,
            updated_at = now()
      WHERE id = p_application_id;
      PERFORM public.compute_application_scores(p_application_id);
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'evaluation_id', v_eval_id, 'weighted_subtotal', ROUND(v_weighted_sum, 2),
    'all_submitted', v_submitted_count >= v_cycle.min_evaluators,
    'pert_score', v_pert_score, 'new_status', v_new_status
  );
END;
$$;

-- ============================================================================
-- Step B (PM Option B cleanup): reconcile Francisleila's drifted final_score
-- via canonical compute_application_scores. Plus audit log row.
-- ============================================================================

DO $cleanup$
DECLARE
  v_francisleila_id uuid := '72ea1a45-8dc8-4b0b-b4cb-f1427968ff22';
  v_before_final numeric;
  v_after_final numeric;
  v_compute_result jsonb;
  v_canonical_expected numeric;
BEGIN
  -- Snapshot before
  SELECT final_score INTO v_before_final
  FROM public.selection_applications
  WHERE id = v_francisleila_id;

  -- Skip if row no longer exists or has no drift (defensive — protects against re-apply)
  IF v_before_final IS NULL THEN
    RAISE NOTICE 'p248 OPP-246.A cleanup: Francisleila row not found, skipping';
    RETURN;
  END IF;

  -- Canonical reconciliation
  v_compute_result := public.compute_application_scores(v_francisleila_id);

  -- Snapshot after
  SELECT final_score INTO v_after_final
  FROM public.selection_applications
  WHERE id = v_francisleila_id;

  -- Compute canonical expected for audit verification
  SELECT COALESCE(leader_score, research_score) INTO v_canonical_expected
  FROM public.selection_applications
  WHERE id = v_francisleila_id;

  -- Audit log only if we actually changed the value (idempotent)
  IF v_before_final IS DISTINCT FROM v_after_final THEN
    INSERT INTO public.admin_audit_log (
      action, target_type, target_id, actor_id, metadata
    ) VALUES (
      'selection.final_score_canonical_reconciliation',
      'selection_application',
      v_francisleila_id,
      NULL,  -- system reconciliation, no human actor
      jsonb_build_object(
        'before_final_score', v_before_final,
        'after_final_score', v_after_final,
        'canonical_expected', v_canonical_expected,
        'compute_result', v_compute_result,
        'reason', 'p248 OPP-246.A — naïve sum from submit_evaluation race overridden by canonical compute_application_scores',
        'rpc_version', 'p248',
        'migration', '20260805000028',
        'audit_doc', 'docs/audit/OPP_246_A_FRANCISLEILA_FINAL_SCORE_DRIFT.md'
      )
    );
    RAISE NOTICE 'p248 OPP-246.A cleanup: Francisleila final_score % → %', v_before_final, v_after_final;
  ELSE
    RAISE NOTICE 'p248 OPP-246.A cleanup: Francisleila already canonical (final=%, no change)', v_after_final;
  END IF;
END
$cleanup$;

-- ============================================================================
-- Sanity DO block — RAISE if any leader has drift after the refactor +
-- cleanup. Catches both Francisleila (if cleanup failed) and any new drift.
-- ============================================================================

DO $sanity$
DECLARE
  v_drift_count int;
  v_drift_details text;
BEGIN
  WITH leader_drift AS (
    SELECT sa.id, sa.applicant_name, sa.final_score,
           COALESCE(sa.leader_score, sa.research_score) AS canonical
    FROM public.selection_applications sa
    WHERE sa.role_applied = 'leader'
      AND sa.final_score IS NOT NULL
      AND COALESCE(sa.leader_score, sa.research_score) IS NOT NULL
      AND abs(sa.final_score - COALESCE(sa.leader_score, sa.research_score)) > 0.5
  )
  SELECT
    COUNT(*),
    string_agg(applicant_name || ' (final=' || final_score || ', canonical=' || canonical || ')', '; ')
  INTO v_drift_count, v_drift_details
  FROM leader_drift;

  IF v_drift_count > 0 THEN
    RAISE EXCEPTION 'p248 OPP-246.A sanity: % leader row(s) still have final_score drift > 0.5pt after refactor + cleanup: %',
      v_drift_count, v_drift_details;
  END IF;

  RAISE NOTICE 'p248 OPP-246.A sanity: 0 leader rows with final_score drift (post-refactor)';
END
$sanity$;

NOTIFY pgrst, 'reload schema';
