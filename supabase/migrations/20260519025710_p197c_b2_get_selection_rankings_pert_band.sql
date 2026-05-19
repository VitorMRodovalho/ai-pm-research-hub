-- p197c B2 (2026-05-19): extend get_selection_rankings with pert_cutoff top-level block
-- + pert_band_position per row (below/within/above/null) so committee + MCP consumers can
-- color-code rankings against the cohort of approved active members. Additive only.
-- Auth unchanged (view_internal_analytics).

DROP FUNCTION IF EXISTS public.get_selection_rankings(text, text);

CREATE OR REPLACE FUNCTION public.get_selection_rankings(p_cycle_code text DEFAULT NULL::text, p_track text DEFAULT 'both'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_pert_cutoff jsonb;
  v_researcher jsonb;
  v_leader jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: admin/GP/curator only');
  END IF;

  IF p_cycle_code IS NOT NULL THEN
    SELECT id INTO v_cycle_id FROM public.selection_cycles WHERE cycle_code = p_cycle_code;
  ELSE
    SELECT id INTO v_cycle_id FROM public.selection_cycles ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No cycle found');
  END IF;

  -- p197c B2: pert_cutoff aggregated from selection_applications (same per cycle)
  SELECT jsonb_build_object(
    'target_score', MAX(pert_target_score),
    'band_lower', MAX(pert_band_lower),
    'band_upper', MAX(pert_band_upper),
    'cohort_n', MAX(pert_cohort_n),
    'method', MAX(pert_cutoff_method),
    'calc_at', MAX(pert_calc_at)
  ) INTO v_pert_cutoff
  FROM public.selection_applications WHERE cycle_id = v_cycle_id;

  IF p_track IN ('researcher', 'both') THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'rank', rank_researcher,
      'applicant_name', applicant_name,
      'chapter', chapter,
      'research_score', research_score,
      'status', status,
      'promotion_path', promotion_path,
      -- p197c B2: band_position helps UI/MCP color-code each row
      'pert_band_position', CASE
        WHEN research_score IS NULL OR pert_band_lower IS NULL OR pert_band_upper IS NULL THEN NULL
        WHEN research_score < pert_band_lower THEN 'below'
        WHEN research_score > pert_band_upper THEN 'above'
        ELSE 'within'
      END
    ) ORDER BY rank_researcher), '[]'::jsonb)
    INTO v_researcher
    FROM public.selection_applications
    WHERE cycle_id = v_cycle_id AND rank_researcher IS NOT NULL;
  END IF;

  IF p_track IN ('leader', 'both') THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'rank', rank_leader,
      'applicant_name', applicant_name,
      'chapter', chapter,
      'research_score', research_score,
      'leader_score', leader_score,
      'status', status,
      'promotion_path', promotion_path,
      'pert_band_position', CASE
        WHEN leader_score IS NULL OR pert_band_lower IS NULL OR pert_band_upper IS NULL THEN NULL
        WHEN leader_score < pert_band_lower THEN 'below'
        WHEN leader_score > pert_band_upper THEN 'above'
        ELSE 'within'
      END
    ) ORDER BY rank_leader), '[]'::jsonb)
    INTO v_leader
    FROM public.selection_applications
    WHERE cycle_id = v_cycle_id AND rank_leader IS NOT NULL;
  END IF;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'track', p_track,
    'pert_cutoff', v_pert_cutoff,
    'researcher_track', COALESCE(v_researcher, '[]'::jsonb),
    'leader_track', COALESCE(v_leader, '[]'::jsonb),
    'formula', jsonb_build_object(
      'research_score', 'objective_pert + interview_pert',
      'leader_score', 'research_score * 0.7 + leader_extra_pert * 0.3',
      'tiebreaker', 'Standard Competition Ranking (ISO 80000-2) + applicant_name ASC'
    )
  );
END;
$function$;

COMMENT ON FUNCTION public.get_selection_rankings(text, text) IS
  'p197c B2 (2026-05-19): adds pert_cutoff top-level block (target_score + band_lower/upper + cohort_n + method + calc_at) + pert_band_position per row (below/within/above/null based on research_score or leader_score vs band). MCP + UI consumers can now color-code rankings against approved active members cohort without separate get_pert_cutoff_summary call. Formula + ordering preserved exactly. Auth unchanged (view_internal_analytics).';
