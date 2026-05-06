-- p95 #129: webinar series schema (split from #89 Frente 2)
-- ====================================================================
-- Per ADR-0020 D6: webinar_series CONSOLIDA into publication_series (already in prod, 5 seeds).
-- Não criar tabela separada — series_id REFERENCES publication_series(id).
-- 7 webinars current state, 0/7 com event_id (gap). Auto-backfill event_id deferred
-- (timezone matching is fragile — admin/líder backfill manually via UI).
--
-- Smoke validated p95 2026-05-05: 8/8 cols shipped, invariants 11/11 = 0.

ALTER TABLE public.webinars
  ADD COLUMN IF NOT EXISTS series_id uuid REFERENCES public.publication_series(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS series_position smallint,
  ADD COLUMN IF NOT EXISTS tribe_anchors integer[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS format_type text,
  ADD COLUMN IF NOT EXISTS briefing_doc_url text,
  ADD COLUMN IF NOT EXISTS sympla_event_url text,
  ADD COLUMN IF NOT EXISTS promo_kit_url text,
  ADD COLUMN IF NOT EXISTS comms_kickoff_at timestamptz;

ALTER TABLE public.webinars
  ADD CONSTRAINT webinars_format_type_check
  CHECK (format_type IS NULL OR format_type IN ('palestra','painel','dupla','lightning','workshop'));

CREATE INDEX IF NOT EXISTS ix_webinars_series_id
  ON public.webinars (series_id, series_position)
  WHERE series_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_webinars_tribe_anchors
  ON public.webinars USING gin (tribe_anchors)
  WHERE array_length(tribe_anchors, 1) > 0;

COMMENT ON COLUMN public.webinars.series_id IS
  'p95 #129: optional FK to publication_series. Per ADR-0020 D6, webinar_series CONSOLIDATED into publication_series. NULL for standalone webinars.';
COMMENT ON COLUMN public.webinars.series_position IS
  'p95 #129: ordinal position within series (e.g., 1, 2, 3 of 6 in storytelling arc).';
COMMENT ON COLUMN public.webinars.tribe_anchors IS
  'p95 #129: legacy_tribe_id array — webinars that involve multiple tribes (cross-tribe collaboration view). Empty for single-tribe.';
COMMENT ON COLUMN public.webinars.format_type IS
  'p95 #129: enum {palestra | painel | dupla | lightning | workshop}. Used by storytelling matrix per series narrative arc.';
COMMENT ON COLUMN public.webinars.briefing_doc_url IS
  'p95 #129: link to briefing document (Drive/Notion/etc). Used by Mayanna comms self-service (#131).';
COMMENT ON COLUMN public.webinars.sympla_event_url IS
  'p95 #129: link to Sympla event registration page. Used by D-30 trigger comms cadence (#131).';
COMMENT ON COLUMN public.webinars.promo_kit_url IS
  'p95 #129: link to promotional materials kit (Canva/Drive folder). Used by comms team for divulgação.';
COMMENT ON COLUMN public.webinars.comms_kickoff_at IS
  'p95 #129: timestamp comms team starts active promotion (D-30 default). Used to track promo cadence vs scheduled_at.';

NOTIFY pgrst, 'reload schema';
