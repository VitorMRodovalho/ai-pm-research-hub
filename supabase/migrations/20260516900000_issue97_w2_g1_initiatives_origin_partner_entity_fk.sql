-- Issue #97 W2 G1: formalize initiatives ↔ partner_entities FK
-- Pre-state: link via metadata.partner_entity_id ad-hoc (1 row LATAM LIM 2026).
-- Post-state: dedicated nullable FK column + backfill from metadata.

ALTER TABLE public.initiatives
  ADD COLUMN IF NOT EXISTS origin_partner_entity_id uuid
    REFERENCES public.partner_entities(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_initiatives_origin_partner
  ON public.initiatives(origin_partner_entity_id)
  WHERE origin_partner_entity_id IS NOT NULL;

UPDATE public.initiatives i
SET origin_partner_entity_id = (i.metadata->>'partner_entity_id')::uuid
WHERE i.origin_partner_entity_id IS NULL
  AND i.metadata ? 'partner_entity_id'
  AND (i.metadata->>'partner_entity_id') ~ '^[0-9a-f-]{36}$'
  AND EXISTS (
    SELECT 1 FROM public.partner_entities pe
    WHERE pe.id = (i.metadata->>'partner_entity_id')::uuid
  );

COMMENT ON COLUMN public.initiatives.origin_partner_entity_id IS
'Issue #97 W2 G1. Formal FK to partner_entities for Partnership→Initiative journey provenance. Replaces ad-hoc metadata.partner_entity_id (still available as legacy redundant snapshot).';

NOTIFY pgrst, 'reload schema';
