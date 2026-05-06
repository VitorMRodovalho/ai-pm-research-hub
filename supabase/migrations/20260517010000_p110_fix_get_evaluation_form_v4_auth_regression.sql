-- p110 hotfix: get_evaluation_form V4 auth + PII log regression
--
-- Estado pré: p109 Onda 4 Fase 1 (migration 20260516970000) usou versão antiga
-- da função (datada de 20260401100000) como base ao adicionar AI inline + briefing.
-- Resultado: dois patches anteriores foram silenciosamente revertidos:
--   1) ADR-0011 V4 auth: 20260516170000 (Phase B'' batch 20.1) trocou
--      "is_superadmin IS TRUE" por can_by_member('manage_platform').
--      970000 voltou para is_superadmin → falha contract test rpc-v4-auth.
--   2) p107 ARM P1 (20260516810000): adicionou _log_application_pii_access após
--      auth check. 970000 omitiu → access dossiê (email, applicant_name, linkedin,
--      resume, motivation, leadership, academic) parou de logar em pii_access_log.
--   3) Campos reason_for_applying + chapter_affiliation foram removidos do payload
--      (estavam em 170000 + 810000).
--   4) committee_role fallback caiu de 'platform_admin' para 'superadmin'.
--
-- Estado pós: V4 auth restaurado + PII log restaurado + campos restaurados.
-- Mantém extensões Onda 4 (consent_ai_analysis_at, ai_analysis Gemini snapshot,
-- ai_triage_* Sonnet 4.6, last_briefing_* Haiku 4.5).
--
-- Funcionalidade pré-Onda 4 não regrediu em prod (is_superadmin column ainda
-- existe, retorna dados para superadmins). Mas teste contract bloqueia +
-- LGPD audit trail estava silenciosamente quebrado desde 2026-05-06.
--
-- ADR refs: ADR-0011 (V4 authority), ADR-0074 (dual-model AI architecture).
-- Rollback: nenhum (estritamente compositive — restaura o que p107+Phase B'' já tinham).

-- Note: keep name unqualified (`get_evaluation_form`, not `public.get_evaluation_form`)
-- to match 970000's signature pattern. The contract test rpc-v4-auth.test.mjs keys
-- its rpcLatest map by the captured name string — schema-qualified vs unqualified
-- create distinct keys, so a fix must use the same form as the migration it's
-- correcting. Functionally identical (search_path = public, pg_temp).
CREATE OR REPLACE FUNCTION get_evaluation_form(p_application_id uuid, p_evaluation_type text)
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

  SELECT * INTO v_committee FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;

  -- p110 hotfix: V4 auth pattern (was: v_caller.is_superadmin IS NOT TRUE)
  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member';
  END IF;

  -- p110 hotfix: restored from p107 ARM P1 (810000) — dossiê PII access log
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
    ELSE '[]'::jsonb
  END;

  SELECT * INTO v_draft FROM public.selection_evaluations
  WHERE application_id = p_application_id AND evaluator_id = v_caller.id AND evaluation_type = p_evaluation_type;

  RETURN jsonb_build_object(
    'application', jsonb_build_object(
      'id', v_app.id, 'applicant_name', v_app.applicant_name, 'email', v_app.email,
      'chapter', v_app.chapter, 'role_applied', v_app.role_applied,
      'certifications', v_app.certifications, 'linkedin_url', v_app.linkedin_url,
      'resume_url', v_app.resume_url, 'motivation_letter', v_app.motivation_letter,
      -- p110 hotfix: restored from 170000+810000 (regredido em 970000)
      'reason_for_applying', v_app.reason_for_applying,
      'chapter_affiliation', v_app.chapter_affiliation,
      'non_pmi_experience', v_app.non_pmi_experience, 'areas_of_interest', v_app.areas_of_interest,
      'availability_declared', v_app.availability_declared, 'proposed_theme', v_app.proposed_theme,
      'leadership_experience', v_app.leadership_experience, 'academic_background', v_app.academic_background,
      'membership_status', v_app.membership_status, 'status', v_app.status,
      -- p109 Onda 4 Fase 1 (preservado): sinais IA inline
      'consent_ai_analysis_at', v_app.consent_ai_analysis_at,
      'ai_analysis', v_app.ai_analysis,
      'ai_triage_score', v_app.ai_triage_score,
      'ai_triage_reasoning', v_app.ai_triage_reasoning,
      'ai_triage_confidence', v_app.ai_triage_confidence,
      'ai_triage_at', v_app.ai_triage_at,
      'ai_triage_model', v_app.ai_triage_model,
      'last_briefing_jsonb', v_app.last_briefing_jsonb,
      'last_briefing_at', v_app.last_briefing_at,
      'last_briefing_model', v_app.last_briefing_model
    ),
    'criteria', v_criteria,
    'evaluation_type', p_evaluation_type,
    -- p110 hotfix: fallback restaurado para 'platform_admin' (era 'superadmin' em 970000)
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

COMMENT ON FUNCTION public.get_evaluation_form(uuid, text) IS
  'p110 hotfix (extends p109 970000 + restores p107 810000 + Phase B 170000): payload Onda 4 (AI inline + briefing) preservado; V4 auth pattern can_by_member(manage_platform) restaurado; PII access log restaurado; reason_for_applying + chapter_affiliation restaurados. Auth: comissão do ciclo OU manage_platform.';

NOTIFY pgrst, 'reload schema';
