-- p158 hotfix #2 part B: mirror_sibling_interview RPC + future-proof reusable path
--
-- PM directive (live test 2026-05-14): for William's dual_track pair, the researcher app had no
-- selection_interviews row (interview was scheduled+conducted only on the leader app). Opening
-- the "Entrevista" tab in the modal for the researcher app showed "Nenhuma entrevista agendada
-- ainda" with no live-eval option (status='submitted' didn't satisfy canStartLive gate). Leader
-- app interview was already locked (submitted). PM resorted to a one-shot SQL fix for William.
--
-- This RPC formalizes the path for future dual_track pairs: copies the sibling's most recent
-- completed interview row + the sibling's 'interview' evaluation to the current application.
-- Only role-agnostic interview criteria are mirrored (the 4 standard pillars: teamwork,
-- proactivity, communication, culture_alignment); leader-specific extras (e.g. theme question
-- in leader_extra eval, or any context-only theme pillars) are NOT copied — those stay attached
-- to the leader app only.
--
-- Guards:
--   - linked_application_id must be set + promotion_path='dual_track'
--   - target app must NOT already have an interview row (avoid double-create)
--   - sibling must have at least one submitted interview evaluation
--   - gated by manage_platform
-- Audits to data_anomaly_log with anomaly_type='selection_dual_track_interview_mirror'.

CREATE OR REPLACE FUNCTION public.mirror_sibling_interview(p_application_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id        uuid;
  v_app              record;
  v_sibling_id       uuid;
  v_source_interview record;
  v_source_eval      record;
  v_new_interview_id uuid;
  v_new_eval_id      uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN json_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN RETURN json_build_object('error', 'Application not found'); END IF;

  IF v_app.promotion_path IS DISTINCT FROM 'dual_track' OR v_app.linked_application_id IS NULL THEN
    RETURN json_build_object('error', 'Application is not part of a dual_track pair');
  END IF;

  v_sibling_id := v_app.linked_application_id;

  IF EXISTS (SELECT 1 FROM public.selection_interviews WHERE application_id = p_application_id) THEN
    RETURN json_build_object('error', 'Target application already has an interview row — refusing to overwrite');
  END IF;

  SELECT * INTO v_source_interview
  FROM public.selection_interviews
  WHERE application_id = v_sibling_id
    AND status = 'completed'
  ORDER BY conducted_at DESC NULLS LAST, scheduled_at DESC NULLS LAST
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Sibling application has no completed interview to mirror');
  END IF;

  SELECT * INTO v_source_eval
  FROM public.selection_evaluations
  WHERE application_id = v_sibling_id
    AND evaluation_type = 'interview'
    AND submitted_at IS NOT NULL
  ORDER BY submitted_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Sibling application has no submitted interview evaluation to mirror');
  END IF;

  INSERT INTO public.selection_interviews (
    application_id, interviewer_ids, scheduled_at, conducted_at, status,
    theme_of_interest, calendar_event_id, notes, duration_minutes, created_at
  ) VALUES (
    p_application_id,
    v_source_interview.interviewer_ids,
    v_source_interview.scheduled_at,
    v_source_interview.conducted_at,
    v_source_interview.status,
    v_source_interview.theme_of_interest,
    NULL,
    COALESCE(v_source_interview.notes, '') || E'\n\n[Espelhado da entrevista de líder/pesquisador sibling ' || v_source_interview.id::text || ' — 4 criterios role-agnostic.]',
    v_source_interview.duration_minutes,
    now()
  )
  RETURNING id INTO v_new_interview_id;

  INSERT INTO public.selection_evaluations (
    application_id, evaluator_id, evaluation_type, scores, weighted_subtotal,
    notes, submitted_at, created_at
  ) VALUES (
    p_application_id,
    v_source_eval.evaluator_id,
    'interview',
    v_source_eval.scores,
    v_source_eval.weighted_subtotal,
    COALESCE(v_source_eval.notes, '') || E'\n[Espelhado da avaliação interview sibling — 4 criterios role-agnostic. Theme question role-specific NOT espelhada.]',
    v_source_eval.submitted_at,
    now()
  )
  RETURNING id INTO v_new_eval_id;

  UPDATE public.selection_applications
  SET    interview_score = v_source_eval.weighted_subtotal,
         updated_at      = now()
  WHERE  id = p_application_id
    AND  interview_score IS NULL;

  INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
  VALUES (
    'selection_dual_track_interview_mirror',
    'info',
    v_app.applicant_name || ' — interview mirrored from sibling app',
    jsonb_build_object(
      'target_app_id',        p_application_id,
      'sibling_app_id',       v_sibling_id,
      'source_interview_id',  v_source_interview.id,
      'source_evaluation_id', v_source_eval.id,
      'new_interview_id',     v_new_interview_id,
      'new_evaluation_id',    v_new_eval_id,
      'weighted_subtotal',    v_source_eval.weighted_subtotal,
      'caller_id',            v_caller_id
    )
  );

  RETURN json_build_object(
    'success',           true,
    'target_app_id',     p_application_id,
    'sibling_app_id',    v_sibling_id,
    'new_interview_id',  v_new_interview_id,
    'new_evaluation_id', v_new_eval_id,
    'mirrored_score',    v_source_eval.weighted_subtotal
  );
END;
$function$;

COMMENT ON FUNCTION public.mirror_sibling_interview(uuid) IS
  'Mirrors sibling app interview row + evaluation onto target app for dual_track pairs. Copies the 4 role-agnostic criteria only (skips theme question / leader-specific extras). Refuses if target already has an interview row. Audits in data_anomaly_log. p158 hotfix#2 (2026-05-14).';

GRANT EXECUTE ON FUNCTION public.mirror_sibling_interview(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
