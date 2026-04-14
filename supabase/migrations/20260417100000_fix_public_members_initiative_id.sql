-- ============================================================================
-- Fix: Add initiative_id to public_members view
-- Purpose: The V4 refactor added initiative_id to members table but the
--          public_members view was not updated. Frontend filters by
--          initiative_id when INITIATIVE_ID is resolved, causing tribe
--          members and leaders to disappear from /tribe/:id pages.
-- Rollback: DROP VIEW public_members; CREATE VIEW public_members AS
--           SELECT (same columns minus initiative_id) FROM members;
-- ============================================================================

DROP VIEW IF EXISTS public_members;

CREATE VIEW public_members AS
SELECT
  id,
  name,
  photo_url,
  chapter,
  operational_role,
  designations,
  tribe_id,
  initiative_id,
  current_cycle_active,
  is_active,
  linkedin_url,
  credly_badges,
  credly_url,
  credly_verified_at,
  cpmai_certified,
  cpmai_certified_at,
  country,
  state,
  cycles,
  created_at,
  share_whatsapp,
  member_status,
  signature_url
FROM members;

-- Restore grants
GRANT SELECT ON public_members TO authenticated;
GRANT SELECT ON public_members TO anon;
GRANT ALL ON public_members TO service_role;
