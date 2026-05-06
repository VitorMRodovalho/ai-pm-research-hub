-- p95 #97 W2: External engagement schema hardening (G1+G2+G3)
-- ====================================================================
-- Implements W2 plan from docs/specs/p87-external-engagement-lifecycle.md
-- Additive only. Backfill LATAM LIM W1 case (1 initiative + 7 board_items).
-- W3 (MCP tool, automation) and W4 (UX wizard) deferred.
-- G7 (welcome email trigger) already shipped previously — out of scope here.
--
-- Smoke validated p95 2026-05-05: all 6 checks pass, invariants 11/11 = 0.

-- ============================================================
-- G1: initiative ↔ partner FK (nullable, ON DELETE SET NULL)
-- ============================================================
ALTER TABLE public.initiatives
  ADD COLUMN IF NOT EXISTS origin_partner_entity_id uuid
    REFERENCES public.partner_entities(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS ix_initiatives_origin_partner
  ON public.initiatives (origin_partner_entity_id)
  WHERE origin_partner_entity_id IS NOT NULL;

-- Backfill LATAM LIM 2026 W1 case (initiative a68fcc06... ← partner 8bb97295...)
UPDATE public.initiatives
SET origin_partner_entity_id = '8bb97295-4e8e-4e19-98a4-37b72d3305b8'::uuid
WHERE id = 'a68fcc06-7de8-400b-b5b3-60e368fb46ac'::uuid
  AND origin_partner_entity_id IS NULL;

COMMENT ON COLUMN public.initiatives.origin_partner_entity_id IS
  'p95 #97 G1: nullable FK linking initiative to originating partner_entity (Partnership→Initiative journey). NULL for organic initiatives.';

-- ============================================================
-- G2: speaker presenter_role formal validation (Opção B — CHECK metadata)
-- ============================================================
-- Pre-validated: 2 existing speakers (Roberto lead + Ivan co) both within new constraint.
ALTER TABLE public.engagements
  ADD CONSTRAINT engagements_speaker_role_check
  CHECK (
    kind <> 'speaker'
    OR (metadata ->> 'presenter_role') IN ('lead', 'co', 'panelist', 'moderator')
  );

COMMENT ON CONSTRAINT engagements_speaker_role_check ON public.engagements IS
  'p95 #97 G2: speakers MUST have metadata.presenter_role IN (lead, co, panelist, moderator). Other kinds unaffected. Spec preferred Option B (CHECK metadata) over Option A (new co_speaker kind) — preserves speaker kind cardinality.';

-- ============================================================
-- G3: board_items external partner provenance
-- ============================================================
ALTER TABLE public.board_items
  ADD COLUMN IF NOT EXISTS source_type text DEFAULT 'internal',
  ADD COLUMN IF NOT EXISTS source_partner_id uuid REFERENCES public.partner_entities(id) ON DELETE SET NULL;

ALTER TABLE public.board_items
  ADD CONSTRAINT board_items_source_type_check
  CHECK (source_type IN ('internal','external_partner','external_event'));

CREATE INDEX IF NOT EXISTS ix_board_items_source_partner
  ON public.board_items (source_partner_id, source_type)
  WHERE source_partner_id IS NOT NULL;

-- Backfill LATAM LIM 7 milestones (board 632787ee...)
UPDATE public.board_items
SET source_type = 'external_partner',
    source_partner_id = '8bb97295-4e8e-4e19-98a4-37b72d3305b8'::uuid
WHERE board_id = '632787ee-9e27-43c9-b6a0-566b52815adc'::uuid
  AND source_partner_id IS NULL;

COMMENT ON COLUMN public.board_items.source_type IS
  'p95 #97 G3: board_item provenance — internal | external_partner | external_event. Default internal preserves pre-G3 rows.';
COMMENT ON COLUMN public.board_items.source_partner_id IS
  'p95 #97 G3: nullable FK to partner_entities when source_type=external_partner. ON DELETE SET NULL.';

NOTIFY pgrst, 'reload schema';
