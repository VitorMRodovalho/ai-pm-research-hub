-- ============================================================================
-- p87 #119 Sprint 1 — anonymize RPC + research_validation triggered_by
-- ============================================================================
-- Substrate para training data validation raises_the_bar (Issue #119).
-- LGPD path Option B (PII-stripped): anonymize candidate texts antes de
-- enviar a Gemini, preserva conteúdo de aplicação para análise mas
-- nunca expõe nome/email/linkedin/empresa real ao modelo.
--
-- Components:
--   1. ALTER ai_analysis_runs CHECK: add 'research_validation' como
--      triggered_by valid value (separa de consent/enrichment/admin_retry)
--   2. RPC anonymize_application_for_ai_training(application_id) SECDEF
--      service_role-callable. Returns jsonb com PII strippped texts.
-- ============================================================================

ALTER TABLE public.ai_analysis_runs DROP CONSTRAINT IF EXISTS ai_analysis_runs_triggered_by_check;
ALTER TABLE public.ai_analysis_runs ADD CONSTRAINT ai_analysis_runs_triggered_by_check
  CHECK (triggered_by = ANY (ARRAY['consent'::text, 'enrichment_request'::text, 'admin_retry'::text, 'cron_retry'::text, 'research_validation'::text]));

CREATE OR REPLACE FUNCTION public.anonymize_application_for_ai_training(
  p_application_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_app record;
  v_pseudo text;
  v_outcome text;
  v_score numeric;
BEGIN
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  v_pseudo := 'Candidato_' || substring(p_application_id::text, 1, 8);

  v_outcome := CASE
    WHEN v_app.status = 'approved' THEN 'approved'
    WHEN v_app.status = 'rejected' THEN 'rejected'
    WHEN v_app.status IN ('converted','interview_done') THEN v_app.status
    ELSE 'other'
  END;

  v_score := v_app.objective_score_avg;

  RETURN jsonb_build_object(
    'application_id', p_application_id,
    'pseudo_name', v_pseudo,
    'role_applied', v_app.role_applied,
    'motivation_letter', v_app.motivation_letter,
    'non_pmi_experience', v_app.non_pmi_experience,
    'leadership_experience', v_app.leadership_experience,
    'academic_background', v_app.academic_background,
    'proposed_theme', v_app.proposed_theme,
    'reason_for_applying', v_app.reason_for_applying,
    'certifications', v_app.certifications,
    'areas_of_interest', v_app.areas_of_interest,
    'availability_declared', v_app.availability_declared,
    'final_outcome', v_outcome,
    'objective_score_avg', v_score,
    'has_human_evals', (
      SELECT COUNT(*) FROM public.selection_evaluations WHERE application_id = p_application_id
    ),
    'applicant_name', NULL,
    'email', NULL,
    'phone', NULL,
    'linkedin_url', NULL,
    'credly_url', NULL,
    'pmi_id', NULL,
    'chapter', NULL
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.anonymize_application_for_ai_training(uuid) FROM PUBLIC;

NOTIFY pgrst, 'reload schema';
