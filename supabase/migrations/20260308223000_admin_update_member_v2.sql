-- ═══════════════════════════════════════════════════════════════
-- Migration: admin_update_member v2 overload
-- Why: current RPC only accepts (p_role, p_roles) legacy params.
--   Frontend sends (p_operational_role, p_designations) first,
--   gets "function not found", then falls back to legacy.
--   With the sync trigger from previous migration, the legacy path
--   would have role overwritten by trigger. Creating v2 fixes this.
-- ═══════════════════════════════════════════════════════════════

-- Drop legacy signature (same type signature uuid, text, text[], text, boolean)
DROP FUNCTION IF EXISTS public.admin_update_member(uuid, text, text[], text, boolean);

-- v2: accepts operational_role + designations directly
CREATE OR REPLACE FUNCTION public.admin_update_member(
  p_member_id uuid,
  p_operational_role text DEFAULT NULL,
  p_designations text[] DEFAULT NULL,
  p_chapter text DEFAULT NULL,
  p_current_cycle_active boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_member record;
BEGIN
  -- Auth check: caller must be superadmin
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND OR v_caller.is_superadmin IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Target member must exist
  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Member not found');
  END IF;

  -- Update fields that were provided (non-null)
  UPDATE public.members SET
    operational_role = COALESCE(p_operational_role, operational_role),
    designations = COALESCE(p_designations, designations),
    chapter = COALESCE(p_chapter, chapter),
    current_cycle_active = COALESCE(p_current_cycle_active, current_cycle_active),
    updated_at = now()
  WHERE id = p_member_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- Grant execute to authenticated users (RLS + function body handles auth)
GRANT EXECUTE ON FUNCTION public.admin_update_member(uuid, text, text[], text, boolean) TO authenticated;
