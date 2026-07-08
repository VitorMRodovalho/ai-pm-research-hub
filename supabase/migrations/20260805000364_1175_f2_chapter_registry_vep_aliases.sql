-- #1175 F2: chapter-name resolution becomes chapter_registry-driven (Pattern 47 / smart-code).
--
-- The VEP membership snapshot carries chapter names that do NOT all follow the
-- "<State>, Brazil Chapter" convention the worker's parseBrChapterCode hardcodes
-- (cloudflare-workers/pmi-vep-sync/src/mapper.ts): the live counter-example is
-- "Amazônia Chapter" (registry state "Amazonas"), which resolved to null, so the member's
-- member_chapter_affiliations stayed empty and the profile "Capítulo de Entrada" card
-- claimed "não encontramos suas filiações" despite the evidence sitting in
-- selection_applications.pmi_memberships (index case: #1175, audited live 2026-07-08).
--
-- This migration makes chapter_registry the SSOT for the mapping:
--   1. chapter_registry.vep_name_aliases — exact (case-insensitive) VEP chapterName strings
--      that map to the chapter beyond the canonical "<State>, Brazil Chapter" pattern.
--      Seeded for AM in both spellings (no unaccent extension in this DB).
--   2. resolve_br_chapter_code(text) — the SQL resolver used by the #1175 backfill and any
--      future SQL-side parsing. The worker builds the equivalent matcher in TS from the
--      same registry rows (cloudflare-workers/pmi-vep-sync/src/mapper.ts
--      buildBrChapterMatcher), so both sides derive from the one SSOT.
--
-- Non-BR names ("PMI Global", "Washington, DC Chapter", "Angola Chapter") intentionally
-- resolve to NULL: member_chapter_affiliations FKs chapter_registry, which is BR-only by
-- design (ADR-0104).

ALTER TABLE public.chapter_registry
  ADD COLUMN IF NOT EXISTS vep_name_aliases text[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN public.chapter_registry.vep_name_aliases IS
  '#1175 F2: exact VEP pmi_memberships chapterName strings (case-insensitive) that map to this chapter when they do not follow the "<State>, Brazil Chapter" convention. Ex.: AM = {"Amazônia Chapter","Amazonia Chapter"}. Consumed by resolve_br_chapter_code() and by the pmi-vep-sync worker matcher.';

UPDATE public.chapter_registry
   SET vep_name_aliases = ARRAY['Amazônia Chapter', 'Amazonia Chapter'],
       updated_at = now()
 WHERE chapter_code = 'AM';

-- Resolver: alias exact match wins; otherwise the canonical "<State>, Brazil Chapter"
-- pattern matched against the registry's own state names (no hardcoded state list).
-- Returns the bare registry code ("AM", "MG", ...) or NULL for non-BR / unknown names.
CREATE OR REPLACE FUNCTION public.resolve_br_chapter_code(p_name text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH n AS (SELECT lower(trim(coalesce(p_name, ''))) AS name)
  SELECT cr.chapter_code
  FROM public.chapter_registry cr, n
  WHERE cr.is_active = true
    AND cr.country = 'BR'
    AND n.name <> ''
    AND (
      EXISTS (SELECT 1 FROM unnest(cr.vep_name_aliases) a WHERE lower(trim(a)) = n.name)
      OR (n.name ~ ',\s*brazil chapter$' AND position(lower(cr.state) IN n.name) > 0)
    )
  ORDER BY
    (EXISTS (SELECT 1 FROM unnest(cr.vep_name_aliases) a WHERE lower(trim(a)) = n.name)) DESC
  LIMIT 1
$function$;

COMMENT ON FUNCTION public.resolve_br_chapter_code(text) IS
  '#1175 F2: chapter_registry-driven resolution of a VEP membership chapterName to the registry code. Alias match first, then "<State>, Brazil Chapter". NULL = non-BR or unknown (intentionally untracked, ADR-0104).';

GRANT EXECUTE ON FUNCTION public.resolve_br_chapter_code(text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
