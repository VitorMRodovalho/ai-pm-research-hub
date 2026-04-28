-- Item 5 (handoff 25/Abr): Vitor prometeu Fabricio rota Credly visibility para TLs.
-- Decision #16 C (both): A enrich per-member + B aggregate dashboard.
-- get_my_tribe_members handoff-referenced não existe; criando ambas como novas RPCs.

CREATE OR REPLACE FUNCTION public.get_tribe_members_with_credly(p_tribe_id integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_is_admin boolean;
  v_result jsonb;
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  v_is_admin := public.can_by_member(v_caller_id, 'manage_member');

  IF NOT v_is_admin
     AND NOT (v_caller_role = 'tribe_leader' AND v_caller_tribe = p_tribe_id)
     AND v_caller_tribe IS DISTINCT FROM p_tribe_id THEN
    RETURN jsonb_build_object('error', 'Unauthorized: TL of tribe or admin required');
  END IF;

  WITH tribe_members AS (
    SELECT
      m.id, m.name, m.photo_url, m.operational_role, m.designations, m.chapter,
      m.member_status, m.is_active, m.person_id,
      m.credly_url,
      m.credly_verified_at,
      m.tribe_id,
      m.current_cycle_active
    FROM public.members m
    WHERE m.tribe_id = p_tribe_id
      AND m.member_status = 'active'
  ),
  badges AS (
    SELECT
      member_id,
      count(*) FILTER (WHERE type = 'trail') AS trail_count,
      bool_or(type = 'trail' AND status = 'active') AS trail_completed,
      bool_or(type = 'cert_pmi_senior') AS cert_pmi_senior,
      bool_or(type = 'cpmai') AS cpmai_certified,
      count(*) FILTER (WHERE status = 'active') AS total_badges
    FROM public.certificates
    GROUP BY member_id
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', tm.id,
    'name', tm.name,
    'photo_url', tm.photo_url,
    'operational_role', tm.operational_role,
    'designations', tm.designations,
    'chapter', tm.chapter,
    'current_cycle_active', tm.current_cycle_active,
    'person_id', tm.person_id,
    'credly_url', tm.credly_url,
    'credly_verified_at', tm.credly_verified_at,
    'badges_summary', jsonb_build_object(
      'trail_count', coalesce(b.trail_count, 0),
      'trail_completed', coalesce(b.trail_completed, false),
      'cert_pmi_senior', coalesce(b.cert_pmi_senior, false),
      'cpmai_certified', coalesce(b.cpmai_certified, false),
      'total_badges', coalesce(b.total_badges, 0)
    )
  ) ORDER BY tm.name), '[]'::jsonb)
  INTO v_result
  FROM tribe_members tm
  LEFT JOIN badges b ON b.member_id = tm.id;

  RETURN jsonb_build_object(
    'tribe_id', p_tribe_id,
    'members', v_result,
    'fetched_at', now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_tribe_members_with_credly(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_tribe_members_with_credly(integer) TO authenticated;

COMMENT ON FUNCTION public.get_tribe_members_with_credly(integer) IS
'Item 5 handoff 25/Abr: per-member tribe view enriquecida com Credly status. Authority: admin (any tribe) OR tribe_leader/researcher (own tribe).';

CREATE OR REPLACE FUNCTION public.get_tribe_credly_status(p_tribe_id integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_is_admin boolean;
  v_total int;
  v_with_credly int;
  v_trail_completed int;
  v_cpmai_certified int;
  v_pmi_senior int;
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  v_is_admin := public.can_by_member(v_caller_id, 'manage_member');

  IF NOT v_is_admin
     AND NOT (v_caller_role = 'tribe_leader' AND v_caller_tribe = p_tribe_id)
     AND v_caller_tribe IS DISTINCT FROM p_tribe_id THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT
    count(*),
    count(*) FILTER (WHERE m.credly_url IS NOT NULL AND length(trim(m.credly_url)) > 0)
  INTO v_total, v_with_credly
  FROM public.members m
  WHERE m.tribe_id = p_tribe_id AND m.member_status = 'active';

  SELECT
    count(DISTINCT c.member_id) FILTER (WHERE c.type = 'trail' AND c.status = 'active'),
    count(DISTINCT c.member_id) FILTER (WHERE c.type = 'cpmai' AND c.status = 'active'),
    count(DISTINCT c.member_id) FILTER (WHERE c.type = 'cert_pmi_senior' AND c.status = 'active')
  INTO v_trail_completed, v_cpmai_certified, v_pmi_senior
  FROM public.certificates c
  JOIN public.members m ON m.id = c.member_id
  WHERE m.tribe_id = p_tribe_id AND m.member_status = 'active';

  RETURN jsonb_build_object(
    'tribe_id', p_tribe_id,
    'members_total', coalesce(v_total, 0),
    'members_with_credly_linked', coalesce(v_with_credly, 0),
    'credly_link_rate', CASE WHEN v_total > 0 THEN ROUND(v_with_credly::numeric / v_total, 2) ELSE 0 END,
    'trail_completed_count', coalesce(v_trail_completed, 0),
    'trail_completion_rate', CASE WHEN v_total > 0 THEN ROUND(v_trail_completed::numeric / v_total, 2) ELSE 0 END,
    'cpmai_certified_count', coalesce(v_cpmai_certified, 0),
    'pmi_senior_count', coalesce(v_pmi_senior, 0),
    'fetched_at', now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_tribe_credly_status(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_tribe_credly_status(integer) TO authenticated;

COMMENT ON FUNCTION public.get_tribe_credly_status(integer) IS
'Item 5 handoff 25/Abr: aggregate Credly dashboard por tribo. Authority: admin (any) OR tribe_leader/researcher (own tribe).';

NOTIFY pgrst, 'reload schema';
