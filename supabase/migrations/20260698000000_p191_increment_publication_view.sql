-- GAP-190.D part 2 — view tracking for /publications cards
--
-- Problem: public_publications.view_count column existed but no RPC ever
-- incremented it, so every card shows "👁 0 views" since publications were
-- created. Mirror pattern de increment_blog_view (single-arg SECDEF + GRANT
-- to anon/authenticated/service_role). Frontend chama on click "Ler →" /
-- "PDF" links (external_url + pdf_url).
--
-- Idempotent: UPDATE only — function call from anon or authenticated.
-- GRANT TO anon mantém parity com /publications acesso público.
--
-- Rollback: DROP FUNCTION public.increment_publication_view(uuid);

CREATE OR REPLACE FUNCTION public.increment_publication_view(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  UPDATE public.public_publications
  SET view_count = COALESCE(view_count, 0) + 1
  WHERE id = p_id AND is_published = true;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.increment_publication_view(uuid) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
