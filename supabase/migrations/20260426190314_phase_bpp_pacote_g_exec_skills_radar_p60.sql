-- Phase B'' Pacote G (p60) — single-fn V3→V4 manage_platform
-- exec_skills_radar: read-only RPC, V3 superadmin OR manager/deputy_manager.
-- V4 manage_platform set = same 2 (superadmin override). Zero expansion.
-- IMPORTANT: original semantic returns empty JSON ('{}') for unauthorized,
-- NOT raise exception (fail-safe silent). Preserve that behavior.

DROP FUNCTION IF EXISTS public.exec_skills_radar();
CREATE OR REPLACE FUNCTION public.exec_skills_radar()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  result json;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN '{}'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN '{}';
  END IF;

  SELECT coalesce(json_agg(row_to_json(t)), '[]'::json) INTO result FROM (
    SELECT
      tr.id AS tribe_id, tr.name AS tribe_name,
      count(m.id) AS member_count,
      count(CASE WHEN m.credly_profile_url IS NOT NULL AND m.credly_profile_url != '' THEN 1 END) AS credly_count,
      count(CASE WHEN m.photo_url IS NOT NULL AND m.photo_url != '' THEN 1 END) AS photo_count,
      count(CASE WHEN m.linkedin IS NOT NULL AND m.linkedin != '' THEN 1 END) AS linkedin_count,
      coalesce((
        SELECT count(*)::int FROM public.publication_submissions ps
        WHERE ps.status = 'published'::public.submission_status
          AND EXISTS(SELECT 1 FROM public.members am WHERE am.id = ps.primary_author_id AND am.tribe_id = tr.id)
      ), 0) AS artifacts_count
    FROM public.tribes tr
    LEFT JOIN public.members m ON m.tribe_id = tr.id AND m.current_cycle_active = true
    WHERE tr.is_active = true
    GROUP BY tr.id, tr.name ORDER BY tr.id
  ) t;
  RETURN result;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.exec_skills_radar() FROM PUBLIC, anon;
COMMENT ON FUNCTION public.exec_skills_radar() IS
  'Phase B'' V4 conversion (p60 Pacote G): manage_platform gate via can_by_member. Was V3 (superadmin OR manager/deputy_manager). Returns empty JSON for unauthorized (preserved fail-safe silent semantic — NOT raise exception). search_path hardened to ''''.';

NOTIFY pgrst, 'reload schema';
