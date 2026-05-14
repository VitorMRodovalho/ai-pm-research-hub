-- p158 F3: get_dual_track_merged_payload — return merged essays + AI analysis for dual_track pair
--
-- Problem (PM directive 2026-05-14): the candidate modal in /admin/selection renders fields
-- (areas_of_interest, proposed_theme, leadership_experience, etc.) from the SINGLE application
-- row clicked in the list. For a dual_track candidate, this means PM sees only the fields
-- captured on that specific app (e.g. leader app has proposed_theme but NULL areas_of_interest;
-- researcher app has areas_of_interest but NULL proposed_theme). PM's words: "voce omitiu as
-- informacoes do questionario da vaga de lider que nao apareceu na candidatura via UI".
--
-- This RPC returns, given either application_id of a dual_track pair:
--   (a) Both apps' full essay+score+AI fields in clearly labeled researcher_app / leader_app
--   (b) A merged_essays object with COALESCE-merged questionnaire fields for direct rendering
--   (c) A merged_ai_analysis object aggregating AI triage outputs across both apps
--   (d) A scores_summary with per-role objective/interview/final scores
--
-- UI uses this on modal open when row.promotion_path = 'dual_track' to render both essay
-- sections (researcher's areas_of_interest + leader's proposed_theme/leadership_experience).
--
-- For non-dual_track apps the RPC returns is_dual_track=false plus the single app's fields
-- in primary_app — UI can fallback gracefully without branching at fetch time.
--
-- Gated by view_internal_analytics (broader read access than manage_platform — PM + evaluators
-- can both load the modal). Internal admin_update_application is the gate for writes.

CREATE OR REPLACE FUNCTION public.get_dual_track_merged_payload(p_application_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id  uuid;
  v_app        record;
  v_sibling    record;
  v_researcher record;
  v_leader     record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Application not found');
  END IF;

  IF v_app.linked_application_id IS NULL OR v_app.promotion_path IS DISTINCT FROM 'dual_track' THEN
    RETURN jsonb_build_object(
      'is_dual_track',     false,
      'pair_role_in_view', v_app.role_applied,
      'primary_app',       to_jsonb(v_app)
    );
  END IF;

  SELECT * INTO v_sibling FROM public.selection_applications WHERE id = v_app.linked_application_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'is_dual_track', false,
      'error',         'Sibling application missing despite linked_application_id',
      'primary_app',   to_jsonb(v_app)
    );
  END IF;

  IF v_app.role_applied = 'researcher' THEN
    v_researcher := v_app;
    v_leader     := v_sibling;
  ELSE
    v_researcher := v_sibling;
    v_leader     := v_app;
  END IF;

  RETURN jsonb_build_object(
    'is_dual_track',     true,
    'pair_role_in_view', v_app.role_applied,
    'researcher_app',    to_jsonb(v_researcher),
    'leader_app',        to_jsonb(v_leader),
    'merged_essays', jsonb_build_object(
      'motivation_letter',     COALESCE(v_leader.motivation_letter,     v_researcher.motivation_letter),
      'non_pmi_experience',    COALESCE(v_leader.non_pmi_experience,    v_researcher.non_pmi_experience),
      'areas_of_interest',     COALESCE(v_researcher.areas_of_interest, v_leader.areas_of_interest),
      'proposed_theme',        COALESCE(v_leader.proposed_theme,        v_researcher.proposed_theme),
      'leadership_experience', COALESCE(v_leader.leadership_experience, v_researcher.leadership_experience),
      'academic_background',   COALESCE(v_leader.academic_background,   v_researcher.academic_background)
    ),
    'merged_ai_analysis', jsonb_build_object(
      'ai_triage_score',       COALESCE(v_leader.ai_triage_score,       v_researcher.ai_triage_score),
      'ai_triage_reasoning',   COALESCE(v_leader.ai_triage_reasoning,   v_researcher.ai_triage_reasoning),
      'ai_triage_confidence',  COALESCE(v_leader.ai_triage_confidence,  v_researcher.ai_triage_confidence),
      'ai_triage_at',          GREATEST(v_leader.ai_triage_at,          v_researcher.ai_triage_at),
      'ai_triage_model',       COALESCE(v_leader.ai_triage_model,       v_researcher.ai_triage_model),
      'ai_pm_focus_tags', (
        SELECT to_jsonb(array_agg(DISTINCT t))
        FROM (
          SELECT jsonb_array_elements_text(COALESCE(v_leader.ai_pm_focus_tags, '[]'::jsonb)) AS t
          UNION
          SELECT jsonb_array_elements_text(COALESCE(v_researcher.ai_pm_focus_tags, '[]'::jsonb))
        ) u
      ),
      'has_researcher_analysis', v_researcher.ai_triage_at IS NOT NULL,
      'has_leader_analysis',     v_leader.ai_triage_at IS NOT NULL
    ),
    'scores_summary', jsonb_build_object(
      'researcher_objective', v_researcher.objective_score_avg,
      'researcher_interview', v_researcher.interview_score,
      'researcher_final',     v_researcher.final_score,
      'leader_objective',     v_leader.objective_score_avg,
      'leader_interview',     v_leader.interview_score,
      'leader_final',         v_leader.final_score
    )
  );
END;
$function$;

COMMENT ON FUNCTION public.get_dual_track_merged_payload(uuid) IS
  'Returns merged questionnaire + AI analysis fields for a dual_track candidate pair, given either application_id. UI uses this on modal open when row.promotion_path=dual_track to render BOTH essay sections (researcher areas_of_interest + leader proposed_theme/leadership_experience). For non-pair apps returns is_dual_track=false. p158 F3 (2026-05-14).';

GRANT EXECUTE ON FUNCTION public.get_dual_track_merged_payload(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
