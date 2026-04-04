-- Auto-link ghost to member: resolves ghost logins by matching email
-- Improved ghost visitors RPC with fuzzy name matching
-- Supports identity linking flow in profile page

BEGIN;

CREATE OR REPLACE FUNCTION try_auto_link_ghost()
RETURNS SETOF members
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  v_member_id uuid;
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;

  -- Already linked? Return the member
  IF EXISTS (SELECT 1 FROM members WHERE auth_id = v_uid) THEN
    RETURN QUERY SELECT * FROM members WHERE auth_id = v_uid LIMIT 1;
    RETURN;
  END IF;

  -- Get the email from auth.users
  SELECT email INTO v_email FROM auth.users WHERE id = v_uid;
  IF v_email IS NULL THEN RETURN; END IF;

  -- Try to find a member with matching email that has NO auth_id (never logged in)
  SELECT id INTO v_member_id FROM members
  WHERE lower(email) = lower(v_email) AND auth_id IS NULL
  LIMIT 1;

  IF v_member_id IS NOT NULL THEN
    UPDATE members SET auth_id = v_uid WHERE id = v_member_id;
    RETURN QUERY SELECT * FROM members WHERE id = v_member_id;
    RETURN;
  END IF;

  -- Try member with matching email that HAS a DIFFERENT auth_id
  -- Safe because OAuth email is verified by the provider
  SELECT id INTO v_member_id FROM members
  WHERE lower(email) = lower(v_email) AND auth_id IS NOT NULL AND auth_id != v_uid
  LIMIT 1;

  IF v_member_id IS NOT NULL THEN
    UPDATE members SET auth_id = v_uid WHERE id = v_member_id;
    RETURN QUERY SELECT * FROM members WHERE id = v_member_id;
    RETURN;
  END IF;

  -- No match found — genuine ghost
  RETURN;
END;
$$;

GRANT EXECUTE ON FUNCTION try_auto_link_ghost TO authenticated;

-- Improved ghost visitors RPC with fuzzy name match
CREATE OR REPLACE FUNCTION get_ghost_visitors()
RETURNS TABLE(
  auth_id uuid, email text, provider text,
  created_at timestamptz, last_sign_in_at timestamptz,
  possible_member_name text
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'auth', 'pg_temp' AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.members
    WHERE public.members.auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'))
  ) THEN RAISE EXCEPTION 'Admin only'; END IF;

  RETURN QUERY
  SELECT
    au.id,
    au.email::text,
    (au.raw_app_meta_data->>'provider')::text,
    au.created_at,
    au.last_sign_in_at,
    COALESCE(
      (SELECT m.name FROM public.members m WHERE lower(m.email) = lower(au.email) LIMIT 1),
      (SELECT m.name FROM public.members m
       WHERE lower(m.name) LIKE '%' || lower(split_part(split_part(au.email, '@', 1), '.', 1)) || '%'
         AND length(split_part(split_part(au.email, '@', 1), '.', 1)) >= 4
       LIMIT 1)
    )::text
  FROM auth.users au
  LEFT JOIN public.members m2 ON m2.auth_id = au.id
  WHERE m2.id IS NULL
  ORDER BY au.last_sign_in_at DESC NULLS LAST;
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;
