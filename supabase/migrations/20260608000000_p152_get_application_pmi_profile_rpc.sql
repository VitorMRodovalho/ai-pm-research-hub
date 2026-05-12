-- p152 W4 P2 (2026-05-12) — RPC for "PMI Profile" modal tab.
--
-- Strategic: PM ask 12/05 — Avaliar tab + modal não surface info enriquecida
-- do JSON import VEP (certifications, capítulos múltiplos, voluntariado PMI
-- histórico per-role, profile bio). Hoje pmi_canonical subgroup no dashboard
-- mostra resumo mas não detalhes.
--
-- Novo RPC retorna 1 jsonb consolidado para a nova tab "📊 PMI":
--   - identity: pmi_id, member_status, member_since/until, is_member
--   - chapters: pmi_memberships array (multi-chapter)
--   - certifications: profile_certifications (PMI-verified) + certifications (form-declared)
--   - profile: industry, company, designation, about_me, linkedin_url,
--     specialties, volunteer_interest, location/city/state/country
--   - service_history: array of {chapter, role, start_date, end_date} per-role
--   - previous_cycles: same-email applications in prior cycles (returning candidate context)
--   - non_pmi_volunteering: form-declared (selection_applications.non_pmi_experience)
--
-- Auth: requires committee membership OR manage_platform (consistent with
-- get_evaluation_form pattern).

DROP FUNCTION IF EXISTS public.get_application_pmi_profile(uuid);
CREATE OR REPLACE FUNCTION public.get_application_pmi_profile(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_in_committee boolean;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found: %', p_application_id;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.selection_committee
    WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id
  ) INTO v_in_committee;

  IF NOT v_in_committee AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: requires committee membership or manage_platform';
  END IF;

  -- Log PII access for audit trail (Phase B fields are personal data per LGPD Art. 5 II)
  PERFORM public._log_application_pii_access(
    p_application_id,
    v_caller.id,
    ARRAY['pmi_id','profile_about_me','profile_company','profile_linkedin_url','pmi_memberships','service_history'],
    'get_application_pmi_profile'
  );

  RETURN jsonb_build_object(
    'identity', jsonb_build_object(
      'pmi_id', v_app.pmi_id,
      'is_pmi_member', (v_app.pmi_id IS NOT NULL AND v_app.pmi_id <> ''),
      'member_status', CASE
        WHEN v_app.pmi_id IS NULL OR v_app.pmi_id = '' THEN 'unknown'
        WHEN v_app.service_latest_end_date IS NULL THEN 'unknown'
        WHEN v_app.service_latest_end_date >= CURRENT_DATE THEN 'active'
        ELSE 'past'
      END,
      'member_since', v_app.service_first_start_date,
      'member_until', v_app.service_latest_end_date,
      'service_history_count', COALESCE(v_app.service_history_count, 0),
      'phase_b_fetched_at', v_app.pmi_data_fetched_at,
      'community_profile_private', v_app.community_profile_private
    ),
    'chapters', jsonb_build_object(
      'memberships', COALESCE(v_app.pmi_memberships, '[]'::jsonb),
      'service_history_chapters', v_app.service_history_chapters,
      'form_chapter', v_app.chapter,
      'chapter_affiliation', v_app.chapter_affiliation
    ),
    'certifications', jsonb_build_object(
      'verified', COALESCE(to_jsonb(v_app.profile_certifications), '[]'::jsonb),
      'form_declared', v_app.certifications
    ),
    'profile', jsonb_build_object(
      'industry', v_app.profile_industry,
      'company', v_app.profile_company,
      'designation', v_app.profile_designation,
      'about_me', v_app.profile_about_me,
      'linkedin_url', v_app.profile_linkedin_url,
      'specialties', v_app.profile_specialties,
      'volunteer_interest', v_app.profile_volunteer_interest,
      'location', v_app.profile_location,
      'city', v_app.profile_city,
      'state', v_app.profile_state,
      'country', v_app.profile_country,
      'is_open_to_volunteer', v_app.is_open_to_volunteer
    ),
    'service_history', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'chapter_name', sh.chapter_name,
        'role_name', sh.role_name,
        'start_date', sh.start_date,
        'end_date', sh.end_date,
        'source', sh.source
      ) ORDER BY sh.start_date DESC NULLS LAST)
      FROM public.selection_application_service_history sh
      WHERE sh.application_id = p_application_id
    ), '[]'::jsonb),
    'previous_cycles', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'application_id', pa.id,
        'cycle_code', pc.cycle_code,
        'role_applied', pa.role_applied,
        'status', pa.status,
        'final_score', pa.final_score,
        'application_date', pa.application_date,
        'rank_chapter', pa.rank_chapter,
        'rank_overall', pa.rank_overall
      ) ORDER BY pa.application_date DESC NULLS LAST)
      FROM public.selection_applications pa
      JOIN public.selection_cycles pc ON pc.id = pa.cycle_id
      WHERE lower(pa.email) = lower(v_app.email)
        AND pa.id <> p_application_id
    ), '[]'::jsonb),
    'non_pmi_volunteering', v_app.non_pmi_experience
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_application_pmi_profile(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
