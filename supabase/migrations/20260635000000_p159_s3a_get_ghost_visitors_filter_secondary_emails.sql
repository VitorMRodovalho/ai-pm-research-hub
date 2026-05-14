-- p159 S#3a (pré-ADR-0078): extend get_ghost_visitors para excluir auth.users cujo email
-- já está em members.secondary_emails (linking via alias).
--
-- PM ask 14/05: Herlon tem 2 auth.users — saguaho@gmail.com (Google, primary auth, last_sign_in
-- hoje) + herlon.sousa@pmice.org.br (email provider, last_sign_in 11/04, orphan da 1ª tentativa).
-- members.secondary_emails do Herlon JÁ tem herlon.sousa@pmice.org.br. Mas RPC só checava
-- auth_id direto, não secondary — orphan continuava em ghost_visitors list.
--
-- Fix: AND NOT EXISTS check sobre members.secondary_emails. Após apply, qualquer auth.users
-- orphan cujo email seja alias de algum member some da lista. Caso Herlon resolvido
-- imediatamente (sem mudar auth_id primary nem deletar nada).

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
  ORDER BY au.last_sign_in_at DESC NULLS LAST;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_ghost_visitors() TO authenticated;

NOTIFY pgrst, 'reload schema';
