-- #625 C1-b: admin_list_members must use the canonical pre-onboarding helper.
--
-- Previous bodies (142, then 148) carried an inline LATERAL copy of the cohort rule.
-- The helper public.member_is_pre_onboarding(uuid, text) was introduced in 143 as the
-- single source for the same rule. This migration removes the inline copy from the RPC
-- so homepage, dashboard and admin members cannot drift independently.

CREATE OR REPLACE FUNCTION public.admin_list_members(
  p_search text DEFAULT NULL::text,
  p_tier text DEFAULT NULL::text,
  p_tribe_id integer DEFAULT NULL::integer,
  p_status text DEFAULT 'active'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', m.id,
      'full_name', m.name,
      'email', m.email,
      'photo_url', m.photo_url,
      'operational_role', m.operational_role,
      'designations', m.designations,
      'is_superadmin', m.is_superadmin,
      'is_active', m.is_active,
      'member_status', m.member_status,
      'tribe_id', m.tribe_id,
      'tribe_name', tc.name,
      'chapter', m.chapter,
      'auth_id', m.auth_id,
      'last_seen_at', m.last_seen_at,
      'total_sessions', COALESCE(m.total_sessions, 0),
      'credly_username', m.credly_url,
      'offboarded_at', m.offboarded_at,
      'status_change_reason', m.status_change_reason,
      'vep_status_raw', vep.vep_status_raw,
      'vep_last_seen_at', vep.vep_last_seen_at,
      'is_pre_onboarding', public.member_is_pre_onboarding(m.person_id, m.member_status),
      -- #625 F1: farol de filiacao (cache + ultima verificacao da trilha append-only)
      'pmi_id_verified', COALESCE(m.pmi_id_verified, false),
      'affiliation_last_verified_at', aff.last_verified_at,
      'affiliation_active', aff.membership_active,
      'affiliation_expires_on', aff.membership_expires_on,
      'affiliation_method', aff.method
    ) ORDER BY m.name), '[]'::jsonb)
    FROM public.members m
    LEFT JOIN public.tribes tc ON tc.id = m.tribe_id
    LEFT JOIN LATERAL (
      SELECT a.vep_status_raw, a.vep_last_seen_at
      FROM public.selection_applications a
      WHERE lower(a.email) = lower(m.email)
        AND a.vep_status_raw IS NOT NULL
      ORDER BY a.vep_last_seen_at DESC NULLS LAST
      LIMIT 1
    ) vep ON true
    -- #625 C1-b: single source for the pre-onboarding cohort rule.
    -- public.member_is_pre_onboarding() is intentionally not exposed to anon/authenticated;
    -- this SECURITY DEFINER RPC invokes it internally.
    LEFT JOIN LATERAL (
      SELECT mav.created_at AS last_verified_at, mav.membership_active,
             mav.membership_expires_on, mav.method
      FROM public.member_affiliation_verifications mav
      WHERE mav.member_id = m.id
      ORDER BY mav.created_at DESC
      LIMIT 1
    ) aff ON true
    WHERE (p_status = 'all'
        OR (p_status = 'active' AND m.member_status = 'active')
        OR (p_status = 'inactive' AND m.member_status = 'inactive')
        OR (p_status = 'observer' AND m.member_status = 'observer')
        OR (p_status = 'alumni' AND m.member_status = 'alumni')
        OR (p_status = 'pre_onboarding' AND public.member_is_pre_onboarding(m.person_id, m.member_status)))
      AND (p_tier IS NULL OR m.operational_role = p_tier)
      AND (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
      AND (p_search IS NULL OR m.name ILIKE '%' || p_search || '%' OR m.email ILIKE '%' || p_search || '%')
  );
END;
$function$;

COMMENT ON FUNCTION public.admin_list_members(text, text, integer, text) IS
  '#625 C1-b: lists members for admin/member surfaces; pre-onboarding cohort rule delegates to member_is_pre_onboarding.';

REVOKE ALL ON FUNCTION public.admin_list_members(text, text, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_members(text, text, integer, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
