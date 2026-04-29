-- p83 Sprint 1B — get_active_chapters() RPC + public grant
-- SECURITY DEFINER pra expor chapter list pra anon/ghost (homepage, team section, footer).
-- LGPD-safe: cnpj NÃO é retornado (legal name + state já são públicos via comunicação institucional).
-- Pattern: matches CLAUDE.md rule #6 "Public data via SECURITY DEFINER RPCs only".
-- Rollback: DROP FUNCTION public.get_active_chapters();

CREATE OR REPLACE FUNCTION public.get_active_chapters()
RETURNS TABLE(
  chapter_code text,
  display_code text,
  legal_name text,
  state text,
  country text,
  logo_url text,
  is_contracting boolean,
  display_order integer
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT
    cr.chapter_code,
    'PMI-' || cr.chapter_code AS display_code,
    cr.legal_name,
    cr.state,
    cr.country,
    cr.logo_url,
    COALESCE(cr.is_contracting_chapter, false) AS is_contracting,
    cr.display_order
  FROM public.chapter_registry cr
  WHERE cr.is_active = true
  ORDER BY
    cr.display_order NULLS LAST,
    cr.chapter_code;
$$;

REVOKE ALL ON FUNCTION public.get_active_chapters() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_chapters() TO authenticated, anon;

COMMENT ON FUNCTION public.get_active_chapters() IS
'p83 — Lista chapters ativos pra exposure pública (homepage/footer/team).
Retorna chapter_code (canonical), display_code (PMI-XX format), legal_name, state, country, logo_url, is_contracting, display_order.
Não expõe cnpj (LGPD/Legal). SECURITY DEFINER pra anon/ghost. Cache 1h recomendado no caller.';

NOTIFY pgrst, 'reload schema';
