-- GC-102: Wrapper RPC to avoid direct query on onboarding_progress (RLS deny-all)
-- Frontend calls this instead of .from('onboarding_progress')

DROP FUNCTION IF EXISTS get_my_onboarding();
CREATE FUNCTION get_my_onboarding()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_member_id uuid;
  v_app_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RETURN NULL; END IF;

  SELECT application_id INTO v_app_id
  FROM onboarding_progress
  WHERE member_id = v_member_id
  LIMIT 1;

  IF v_app_id IS NULL THEN RETURN NULL; END IF;

  RETURN get_onboarding_status(v_app_id);
END;
$$;

NOTIFY pgrst, 'reload schema';
