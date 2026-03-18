-- ============================================================
-- W-ADMIN Phase 3: admin_list_members RPC
-- Server-side filtered member listing for admin panel.
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_list_members(
  p_search text DEFAULT NULL,
  p_tier text DEFAULT NULL,
  p_tribe_id integer DEFAULT NULL,
  p_status text DEFAULT 'active'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'))
  ) THEN RAISE EXCEPTION 'Admin only'; END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', m.id,
      'full_name', m.full_name,
      'email', m.email,
      'photo_url', m.photo_url,
      'operational_role', m.operational_role,
      'designations', m.designations,
      'is_superadmin', m.is_superadmin,
      'is_active', m.is_active,
      'tribe_id', m.tribe_id,
      'tribe_name', tc.name,
      'chapter', m.chapter,
      'auth_id', m.auth_id,
      'last_seen_at', m.last_seen_at,
      'total_sessions', COALESCE(m.total_sessions, 0),
      'credly_username', m.credly_username
    ) ORDER BY m.full_name), '[]'::jsonb)
    FROM members m
    LEFT JOIN tribes tc ON tc.id = m.tribe_id
    WHERE
      (p_status = 'all' OR (p_status = 'active' AND m.is_active = true) OR (p_status = 'inactive' AND m.is_active = false))
      AND (p_tier IS NULL OR m.operational_role = p_tier)
      AND (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
      AND (p_search IS NULL OR m.full_name ILIKE '%' || p_search || '%' OR m.email ILIKE '%' || p_search || '%')
  );
END;
$$;
