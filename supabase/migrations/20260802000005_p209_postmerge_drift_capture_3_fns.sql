-- p209 / post-merge drift capture (3 functions)
--
-- Captures live body of 3 functions that drifted post-PR-merges at p209 close.
-- Pattern source for each:
--
-- 1. _trg_pmi_video_screening_voice_consent_check() — TRUE ORPHAN (Q-C fail)
--    Created in PR #222 (issue #221 Whisper Art. 11 RETROATIVO) via apply_migration
--    MCP at p208, but the .sql file in PR #222 does NOT contain this trigger
--    function definition. Q-C orphan check (by name) flags it. Captured here as canonical.
--
-- 2. _test_invariants_with_synthetic_breach(p_breach text) — file vs live drift (Phase C)
--    PR #215 council fix commit (11f626f8) modified the migration body. Live body
--    was applied at p206 via apply_migration with pre-fix version. File body now
--    differs from live. Live IS canonical; re-capture aligns.
--
-- 3. submit_evaluation(...) — file vs live drift (Phase C)
--    Modified 3x at p209: A1.2 max validation + A2 minimal cohort separation.
--    Minor whitespace difference vs pg_get_functiondef output causes Phase C hash
--    mismatch. Re-capture sync.
--
-- Applied via pg_get_functiondef(oid) at p209 post-merge cleanup 2026-05-21.
-- Bodies byte-equivalent to live state — NO-OP per [[feedback-pg-get-functiondef-idempotent-capture]].

CREATE OR REPLACE FUNCTION public._test_invariants_with_synthetic_breach(p_breach text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cycle_id uuid;
  v_org_id uuid;
  v_test_email text;
  v_result jsonb;
BEGIN
  IF current_setting('role', true) NOT IN ('service_role', 'postgres')
     AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: _test_invariants_with_synthetic_breach requires service_role';
  END IF;

  IF p_breach NOT IN ('R', 'S') THEN
    RAISE EXCEPTION 'Invalid p_breach value: % (must be ''R'' or ''S'')', p_breach;
  END IF;

  SELECT id, organization_id
  INTO v_cycle_id, v_org_id
  FROM public.selection_cycles
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_cycle_id IS NULL THEN
    RAISE EXCEPTION 'No selection_cycles available — cannot seed synthetic breach';
  END IF;

  v_test_email := '__test_invariant_' || lower(p_breach) || '_' ||
                  replace(gen_random_uuid()::text, '-', '') || '@invariant.test';

  INSERT INTO public.selection_applications (
    cycle_id, organization_id, applicant_name, email, role_applied, status
  ) VALUES (
    v_cycle_id, v_org_id,
    '__test_invariant_synthetic__', v_test_email,
    'researcher', 'approved'
  );

  IF p_breach = 'S' THEN
    INSERT INTO public.members (
      organization_id, name, email, member_status, person_id, chapter
    ) VALUES (
      v_org_id, '__test_invariant_synthetic__', v_test_email,
      'active', NULL, 'Outro'
    );
  END IF;

  SELECT jsonb_agg(row_to_json(t) ORDER BY t.invariant_name)
  INTO v_result
  FROM public.check_schema_invariants() t
  WHERE t.invariant_name IN (
    'R_approved_application_has_member',
    'S_approved_member_has_person_id'
  );

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public._trg_pmi_video_screening_voice_consent_check()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_consent_at timestamptz;
  v_revoked_at timestamptz;
  v_transcription_being_set boolean;
BEGIN
  v_transcription_being_set := (
    TG_OP = 'INSERT' AND NEW.transcription IS NOT NULL
  ) OR (
    TG_OP = 'UPDATE' AND NEW.transcription IS NOT NULL
    AND (OLD.transcription IS DISTINCT FROM NEW.transcription)
  );

  IF NOT v_transcription_being_set THEN
    RETURN NEW;
  END IF;

  SELECT consent_voice_biometric_at, consent_voice_biometric_revoked_at
  INTO v_consent_at, v_revoked_at
  FROM public.selection_applications
  WHERE id = NEW.application_id;

  IF v_consent_at IS NULL THEN
    RAISE EXCEPTION 'LGPD Art. 11 §I: voice biometric consent required before transcription. selection_applications.consent_voice_biometric_at IS NULL for application_id = %. See issue #218 + ADR-0094.', NEW.application_id
      USING ERRCODE = 'check_violation', HINT = 'Capture explicit destacado consent (Art. 11 §I) via /portal-aplicacao or admin override before allowing Whisper transcription.';
  END IF;

  IF v_revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'LGPD Art. 11 §I: voice biometric consent revoked at % for application_id = %. Transcription blocked + retroactive deletion required (Art. 18 §IV).', v_revoked_at, NEW.application_id
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_evaluation(p_application_id uuid, p_evaluation_type text, p_scores jsonb, p_notes text DEFAULT NULL::text, p_criterion_notes jsonb DEFAULT NULL::jsonb, p_ai_suggestion_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      UPDATE public.selection_applications SET interview_score = v_pert_score,
        final_score = COALESCE(objective_score_avg, 0) + v_pert_score + COALESCE(leader_extra_pert_score, 0),
        status = 'final_eval', updated_at = now()
      WHERE id = p_application_id;
    ELSIF p_evaluation_type = 'leader_extra' THEN
      UPDATE public.selection_applications SET
        leader_extra_pert_score = v_pert_score,
        final_score = COALESCE(objective_score_avg, 0) + COALESCE(interview_score, 0) + v_pert_score,
        updated_at = now()
      WHERE id = p_application_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'evaluation_id', v_eval_id, 'weighted_subtotal', ROUND(v_weighted_sum, 2),
    'all_submitted', v_submitted_count >= v_cycle.min_evaluators,
    'pert_score', v_pert_score, 'new_status', v_new_status
  );
END;
$function$;
