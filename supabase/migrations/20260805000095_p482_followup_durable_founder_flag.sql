-- ════════════════════════════════════════════════════════════════
-- #482 follow-up — durable is_founder marker for the public "Fundadores" wall
-- ════════════════════════════════════════════════════════════════
-- PROBLEM: #482 keyed the wall off the 'founder' DESIGNATION, but invariant C
-- (check_schema_invariants) clears members.designations on terminal status
-- (alumni / inactive / observer). So a founder / 2024-pilot participant who goes
-- alumni LOSES the 'founder' designation and drops out of the wall entirely — the
-- #482 "mute non-active founders" treatment could NEVER fire. Confirmed live: the
-- 2024-pilot alumni (Carlos Magno, Andressa Martins, Giovanni Oliveira Baroni Brandão)
-- carry no designation and were absent from the wall.
--
-- FIX (PM-curated, 2026-06-02): a permanent boolean members.is_founder that SURVIVES
-- offboarding (only designations are cleared on terminal status, not this column).
-- Seeded from the durable 2024-pilot signal (cycles @> {pilot-2024}) plus any current
-- 'founder'-designated member = 8 today (5 active founders + 3 PM-confirmed alumni).
-- Admin-controlled thereafter. The TeamSection wall re-sources off is_founder and mutes
-- members whose member_status <> 'active' (robust vs the current_cycle_active anomaly, #483).
--
-- ROLLBACK:
--   CREATE OR REPLACE VIEW public.public_members AS <prior column list, without is_founder>;
--   ALTER TABLE public.members DROP COLUMN is_founder;
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.members
  ADD COLUMN IF NOT EXISTS is_founder boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.members.is_founder IS
  'Durable founder / 2024-pilot marker for the public Fundadores wall. Survives offboarding (unlike the ''founder'' designation, which invariant C clears on terminal status). Curated / admin-controlled. #482 follow-up.';

-- Seed the curated set: the 2024-pilot cohort (durable cycles tag) + any founder-designated member.
UPDATE public.members
  SET is_founder = true
  WHERE cycles && ARRAY['pilot-2024']::text[]
     OR 'founder' = ANY(designations);

-- Expose is_founder on the anon-readable public surface (appended at the end — CREATE OR REPLACE
-- VIEW requires the prior columns unchanged in order/type; grants + (null) reloptions are preserved).
CREATE OR REPLACE VIEW public.public_members AS
  SELECT id,
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
         signature_url,
         is_founder
  FROM public.members;

NOTIFY pgrst, 'reload schema';

-- Sanity: the curated founder set must include the full 2024-pilot cohort (>= 8).
DO $sanity$
DECLARE v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.members WHERE is_founder;
  IF v_n < 8 THEN RAISE EXCEPTION '#482-followup: expected >= 8 founders flagged, got %', v_n; END IF;
END
$sanity$;
