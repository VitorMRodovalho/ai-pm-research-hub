-- ═══════════════════════════════════════════════════════════════
-- Migration: admin_update_member full overload for member/[id] page
-- The basic overload (uuid, text, text[], text, boolean) covers admin/index.
-- This overload covers admin/member/[id] with name, email, tribe, pmi, phone, linkedin.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_update_member(
  p_member_id uuid,
  p_name text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_operational_role text DEFAULT NULL,
  p_designations text[] DEFAULT NULL,
  p_chapter text DEFAULT NULL,
  p_tribe_id int DEFAULT NULL,
  p_pmi_id text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_linkedin_url text DEFAULT NULL,
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
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND OR v_caller.is_superadmin IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Member not found');
  END IF;

  UPDATE public.members SET
    name = COALESCE(p_name, name),
    email = COALESCE(p_email, email),
    operational_role = COALESCE(p_operational_role, operational_role),
    designations = COALESCE(p_designations, designations),
    chapter = COALESCE(p_chapter, chapter),
    tribe_id = COALESCE(p_tribe_id, tribe_id),
    pmi_id = COALESCE(p_pmi_id, pmi_id),
    phone = COALESCE(p_phone, phone),
    linkedin_url = COALESCE(p_linkedin_url, linkedin_url),
    current_cycle_active = COALESCE(p_current_cycle_active, current_cycle_active),
    updated_at = now()
  WHERE id = p_member_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_update_member(uuid, text, text, text, text[], text, int, text, text, text, boolean) TO authenticated;
