-- PR-A template: admin_update_member v2 contract
-- Goal: remove frontend requirement to send p_role/p_roles.
-- Apply in staging first, validate, then production.

-- 1) Keep compatibility helpers while transition exists.
-- CREATE OR REPLACE FUNCTION compute_legacy_role(op_role text, desigs text[]) ...
-- CREATE OR REPLACE FUNCTION compute_legacy_roles(op_role text, desigs text[]) ...

-- 2) Update admin_update_member to accept v2 params.
-- IMPORTANT: adapt body to your current function implementation.
-- This template keeps p_role/p_roles optional for temporary backward compatibility.

/*
CREATE OR REPLACE FUNCTION public.admin_update_member(
  p_member_id uuid,
  p_name text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_operational_role text DEFAULT NULL,
  p_designations text[] DEFAULT NULL,
  p_chapter text DEFAULT NULL,
  p_tribe_id integer DEFAULT NULL,
  p_pmi_id text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_linkedin_url text DEFAULT NULL,
  p_current_cycle_active boolean DEFAULT NULL,
  p_role text DEFAULT NULL,   -- legacy fallback only
  p_roles text[] DEFAULT NULL -- legacy fallback only
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_operational_role text;
  v_designations text[];
BEGIN
  v_operational_role := COALESCE(p_operational_role, p_role, 'guest');
  v_designations := COALESCE(p_designations, p_roles, ARRAY[]::text[]);

  -- TODO: keep your existing authorization checks here.
  -- TODO: keep your existing uniqueness checks here.
  -- TODO: keep your existing member update logic here.
  -- Example:
  -- UPDATE public.members
  -- SET
  --   name = COALESCE(p_name, name),
  --   email = COALESCE(p_email, email),
  --   operational_role = v_operational_role,
  --   designations = v_designations,
  --   chapter = COALESCE(p_chapter, chapter),
  --   tribe_id = COALESCE(p_tribe_id, tribe_id),
  --   pmi_id = COALESCE(p_pmi_id, pmi_id),
  --   phone = COALESCE(p_phone, phone),
  --   linkedin_url = COALESCE(p_linkedin_url, linkedin_url),
  --   current_cycle_active = COALESCE(p_current_cycle_active, current_cycle_active),
  --   updated_at = now()
  -- WHERE id = p_member_id;

  RETURN jsonb_build_object('success', true);
END;
$$;
*/

-- 3) Validation queries (run after deploy)
-- SELECT proname, proargnames FROM pg_proc WHERE proname = 'admin_update_member';
-- SELECT id, operational_role, designations FROM public.members LIMIT 20;
