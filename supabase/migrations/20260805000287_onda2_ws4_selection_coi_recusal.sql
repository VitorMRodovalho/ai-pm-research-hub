-- Onda 2 — WS-4: conflict-of-interest recusal from the selection scores surface (ADR-0109).
--
-- Policy (legal-counsel BLOCKER + accountability, council 2026-06-28): a caller who is an ACTIVE
-- candidate (non-terminal selection_applications row) in a cycle must NOT be able to read that
-- cycle's selection scores/rankings, even if they otherwise hold selection-read authority
-- (view_internal_analytics — e.g. a chapter president / sponsor who also applied). Segregation of
-- duties (PMI Code §4 Fairness) + LGPD finalidade/Art.6,VII (an evaluated candidate seeing
-- competitors' scores is a non-discrimination/finalidade violation). The "PMI-Amazonas president who
-- applies as researcher" mix-case. GROUNDED 2026-06-28: 0 current instances (forward-defense).
--
-- GP (manage_platform) administers selection and is NEVER recused — member-lifecycle/selection-admin
-- is GP-only by design. The recused persona is a non-GP selection-access holder who also applied.
--
-- Scope of THIS migration: the helper primitive + the gate on get_selection_rankings (the SCORES
-- surface — the COI crux). The larger get_selection_dashboard (18.9KB) + sibling read RPCs
-- (pipeline_metrics / health / application detail / vep_divergence) get the same gate in the tracked
-- fast-follow (ADR-0109 PR-2). 0 current instances → no exposure window for that follow-up.
--
-- Cross-ref: docs/adr/ADR-0109-selection-coi-recusal.md, docs/reference/V4_AUTHORITY_MODEL.md, handoff pt6 WS-4.

-- Helper: is the caller an active candidate in this cycle (and not GP)? → recused.
-- Internal-only: SECURITY DEFINER, REVOKED from anon/authenticated so it cannot be called directly
-- via PostgREST (that would leak candidate status of an arbitrary member). Called by the selection
-- read RPCs, which run as the definer.
CREATE OR REPLACE FUNCTION public.selection_coi_recused(p_caller_id uuid, p_cycle_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT
    p_cycle_id IS NOT NULL
    AND p_caller_id IS NOT NULL
    AND NOT public.can_by_member(p_caller_id, 'manage_platform')
    AND EXISTS (
      SELECT 1
      FROM public.selection_applications sa
      JOIN public.members m ON m.id = p_caller_id
      WHERE sa.cycle_id = p_cycle_id
        AND sa.status NOT IN ('rejected','withdrawn','cancelled')
        AND sa.email IS NOT NULL
        AND (
          lower(sa.email) = lower(m.email)
          OR EXISTS (
            SELECT 1 FROM public.member_emails me
            WHERE me.member_id = m.id AND lower(me.email) = lower(sa.email)
          )
        )
    );
$function$;

REVOKE ALL ON FUNCTION public.selection_coi_recused(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.selection_coi_recused(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.selection_coi_recused(uuid, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.selection_coi_recused(uuid, uuid) TO service_role;

-- Gate get_selection_rankings with the recusal check (inserted after cycle resolution).
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

  -- ADR-0109 COI recusal: an active candidate in this cycle is recused from the scores surface.
  IF public.selection_coi_recused(v_caller_id, v_cycle_id) THEN
    RETURN jsonb_build_object('error', 'recused_conflict_of_interest',
      'detail', 'Você é candidato(a) neste ciclo — as visões de seleção estão impedidas por conflito de interesse (ADR-0109).');
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
