-- p159 S#3b: extend get_ghost_visitors filter — também excluir auth.users cujo email
-- match members.email (primary), não só secondary_emails.
--
-- PM 14/05 audit: 4 ghosts (Carlos magno@innove.se · Paulo paulorobertodecamargofilho@gmail.com
-- · Paulo paulo-junior@outlook.com · Italo italo.sn@hotmail.com). Os 2 últimos eram
-- duplicates do email primary dos members correspondentes (Supabase OAuth duplicates per
-- provider). Filter anterior (S#3a) só checava secondary_emails — primary email match
-- ainda deixava dup como ghost.
--
-- get_member_by_auth RPC já resolve via email match (auto-claim auth_id quando user faz
-- login no provider duplicado). Ghost RPC agora reflete isso visualmente.

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
       WHERE lower(au.email) = ANY(SELECT lower(unnest(coalesce(m.secondary_emails, '{}'::text[]))))
       LIMIT 1),
      (SELECT m.name FROM public.members m
       WHERE lower(m.name) LIKE '%' || lower(split_part(split_part(au.email, '@', 1), '.', 1)) || '%'
         AND length(split_part(split_part(au.email, '@', 1), '.', 1)) >= 4
       LIMIT 1)
    )::text
  FROM auth.users au
  LEFT JOIN public.members m2 ON m2.auth_id = au.id
  WHERE m2.id IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.members m3
      WHERE lower(au.email) = ANY(SELECT lower(unnest(coalesce(m3.secondary_emails, '{}'::text[]))))
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.members m4
      WHERE lower(m4.email) = lower(au.email)
    )
  ORDER BY au.last_sign_in_at DESC NULLS LAST;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_ghost_visitors() TO authenticated;

NOTIFY pgrst, 'reload schema';
