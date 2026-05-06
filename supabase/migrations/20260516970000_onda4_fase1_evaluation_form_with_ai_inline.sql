-- ARM Onda 4 Fase 1 (p109): inline AI panel substrate
--
-- Atende PM pain point #2 ("AI em tab → inline note validável").
-- Move sinais IA (Gemini raises_the_bar + Sonnet 4.6 triage) inline na tela de
-- avaliação, lado a lado, para PM validar contra impressão própria.
-- Briefing entrevista (Haiku 4.5) persiste e renderiza na tab Entrevista
-- (Opção C ratificada por PM 2026-05-06).
--
-- Mudanças:
--   1. ALTER selection_applications: +last_briefing_jsonb / +last_briefing_at /
--      +last_briefing_model. Permite cache server-side do briefing (pula re-call
--      Haiku se PM revisita). Sobrescreve no próximo regenerate.
--   2. DROP + CREATE get_evaluation_form: payload da application passa a incluir
--      ai_triage_* (Sonnet 4.6) + ai_analysis JSONB (Gemini snapshot mais recente)
--      + last_briefing_* + consent_ai_analysis_at. Frontend renderiza inline panel
--      sem RPC adicional.
--
-- ADR ref: ADR-0074 (dual-model AI architecture)
-- ADR-0011 ref: SECURITY DEFINER preservado, auth via members + selection_committee
--
-- LGPD considerações: ai_analysis e ai_triage_* já são purgados em consent_revoke
-- (trigger _trg_purge_ai_analysis_on_consent_revocation, migration 940000).
-- last_briefing_jsonb também precisa purgar em consent_revoke — adicionado abaixo.
--
-- Rollback:
--   ALTER TABLE selection_applications DROP COLUMN last_briefing_*;
--   Reverter get_evaluation_form para versão de 20260401100000.

-- 1. Briefing cache columns
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS last_briefing_jsonb jsonb,
  ADD COLUMN IF NOT EXISTS last_briefing_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_briefing_model text;

COMMENT ON COLUMN public.selection_applications.last_briefing_jsonb IS
  'p109 ARM Onda 4 Fase 1: snapshot do último briefing entrevista gerado (Haiku 4.5). Schema: { personalized_questions: [{question, rationale}×3], interview_focus_areas: string[3-5], preparation_notes: string }. Sobrescreve em regenerate. Purgado em consent revoke.';
COMMENT ON COLUMN public.selection_applications.last_briefing_at IS
  'p109 ARM Onda 4 Fase 1: timestamp do último briefing gerado.';
COMMENT ON COLUMN public.selection_applications.last_briefing_model IS
  'p109 ARM Onda 4 Fase 1: model_id do último briefing (e.g. claude-haiku-4-5).';

-- 2. Estender purge trigger para incluir last_briefing_*
-- (consent revoke trigger original em migration 940000 — ai_triage_* + ai_analysis purga)
CREATE OR REPLACE FUNCTION _trg_purge_ai_analysis_on_consent_revocation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.consent_ai_analysis_revoked_at IS NOT NULL
     AND OLD.consent_ai_analysis_revoked_at IS NULL THEN
    UPDATE public.selection_applications
       SET linkedin_relevant_posts = NULL,
           cv_extracted_text = NULL,
           ai_pm_focus_tags = NULL,
           ai_analysis = NULL,
           ai_triage_score = NULL,
           ai_triage_reasoning = NULL,
           ai_triage_confidence = NULL,
           ai_triage_at = NULL,
           ai_triage_model = NULL,
           last_briefing_jsonb = NULL,
           last_briefing_at = NULL,
           last_briefing_model = NULL
     WHERE id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION _trg_purge_ai_analysis_on_consent_revocation() IS
  'p109 ARM Onda 4 Fase 1 (extends p108 940000): purga AI-derived fields em consent revoke. Inclui briefing cache (Onda 4) além de ai_analysis legacy + ai_triage_* (Onda 3). ai_processing_log retido per Art. 16 (audit trail).';

-- 3. DROP + CREATE get_evaluation_form com sinais IA + briefing cache
DROP FUNCTION IF EXISTS get_evaluation_form(uuid, text);
CREATE FUNCTION get_evaluation_form(p_application_id uuid, p_evaluation_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
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
  IF v_committee IS NULL AND v_caller.is_superadmin IS NOT TRUE THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member for this cycle';
  END IF;

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
      'non_pmi_experience', v_app.non_pmi_experience, 'areas_of_interest', v_app.areas_of_interest,
      'availability_declared', v_app.availability_declared, 'proposed_theme', v_app.proposed_theme,
      'leadership_experience', v_app.leadership_experience, 'academic_background', v_app.academic_background,
      'membership_status', v_app.membership_status, 'status', v_app.status,
      -- p109 Onda 4 Fase 1: sinais IA inline
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
    'committee_role', COALESCE(v_committee.role, 'superadmin'),
    'draft', CASE WHEN v_draft IS NOT NULL THEN jsonb_build_object(
      'id', v_draft.id, 'scores', v_draft.scores, 'notes', v_draft.notes,
      'criterion_notes', COALESCE(v_draft.criterion_notes, '{}'::jsonb),
      'weighted_subtotal', v_draft.weighted_subtotal, 'submitted_at', v_draft.submitted_at
    ) ELSE NULL END,
    'is_locked', CASE WHEN v_draft.submitted_at IS NOT NULL THEN true ELSE false END
  );
END;
$$;

COMMENT ON FUNCTION get_evaluation_form(uuid, text) IS
  'p109 ARM Onda 4 Fase 1 (extends 20260401100000): payload inclui consent_ai_analysis_at + ai_analysis (Gemini) + ai_triage_* (Sonnet 4.6) + last_briefing_* (Haiku 4.5) para inline AI panel na tela de avaliação. Auth: comissão do ciclo OU superadmin.';

NOTIFY pgrst, 'reload schema';
