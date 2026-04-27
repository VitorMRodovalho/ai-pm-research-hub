-- ADR-0031 (Accepted, p66): admin_list_members V4 conversion
-- Phase B'' V3→V4 conversion via Opção B reuse view_internal_analytics (ADR-0030).
-- See docs/adr/ADR-0031-admin-list-members-v4-conversion.md
--
-- PM ratified Q1-Q4 (2026-04-26 p66):
--   Q1 reuso view_internal_analytics ao invés de nova action: SIM
--   Q2 Roberto Macêdo gain (chapter_board × liaison legítimo): SIM
--   Q3 defer log_pii_access_batch integration: SIM
--   Q4 timing: p66 mesmo
--
-- Privilege expansion safety check (verified pre-apply):
--   legacy_count = 9
--   v4_count = 10
--   would_gain = [Roberto Macêdo] (chapter_board × liaison engagement,
--                corrige gap V3 onde observer com governance role
--                institucional não tinha acesso)
--   would_lose = []

CREATE OR REPLACE FUNCTION public.admin_list_members(
  p_search text DEFAULT NULL::text,
  p_tier text DEFAULT NULL::text,
  p_tribe_id integer DEFAULT NULL::integer,
  p_status text DEFAULT 'active'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  -- V4 gate (replaces V3 operational_role check) — Opção B reuse view_internal_analytics
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
      'status_change_reason', m.status_change_reason
    ) ORDER BY m.name), '[]'::jsonb)
    FROM public.members m
    LEFT JOIN public.tribes tc ON tc.id = m.tribe_id
    WHERE (p_status = 'all'
        OR (p_status = 'active' AND m.member_status = 'active')
        OR (p_status = 'inactive' AND m.member_status = 'inactive')
        OR (p_status = 'observer' AND m.member_status = 'observer')
        OR (p_status = 'alumni' AND m.member_status = 'alumni'))
      AND (p_tier IS NULL OR m.operational_role = p_tier)
      AND (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
      AND (p_search IS NULL OR m.name ILIKE '%' || p_search || '%' OR m.email ILIKE '%' || p_search || '%')
  );
END;
$$;
COMMENT ON FUNCTION public.admin_list_members(text, text, integer, text) IS
  'Phase B'' V4 conversion (ADR-0031, p66): Opção B reuse view_internal_analytics gate via can_by_member. Was V3 (is_superadmin OR operational_role IN manager/deputy_manager/sponsor/chapter_liaison).';

NOTIFY pgrst, 'reload schema';
