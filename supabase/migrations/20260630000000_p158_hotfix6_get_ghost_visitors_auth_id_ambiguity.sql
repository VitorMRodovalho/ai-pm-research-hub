-- p158 hotfix #6: fix auth_id ambiguity in get_ghost_visitors
--
-- PM live test 2026-05-14: /admin/adoption shows console error
--   POST .../get_ghost_visitors 400 (Bad Request)
--   column reference "auth_id" is ambiguous — could refer to PL/pgSQL variable or table column
--
-- Root cause: RETURN TABLE declares auth_id as output column AND the body's JOIN references
-- members.auth_id. PostgreSQL refuses to disambiguate (same gotcha as
-- feedback_postgres_returns_table_id_ambiguity.md p87).
--
-- Fix: prefix all RETURN TABLE cols with 'out_' (out_auth_id, out_email, etc). Frontend update
-- required to read new field names. Behavior identical.

DROP FUNCTION IF EXISTS public.get_ghost_visitors();

CREATE OR REPLACE FUNCTION public.get_ghost_visitors()
RETURNS TABLE(
  out_auth_id              uuid,
  out_email                text,
  out_provider             text,
  out_created_at           timestamptz,
  out_last_sign_in_at      timestamptz,
  out_possible_member_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

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
$function$;

GRANT EXECUTE ON FUNCTION public.get_ghost_visitors() TO authenticated;

NOTIFY pgrst, 'reload schema';
