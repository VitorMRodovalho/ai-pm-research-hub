-- ARM P1 (post Onda 2): pii_access_log para abertura de dossiê de candidato
--
-- Estado pré: get_application_score_breakdown e get_evaluation_form retornam PII
-- (email, linkedin_url, resume_url, motivation_letter, ...) sem registrar em
-- pii_access_log. Apenas RPCs que tocam members têm essa cobertura.
--
-- Mudanças:
--   1) Helper _log_application_pii_access(application_id, accessor_id, fields, context)
--      faz INSERT em pii_access_log resolvendo target_member_id via email match
--      (selection_applications.email → members.email lower-cased)
--   2) get_application_score_breakdown chama helper após auth check
--   3) get_evaluation_form chama helper após auth check
--
-- Auditoria LGPD: cada acesso a dossiê de candidato fica rastreável (accessor +
-- target + campos + context + timestamp).
--
-- Rollback:
--   DROP FUNCTION public._log_application_pii_access(uuid,uuid,text[],text);
--   CREATE OR REPLACE FUNCTION ... versão sem helper call.

-- 1) Helper SECDEF (private — leading underscore + REVOKE de PUBLIC)
CREATE OR REPLACE FUNCTION public._log_application_pii_access(
  p_application_id uuid,
  p_accessor_id uuid,
  p_fields text[],
  p_context text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_target_member_id uuid;
  v_app_email text;
BEGIN
  SELECT email INTO v_app_email FROM public.selection_applications WHERE id = p_application_id;
  IF v_app_email IS NULL THEN RETURN; END IF;

  SELECT id INTO v_target_member_id FROM public.members
  WHERE lower(trim(email)) = lower(trim(v_app_email))
  LIMIT 1;

  -- target_member_id pode ser NULL para candidatos que ainda não viraram members
  -- (legítimo no funil pré-conversion). pii_access_log permite null.
  INSERT INTO public.pii_access_log (
    accessor_id, target_member_id, fields_accessed, context, accessed_at
  )
  VALUES (
    p_accessor_id, v_target_member_id, p_fields, p_context, now()
  );
EXCEPTION WHEN OTHERS THEN
  -- Fail-soft: logging não deve bloquear leitura legítima
  RAISE NOTICE '_log_application_pii_access failed: %', SQLERRM;
END;
$func$;

REVOKE ALL ON FUNCTION public._log_application_pii_access(uuid,uuid,text[],text) FROM PUBLIC, anon, authenticated;
-- Apenas chamado por outros SECDEF wrappers; não direct-callable

-- 2) get_application_score_breakdown — append pii_access_log após auth check
CREATE OR REPLACE FUNCTION public.get_application_score_breakdown(p_application_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_evals jsonb;
  v_blind boolean;
  v_hidden text[];
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR NOT (
    v_caller.is_superadmin = true
    OR can_by_member(v_caller.id, 'manage_member')
    OR (v_caller.designations && ARRAY['curator'])
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM selection_applications WHERE id = p_application_id;
  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('error', 'application_not_found');
  END IF;

  -- p107 ARM P1: log dossiê access
  PERFORM public._log_application_pii_access(
    p_application_id,
    v_caller.id,
    ARRAY['email','applicant_name','evaluations'],
    'get_application_score_breakdown'
  );

  SELECT * INTO v_cycle FROM selection_cycles WHERE id = v_app.cycle_id;

  v_blind := COALESCE(v_cycle.phase, 'planning') IN ('evaluating', 'interviews')
             AND v_caller.is_superadmin IS NOT TRUE;

  IF v_blind THEN
    SELECT jsonb_agg(jsonb_build_object(
      'evaluation_type', e.evaluation_type,
      'evaluator_name', m.name,
      'evaluator_id', m.id,
      'weighted_subtotal', e.weighted_subtotal,
      'submitted_at', e.submitted_at,
      'scores', e.scores,
      'is_own', true
    ) ORDER BY e.evaluation_type)
    INTO v_evals
    FROM selection_evaluations e
    JOIN members m ON m.id = e.evaluator_id
    WHERE e.application_id = p_application_id
      AND e.submitted_at IS NOT NULL
      AND e.evaluator_id = v_caller.id;

    v_hidden := ARRAY['other_evaluators_names', 'other_evaluators_scores', 'other_evaluators_subtotals'];
  ELSE
    SELECT jsonb_agg(jsonb_build_object(
      'evaluation_type', e.evaluation_type,
      'evaluator_name', m.name,
      'evaluator_id', m.id,
      'weighted_subtotal', e.weighted_subtotal,
      'submitted_at', e.submitted_at,
      'scores', e.scores,
      'is_own', e.evaluator_id = v_caller.id
    ) ORDER BY e.evaluation_type, m.name)
    INTO v_evals
    FROM selection_evaluations e
    JOIN members m ON m.id = e.evaluator_id
    WHERE e.application_id = p_application_id AND e.submitted_at IS NOT NULL;

    v_hidden := ARRAY[]::text[];
  END IF;

  RETURN jsonb_build_object(
    'application_id', v_app.id,
    'applicant_name', v_app.applicant_name,
    'email', v_app.email,
    'role_applied', v_app.role_applied,
    'promotion_path', v_app.promotion_path,
    'status', v_app.status,
    'research_score', v_app.research_score,
    'leader_score', v_app.leader_score,
    'rank_researcher', v_app.rank_researcher,
    'rank_leader', v_app.rank_leader,
    'evaluations', COALESCE(v_evals, '[]'::jsonb),
    'linked_application_id', v_app.linked_application_id,
    'blind_review_active', v_blind,
    'cycle_phase', COALESCE(v_cycle.phase, 'unknown'),
    'hidden_fields', v_hidden
  );
END;
$func$;

-- 3) get_evaluation_form — append pii_access_log após auth check
CREATE OR REPLACE FUNCTION public.get_evaluation_form(p_application_id uuid, p_evaluation_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_caller record; v_app record; v_cycle record; v_committee record; v_draft record; v_criteria jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN RAISE EXCEPTION 'Application not found: %', p_application_id; END IF;
  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;
  SELECT * INTO v_committee FROM public.selection_committee WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;
  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member';
  END IF;

  -- p107 ARM P1: log dossiê access (rich PII surface)
  PERFORM public._log_application_pii_access(
    p_application_id,
    v_caller.id,
    ARRAY['email','applicant_name','linkedin_url','resume_url','motivation_letter','leadership_experience','academic_background'],
    'get_evaluation_form:' || p_evaluation_type
  );

  v_criteria := CASE p_evaluation_type
    WHEN 'objective' THEN v_cycle.objective_criteria
    WHEN 'interview' THEN v_cycle.interview_criteria
    WHEN 'leader_extra' THEN v_cycle.leader_extra_criteria
    ELSE '[]'::jsonb END;

  SELECT * INTO v_draft FROM public.selection_evaluations
  WHERE application_id = p_application_id AND evaluator_id = v_caller.id AND evaluation_type = p_evaluation_type;

  RETURN jsonb_build_object(
    'application', jsonb_build_object(
      'id', v_app.id, 'applicant_name', v_app.applicant_name, 'email', v_app.email,
      'chapter', v_app.chapter, 'role_applied', v_app.role_applied,
      'certifications', v_app.certifications, 'linkedin_url', v_app.linkedin_url,
      'resume_url', v_app.resume_url, 'motivation_letter', v_app.motivation_letter,
      'reason_for_applying', v_app.reason_for_applying,
      'chapter_affiliation', v_app.chapter_affiliation,
      'non_pmi_experience', v_app.non_pmi_experience, 'areas_of_interest', v_app.areas_of_interest,
      'availability_declared', v_app.availability_declared, 'proposed_theme', v_app.proposed_theme,
      'leadership_experience', v_app.leadership_experience, 'academic_background', v_app.academic_background,
      'membership_status', v_app.membership_status, 'status', v_app.status
    ),
    'criteria', v_criteria, 'evaluation_type', p_evaluation_type,
    'committee_role', COALESCE(v_committee.role, 'platform_admin'),
    'draft', CASE WHEN v_draft IS NOT NULL THEN jsonb_build_object(
      'id', v_draft.id, 'scores', v_draft.scores, 'notes', v_draft.notes,
      'criterion_notes', COALESCE(v_draft.criterion_notes, '{}'::jsonb),
      'weighted_subtotal', v_draft.weighted_subtotal, 'submitted_at', v_draft.submitted_at
    ) ELSE NULL END,
    'is_locked', CASE WHEN v_draft.submitted_at IS NOT NULL THEN true ELSE false END
  );
END;
$func$;

NOTIFY pgrst, 'reload schema';
