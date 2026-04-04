-- Ghost visitors RPC — lists auth.users without member records
-- Admin-only, LGPD-safe (data already consented via OAuth login)

BEGIN;

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
    (SELECT m.name FROM public.members m WHERE lower(m.email) = lower(au.email) LIMIT 1)::text
  FROM auth.users au
  LEFT JOIN public.members m2 ON m2.auth_id = au.id
  WHERE m2.id IS NULL
  ORDER BY au.last_sign_in_at DESC NULLS LAST;
END;
$$;

GRANT EXECUTE ON FUNCTION get_ghost_visitors TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
