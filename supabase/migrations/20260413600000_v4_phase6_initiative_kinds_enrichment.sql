-- ============================================================================
-- V4 Phase 6 — Migration 1/5: initiative_kinds schema enrichment
-- ADR: ADR-0009 (Config-Driven Initiative Kinds)
-- Depends on: Phase 2 (initiative_kinds table) + Phase 3 (engagement_kinds table)
-- Rollback: ALTER TABLE public.initiative_kinds
--             DROP COLUMN IF EXISTS allowed_engagement_kinds,
--             DROP COLUMN IF EXISTS required_engagement_kinds,
--             DROP COLUMN IF EXISTS certificate_template_id,
--             DROP COLUMN IF EXISTS created_by;
--           DELETE FROM public.initiative_kinds WHERE slug = 'book_club';
-- ============================================================================

-- Add 4 columns specified in ADR-0009 but omitted in Phase 2 (minimal bootstrap).
-- These columns enable config-driven behavior: which engagement kinds can participate,
-- which are required, and who created the kind.

ALTER TABLE public.initiative_kinds
  ADD COLUMN IF NOT EXISTS allowed_engagement_kinds text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS required_engagement_kinds text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS certificate_template_id uuid,
  ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.initiative_kinds.allowed_engagement_kinds IS 'Which engagement_kinds.slug values can participate in initiatives of this kind';
COMMENT ON COLUMN public.initiative_kinds.required_engagement_kinds IS 'Which engagement_kinds.slug values MUST be present (e.g. study_group needs an owner)';
COMMENT ON COLUMN public.initiative_kinds.certificate_template_id IS 'UUID of certificate template for has_certificate=true kinds';
COMMENT ON COLUMN public.initiative_kinds.created_by IS 'auth.users(id) who created this kind via admin UI';

-- ── Update existing seed rows with engagement kind mappings ──────────────────

UPDATE public.initiative_kinds SET
  allowed_engagement_kinds = '{volunteer,observer,alumni,guest,speaker}',
  required_engagement_kinds = '{volunteer}'
WHERE slug = 'research_tribe';

UPDATE public.initiative_kinds SET
  allowed_engagement_kinds = '{study_group_owner,study_group_participant,observer}',
  required_engagement_kinds = '{study_group_owner}'
WHERE slug = 'study_group';

UPDATE public.initiative_kinds SET
  allowed_engagement_kinds = '{volunteer,speaker,guest,observer}',
  required_engagement_kinds = '{volunteer}'
WHERE slug = 'congress';

UPDATE public.initiative_kinds SET
  allowed_engagement_kinds = '{speaker,guest,observer,volunteer}',
  required_engagement_kinds = '{}'
WHERE slug = 'workshop';

-- ── Insert book_club kind (ADR-0009 acceptance criteria) ─────────────────────

INSERT INTO public.initiative_kinds (
  slug, display_name, description, icon,
  default_duration_days, max_concurrent_per_org,
  has_board, has_meeting_notes, has_deliverables, has_attendance, has_certificate,
  allowed_engagement_kinds, required_engagement_kinds,
  lifecycle_states
) VALUES (
  'book_club',
  'Clube do Livro',
  'Grupo de leitura e discussão coletiva de livro ou publicação relevante. Cadência semanal ou quinzenal.',
  'book-open-check',
  90, 10,
  true, true, false, true, false,
  '{volunteer,observer,guest}',
  '{}',
  '{draft,active,concluded,archived}'
);

-- PostgREST reload
NOTIFY pgrst, 'reload schema';
