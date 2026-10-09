-- #2613 — Biblioteca de publicações: página permanente por obra, coleções e citação pronta.
--
-- (1) public_publications ganha slug, first_published_at, license, collection_id e collection_position.
--     O slug nasce na primeira publicação (do título, ou o que vier no próprio UPDATE que publica) e
--     NÃO muda depois: o trigger recusa a troca quando first_published_at já existe. Assim a URL
--     /publications/<slug> é estável para citação, QR code e DOI apontando de volta.
--     Slugs reservados: os caminhos estáticos irmãos da rota dinâmica (submissions, collections, feed).
--
-- (2) publication_collections: o toolkit que agrupa capítulos, em ordem. Não confundir com
--     publication_series, que é série EDITORIAL (blog, newsletter) com cadência e voz editorial.
--     RLS ligada sem policy: a leitura pública sai só pelas RPCs SECURITY DEFINER abaixo.
--
-- (3) Portão da ADR-0105 em public_publications. Hoje anon lê a linha publicada direto pela policy
--     permissiva "pub_read_published", sem o portão de iniciativa confidencial, e a RPC
--     get_public_publications também não o aplica (estava no allowlist do #785 como latente:
--     0 publicações ligadas a iniciativa confidencial, medido em 09/10/2026). Entra uma policy
--     RESTRICTIVE de SELECT com rls_can_see_initiative(initiative_id) e rls_can_see_item(board_item_id),
--     e o mesmo predicado nas três leitoras.
--
-- (4) Leitoras públicas: get_public_publication(slug) e get_public_publication_collection(slug),
--     mais get_public_publications com slug, licença e coleção. O corpo de get_public_publications
--     parte do vivo de 09/10/2026 (md5 5c28efa871b6aad7ef17cec583903521, idêntico à captura
--     20260427200000) e mantém o search_path que 20260428150000 lhe deu.
--
-- (5) Dados: a primeira obra (Capítulo 6 do toolkit da Tribo 13) recebe slug, licença e PDF, e o
--     toolkit vira a primeira coleção. Licença e PDF lidos na API pública do figshare em 09/10/2026
--     (license "CC BY 4.0"; um arquivo PDF).

-- ── (2) coleções ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.publication_collections (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug               text NOT NULL,
  title              text NOT NULL CHECK (length(btrim(title)) > 0),
  description        text,
  collection_type    text NOT NULL DEFAULT 'toolkit'
                       CHECK (collection_type IN ('toolkit','book','proceedings','series')),
  initiative_id      uuid REFERENCES public.initiatives(id) ON DELETE SET NULL,
  doi                text,
  license            text CHECK (license IS NULL OR license ~ '^[A-Za-z0-9.+-]+$'),
  is_published       boolean NOT NULL DEFAULT false,
  first_published_at timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT publication_collections_slug_key UNIQUE (slug),
  CONSTRAINT publication_collections_slug_format CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$')
);
CREATE INDEX IF NOT EXISTS idx_publication_collections_initiative ON public.publication_collections (initiative_id);

ALTER TABLE public.publication_collections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.publication_collections FROM PUBLIC, anon, authenticated;

COMMENT ON TABLE public.publication_collections IS
  '#2613: coleção de obras publicadas (toolkit com capítulos, livro, anais). Leitura pública só por get_public_publication_collection. Não é publication_series (série editorial).';

-- ── (1) colunas novas em public_publications ──────────────────────────────────
ALTER TABLE public.public_publications
  ADD COLUMN IF NOT EXISTS slug                text,
  ADD COLUMN IF NOT EXISTS first_published_at  timestamptz,
  ADD COLUMN IF NOT EXISTS license             text,
  ADD COLUMN IF NOT EXISTS collection_id       uuid REFERENCES public.publication_collections(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS collection_position integer;

ALTER TABLE public.public_publications DROP CONSTRAINT IF EXISTS public_publications_slug_key;
ALTER TABLE public.public_publications ADD CONSTRAINT public_publications_slug_key UNIQUE (slug);
ALTER TABLE public.public_publications DROP CONSTRAINT IF EXISTS public_publications_slug_format;
ALTER TABLE public.public_publications ADD CONSTRAINT public_publications_slug_format
  CHECK (slug IS NULL OR (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND slug NOT IN ('submissions','collections','feed')));
ALTER TABLE public.public_publications DROP CONSTRAINT IF EXISTS public_publications_license_format;
ALTER TABLE public.public_publications ADD CONSTRAINT public_publications_license_format
  CHECK (license IS NULL OR license ~ '^[A-Za-z0-9.+-]+$');
ALTER TABLE public.public_publications DROP CONSTRAINT IF EXISTS public_publications_collection_position;
ALTER TABLE public.public_publications ADD CONSTRAINT public_publications_collection_position
  CHECK (collection_position IS NULL OR (collection_position > 0 AND collection_id IS NOT NULL));
CREATE INDEX IF NOT EXISTS idx_public_publications_collection
  ON public.public_publications (collection_id, collection_position);

COMMENT ON COLUMN public.public_publications.slug IS
  '#2613: URL permanente /publications/<slug>. Nasce na primeira publicação e não muda depois (trigger _public_publications_slug_guard).';
COMMENT ON COLUMN public.public_publications.license IS
  '#2613: identificador SPDX da licença da obra (ex.: CC-BY-4.0).';

-- slug a partir do título: minúsculas, sem acento, só [a-z0-9-], até 80 caracteres
CREATE OR REPLACE FUNCTION public._publication_slugify(p_text text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  SELECT btrim(left(btrim(regexp_replace(lower(translate(coalesce(p_text, ''),
    'ÁÀÂÃÄÅáàâãäåÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇçÑñ',
    'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNn')),
    '[^a-z0-9]+', '-', 'g'), '-'), 80), '-')
$function$;

-- SECURITY DEFINER para a checagem de unicidade enxergar também linhas que o chamador não vê
-- (sem isso, um slug de obra confidencial colidiria em erro de UNIQUE em vez de ganhar sufixo).
CREATE OR REPLACE FUNCTION public._public_publications_slug_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_base text;
  v_try  text;
  v_n    integer := 1;
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.first_published_at IS NOT NULL THEN
    IF NEW.slug IS DISTINCT FROM OLD.slug THEN
      RAISE EXCEPTION 'slug "%" is permanent after first publication', OLD.slug
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.first_published_at := OLD.first_published_at;
  END IF;

  IF NEW.is_published AND NEW.slug IS NULL THEN
    v_base := public._publication_slugify(NEW.title);
    IF v_base = '' THEN v_base := 'publicacao'; END IF;
    v_try := v_base;
    WHILE v_try IN ('submissions','collections','feed')
       OR EXISTS (SELECT 1 FROM public.public_publications p WHERE p.slug = v_try AND p.id <> NEW.id) LOOP
      v_n := v_n + 1;
      v_try := v_base || '-' || v_n;
    END LOOP;
    NEW.slug := v_try;
  END IF;

  IF NEW.is_published AND NEW.first_published_at IS NULL THEN
    NEW.first_published_at := now();
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_public_publications_slug_guard ON public.public_publications;
CREATE TRIGGER trg_public_publications_slug_guard
  BEFORE INSERT OR UPDATE ON public.public_publications
  FOR EACH ROW EXECUTE FUNCTION public._public_publications_slug_guard();

CREATE OR REPLACE FUNCTION public._publication_collections_slug_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.first_published_at IS NOT NULL THEN
    IF NEW.slug IS DISTINCT FROM OLD.slug THEN
      RAISE EXCEPTION 'collection slug "%" is permanent after first publication', OLD.slug
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.first_published_at := OLD.first_published_at;
  END IF;
  IF NEW.is_published AND NEW.first_published_at IS NULL THEN
    NEW.first_published_at := now();
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_publication_collections_slug_guard ON public.publication_collections;
CREATE TRIGGER trg_publication_collections_slug_guard
  BEFORE INSERT OR UPDATE ON public.publication_collections
  FOR EACH ROW EXECUTE FUNCTION public._publication_collections_slug_guard();

REVOKE ALL ON FUNCTION public._public_publications_slug_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._publication_collections_slug_guard() FROM PUBLIC, anon, authenticated;

-- ── (3) portão da ADR-0105 na tabela ──────────────────────────────────────────
DROP POLICY IF EXISTS public_publications_confidential_gate ON public.public_publications;
CREATE POLICY public_publications_confidential_gate ON public.public_publications AS RESTRICTIVE FOR SELECT
  USING (public.rls_can_see_initiative(initiative_id) AND public.rls_can_see_item(board_item_id));

-- ── (4) leitoras públicas ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_public_publications(
  p_type text DEFAULT NULL,
  p_tribe_id integer DEFAULT NULL,
  p_cycle text DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_limit integer DEFAULT 50
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_result jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(r) ORDER BY r.is_featured DESC, r.publication_date DESC NULLS LAST)
  INTO v_result FROM (
    SELECT pp.id, pp.slug, pp.title, pp.abstract, pp.authors, pp.publication_date, pp.publication_type,
      pp.external_url, pp.external_platform, pp.doi, pp.keywords,
      i.legacy_tribe_id AS tribe_id, pp.cycle_code,
      pp.language, pp.citation_count, pp.view_count, pp.thumbnail_url, pp.pdf_url, pp.is_featured,
      pp.license, pc.slug AS collection_slug, pc.title AS collection_title, pp.collection_position
    FROM public.public_publications pp
    LEFT JOIN public.initiatives i ON i.id = pp.initiative_id
    LEFT JOIN public.publication_collections pc ON pc.id = pp.collection_id AND pc.is_published = true
    WHERE pp.is_published = true
      AND public.rls_can_see_initiative(pp.initiative_id)
      AND public.rls_can_see_item(pp.board_item_id)
      AND (p_type IS NULL OR pp.publication_type = p_type)
      AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
      AND (p_cycle IS NULL OR pp.cycle_code = p_cycle)
      AND (p_search IS NULL OR pp.title ILIKE '%' || p_search || '%'
        OR pp.abstract ILIKE '%' || p_search || '%'
        OR EXISTS (SELECT 1 FROM unnest(pp.keywords) k WHERE k ILIKE '%' || p_search || '%'))
    ORDER BY pp.is_featured DESC, pp.publication_date DESC NULLS LAST LIMIT p_limit
  ) r;
  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_publication(p_slug text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'id', pp.id,
    'slug', pp.slug,
    'title', pp.title,
    'abstract', pp.abstract,
    'authors', to_jsonb(pp.authors),
    'author_profiles', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('name', pm.name, 'linkedin_url', pm.linkedin_url) ORDER BY a.ord)
      FROM unnest(pp.author_member_ids) WITH ORDINALITY AS a(member_id, ord)
      JOIN public.public_members pm ON pm.id = a.member_id
    ), '[]'::jsonb),
    'publication_date', pp.publication_date,
    'first_published_at', pp.first_published_at,
    'updated_at', pp.updated_at,
    'publication_type', pp.publication_type,
    'external_url', pp.external_url,
    'external_platform', pp.external_platform,
    'doi', pp.doi,
    'pdf_url', pp.pdf_url,
    'thumbnail_url', pp.thumbnail_url,
    'keywords', to_jsonb(pp.keywords),
    'language', pp.language,
    'cycle_code', pp.cycle_code,
    'license', pp.license,
    'view_count', pp.view_count,
    'initiative', CASE WHEN i.id IS NULL THEN NULL ELSE jsonb_build_object(
      'title', i.title, 'kind', i.kind, 'tribe_id', i.legacy_tribe_id) END,
    'collection', CASE WHEN pc.id IS NULL THEN NULL ELSE jsonb_build_object(
      'slug', pc.slug, 'title', pc.title, 'collection_type', pc.collection_type,
      'position', pp.collection_position,
      'items', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('slug', s.slug, 'title', s.title, 'position', s.collection_position)
                         ORDER BY s.collection_position NULLS LAST, s.title)
        FROM public.public_publications s
        WHERE s.collection_id = pc.id AND s.is_published = true
          AND public.rls_can_see_initiative(s.initiative_id)
          AND public.rls_can_see_item(s.board_item_id)
      ), '[]'::jsonb)) END
  )
  FROM public.public_publications pp
  LEFT JOIN public.initiatives i ON i.id = pp.initiative_id
  LEFT JOIN public.publication_collections pc ON pc.id = pp.collection_id AND pc.is_published = true
    AND public.rls_can_see_initiative(pc.initiative_id)
  WHERE pp.slug = p_slug
    AND pp.is_published = true
    AND public.rls_can_see_initiative(pp.initiative_id)
    AND public.rls_can_see_item(pp.board_item_id)
$function$;

CREATE OR REPLACE FUNCTION public.get_public_publication_collection(p_slug text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'slug', pc.slug,
    'title', pc.title,
    'description', pc.description,
    'collection_type', pc.collection_type,
    'doi', pc.doi,
    'license', pc.license,
    'first_published_at', pc.first_published_at,
    'initiative', CASE WHEN i.id IS NULL THEN NULL ELSE jsonb_build_object(
      'title', i.title, 'kind', i.kind, 'tribe_id', i.legacy_tribe_id) END,
    'items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'slug', s.slug, 'title', s.title, 'position', s.collection_position,
               'authors', to_jsonb(s.authors), 'publication_date', s.publication_date,
               'doi', s.doi, 'abstract', s.abstract)
             ORDER BY s.collection_position NULLS LAST, s.title)
      FROM public.public_publications s
      WHERE s.collection_id = pc.id AND s.is_published = true
        AND public.rls_can_see_initiative(s.initiative_id)
        AND public.rls_can_see_item(s.board_item_id)
    ), '[]'::jsonb)
  )
  FROM public.publication_collections pc
  LEFT JOIN public.initiatives i ON i.id = pc.initiative_id
  WHERE pc.slug = p_slug
    AND pc.is_published = true
    AND public.rls_can_see_initiative(pc.initiative_id)
$function$;

REVOKE ALL ON FUNCTION public.get_public_publication(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_public_publication_collection(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_publication(text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_public_publication_collection(text) TO anon, authenticated, service_role;

-- ── (5) dados: primeira obra e primeira coleção ───────────────────────────────
INSERT INTO public.publication_collections (slug, title, description, collection_type, initiative_id, license, is_published)
SELECT 'qualidade-de-dados-em-projetos-de-ia',
       'Qualidade de Dados em Projetos de IA',
       'Toolkit da Tribo "Dados em Projetos de IA" do Núcleo IA & GP, publicado capítulo a capítulo.',
       'toolkit', i.id, 'CC-BY-4.0', true
FROM public.initiatives i
WHERE i.id = '7502b6c2-5c8c-472c-bab0-09f757b98ea4'
ON CONFLICT (slug) DO NOTHING;

UPDATE public.public_publications pp
SET slug = 'capitulo-6-gestao-de-linhagem-e-rastreabilidade-de-dados-em-projetos-de-ia',
    first_published_at = COALESCE(pp.first_published_at, pp.updated_at),
    license = 'CC-BY-4.0',
    pdf_url = COALESCE(pp.pdf_url, 'https://ndownloader.figshare.com/files/69803151'),
    collection_id = (SELECT pc.id FROM public.publication_collections pc
                     WHERE pc.slug = 'qualidade-de-dados-em-projetos-de-ia'),
    collection_position = 6
WHERE pp.id = '353929b3-ab02-4aea-a8fa-d771341ba497'
  AND pp.slug IS NULL;

-- Depois do backfill: a obra já publicada só tem slug a partir do UPDATE acima.
ALTER TABLE public.public_publications DROP CONSTRAINT IF EXISTS public_publications_published_has_slug;
ALTER TABLE public.public_publications ADD CONSTRAINT public_publications_published_has_slug
  CHECK (NOT is_published OR slug IS NOT NULL);

-- ── pós-condição: aborta a migration inteira se algo saiu errado ─────────────
DO $postcondition$
DECLARE
  v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.public_publications WHERE is_published AND slug IS NULL;
  IF v_n <> 0 THEN RAISE EXCEPTION '#2613: % obra(s) publicada(s) sem slug', v_n; END IF;

  SELECT count(*) INTO v_n FROM pg_catalog.pg_policies
  WHERE schemaname = 'public' AND tablename = 'public_publications'
    AND policyname = 'public_publications_confidential_gate' AND permissive = 'RESTRICTIVE'
    AND cmd = 'SELECT' AND qual ILIKE '%rls_can_see_initiative%';
  IF v_n <> 1 THEN RAISE EXCEPTION '#2613: policy RESTRICTIVE do portão confidencial ausente'; END IF;

  SELECT count(*) INTO v_n FROM pg_catalog.pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'get_public_publications'
    AND p.prosecdef AND p.proconfig @> ARRAY['search_path=public, pg_temp'];
  IF v_n <> 1 THEN RAISE EXCEPTION '#2613: get_public_publications perdeu SECURITY DEFINER ou search_path'; END IF;

  IF public._publication_slugify('Capítulo 6 — Gestão de Linhagem') <> 'capitulo-6-gestao-de-linhagem' THEN
    RAISE EXCEPTION '#2613: _publication_slugify devolveu %', public._publication_slugify('Capítulo 6 — Gestão de Linhagem');
  END IF;
END
$postcondition$;

NOTIFY pgrst, 'reload schema';
