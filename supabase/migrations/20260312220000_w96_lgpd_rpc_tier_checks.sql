-- ============================================================================
-- W96: LGPD Backend Enforcement — RPC tier checks
-- Adds tier validation to RPCs that return LGPD-sensitive data (emails,
-- phone numbers, addresses). Existing RLS on members table is already solid;
-- this migration focuses on SECURITY DEFINER RPCs that bypass RLS.
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. admin_get_member_details — full PII access (admin only)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_get_member_details(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller record;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM get_my_member_record();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF NOT (v_caller.is_superadmin = true
          OR v_caller.operational_role IN ('manager', 'deputy_manager')) THEN
    RAISE EXCEPTION 'Access denied: requires admin tier (LGPD-sensitive data)';
  END IF;

  SELECT jsonb_build_object(
    'id', m.id,
    'name', m.name,
    'email', m.email,
    'phone', m.phone,
    'photo_url', m.photo_url,
    'tribe_id', m.tribe_id,
    'operational_role', m.operational_role,
    'designations', m.designations,
    'is_superadmin', m.is_superadmin,
    'is_active', m.is_active,
    'cycle_active', m.cycle_active,
    'cycles', m.cycles,
    'created_at', m.created_at
  ) INTO v_result
  FROM members m WHERE m.id = p_member_id;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_member_details(uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. admin_list_members_with_pii — bulk PII access (admin only)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_list_members_with_pii(p_tribe_id int DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller record;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM get_my_member_record();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF NOT (v_caller.is_superadmin = true
          OR v_caller.operational_role IN ('manager', 'deputy_manager')) THEN
    RAISE EXCEPTION 'Access denied: requires admin tier (LGPD-sensitive data)';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', m.id,
    'name', m.name,
    'email', m.email,
    'phone', m.phone,
    'tribe_id', m.tribe_id,
    'operational_role', m.operational_role,
    'designations', m.designations,
    'is_active', m.is_active,
    'cycle_active', m.cycle_active
  ) ORDER BY m.name), '[]'::jsonb) INTO v_result
  FROM members m
  WHERE (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id);

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_list_members_with_pii(int) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Harden get_board_members — strip PII for non-admin callers
--    This RPC already exists and returns name + photo only (safe).
--    No changes needed; documenting compliance.
-- ═══════════════════════════════════════════════════════════════════════════

-- get_board_members returns: id, name, photo_url, operational_role
-- NO email, phone, or address → LGPD compliant as-is.

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. RLS on board_item_assignments — already enabled in W91
-- ═══════════════════════════════════════════════════════════════════════════

-- board_item_assignments: RLS enabled, SELECT for authenticated, ALL for authenticated
-- No PII stored in this table (only member_id references).

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. RLS on board_sla_config — already enabled in W90
-- ═══════════════════════════════════════════════════════════════════════════

-- board_sla_config: RLS enabled, SELECT for authenticated, ALL for admin only
-- No PII stored.

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. Ensure curation RPCs have proper tier checks (already done in W90)
-- ═══════════════════════════════════════════════════════════════════════════

-- submit_curation_review: checks curator/manager designation ✓
-- assign_curation_reviewer: checks curator/manager designation ✓
-- get_curation_dashboard: checks curator/manager designation ✓
-- get_item_curation_history: open to authenticated (no PII) ✓
