-- Adds contracting_chapter to selection_cycles for governance tracking
-- Fixes volunteer agreement RPCs to use contracting_chapter instead of member.chapter
-- Fixes diversity dashboard cycle selector and data enrichment

-- 1. Schema: contracting_chapter on selection_cycles
ALTER TABLE selection_cycles ADD COLUMN IF NOT EXISTS contracting_chapter text DEFAULT 'PMI-GO';

-- 2. Backfill existing cycles
UPDATE selection_cycles SET contracting_chapter = 'PMI-GO' WHERE contracting_chapter IS NULL;

-- 3. Backfill existing certificates with contracting_chapter
UPDATE certificates c
SET content_snapshot = c.content_snapshot || jsonb_build_object(
  'member_chapter', m.chapter,
  'contracting_chapter', 'PMI-GO'
)
FROM members m
WHERE m.id = c.member_id
  AND c.type = 'volunteer_agreement'
  AND (c.content_snapshot->>'contracting_chapter') IS NULL;

-- 4. RPCs are applied directly (sign_volunteer_agreement, counter_sign_certificate,
--    get_pending_countersign, get_volunteer_agreement_status, get_diversity_dashboard)
--    See session 08/Apr for full definitions.
