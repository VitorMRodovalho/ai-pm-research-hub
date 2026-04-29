-- p83 Sprint 1A — chapter_registry schema extension
-- Adiciona colunas necessárias pra tornar listagem de chapters data-driven (frontend dynamic).
-- Backfill 5 chapters atuais (CE/DF/GO/MG/RS) com logo_url + display_order.
-- Não INSERTa novos chapters; aguarda lista oficial Ivan Lourenço (PMI-GO Pres) antes da expansão 5→15.
-- Rollback: ALTER TABLE chapter_registry DROP COLUMN logo_url, DROP COLUMN display_order, DROP COLUMN country; DROP INDEX idx_chapter_registry_active_order;

ALTER TABLE public.chapter_registry
  ADD COLUMN IF NOT EXISTS country text NOT NULL DEFAULT 'BR',
  ADD COLUMN IF NOT EXISTS display_order integer,
  ADD COLUMN IF NOT EXISTS logo_url text;

COMMENT ON COLUMN public.chapter_registry.country IS 'ISO 3166-1 alpha-2 country code. BR atual; abre caminho pra LATAM expansion no futuro.';
COMMENT ON COLUMN public.chapter_registry.display_order IS 'Ordem em que chapters aparecem em listas UI. Menor = primeiro. NULL = ordenado alfabeticamente como fallback.';
COMMENT ON COLUMN public.chapter_registry.logo_url IS 'Caminho público do logo (PNG/JPG/SVG). Servido via /assets/logos/. Pode apontar pra CDN externa se necessário.';

UPDATE public.chapter_registry SET logo_url = '/assets/logos/pmigo.png', display_order = 1 WHERE chapter_code = 'GO';
UPDATE public.chapter_registry SET logo_url = '/assets/logos/pmice.jpg', display_order = 2 WHERE chapter_code = 'CE';
UPDATE public.chapter_registry SET logo_url = '/assets/logos/pmidf.png', display_order = 3 WHERE chapter_code = 'DF';
UPDATE public.chapter_registry SET logo_url = '/assets/logos/pmimg.png', display_order = 4 WHERE chapter_code = 'MG';
UPDATE public.chapter_registry SET logo_url = '/assets/logos/pmirs.png', display_order = 5 WHERE chapter_code = 'RS';

CREATE INDEX IF NOT EXISTS idx_chapter_registry_active_order
  ON public.chapter_registry(is_active, display_order NULLS LAST, chapter_code)
  WHERE is_active = true;
