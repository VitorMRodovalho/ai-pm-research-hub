-- PR 4 of #766 item 2/4 (server-side milestones framework).
-- See docs/specs/SPEC_766_SERVER_SIDE_MILESTONES.md §7 (PR4).
--
-- Adds the `promotion` milestone: fired when a member's operational_role is elevated to
-- 'tribe_leader' (the leader-track role) from any non-leader role.
--
-- GROUNDING (execute_sql, 2026-06-17): operational_role has NO value 'leader' — the SPEC §7
-- draft said 'leader', but the live leader-track role is 'tribe_leader' (6 members). The RPC
-- promote_to_leader_track does NOT touch members.operational_role (it only manipulates
-- selection_applications); the role is set to 'tribe_leader' by the sync_operational_role_cache
-- trigger from auth_engagements. So the only hook that captures EVERY promotion path (incl. a
-- direct admin UPDATE) is a trigger on members.operational_role itself, not an RPC hook.
--
-- Scope: NARROW — only tribe_leader. manager/deputy_manager are GP-structural roles, not a
-- volunteer's celebrated promotion; broadening would mix semantics. UNIQUE(member_id,
-- milestone_key) guarantees only the FIRST elevation celebrates (data-architect, PR4).
--
-- NO new invariant (count stays 31). Unlike term_signed / first_attendance / first_deliverable,
-- promotion has NO immutable source of truth: operational_role is a mutable cache and demotion
-- (tribe_leader -> alumni at cycle end) is routine, so a directional "milestone => is tribe_leader
-- now" check would generate permanent false positives for every rotated-out leader. The
-- structural guard is the trigger WHEN clause + UNIQUE + record_milestone REVOKE
-- (data-architect + security-engineer GO-with-changes, PR4).
--
-- schema-cache-columns.test gate (ADR-0012): VERIFIED CLEAN — this migration adds NO column to
-- members/engagements/initiatives (trigger-only), so the cache-column contract is not engaged.
--
-- Backfill is SILENT (acknowledged_at = now()) so the 6 current tribe_leaders are NOT
-- re-celebrated; only post-deploy elevations fire a pending milestone. Race-safe: backfill runs
-- BEFORE CREATE TRIGGER (SPEC §6.3). occurred_at = COALESCE(updated_at, created_at, now()) — a
-- proxy for the promotion moment (no promoted_at column exists; updated_at may be later than the
-- real promotion if the row was touched again — acceptable for an informational column).
--
-- Edge (documented): a member promoted -> demoted -> re-promoted is NOT in the backfill (not
-- tribe_leader at apply time), so the trigger fires on re-promotion and they celebrate then —
-- "first time the milestone is recorded", not "first promotion ever". Acceptable for v1 (SPEC §6.5).
--
-- ROLLBACK:
--   DROP TRIGGER IF EXISTS trg_record_promotion_milestone ON public.members;
--   DROP FUNCTION IF EXISTS public._trg_record_promotion_milestone();
--   DELETE FROM public.member_milestones WHERE milestone_key = 'promotion';
--   NOTIFY pgrst, 'reload schema';

-- 1. Trigger function. source_id is NULL (no role_transitions table; source_type='promotion' is
--    informational). public.record_milestone is schema-qualified (search_path=''). No inline
--    comment inside the function body — Phase C captures prosrc verbatim (PR2/PR3 sediment).
CREATE OR REPLACE FUNCTION public._trg_record_promotion_milestone()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
BEGIN
  PERFORM public.record_milestone(
    NEW.id, 'promotion', 'promotion', NULL::uuid,
    jsonb_build_object('via', 'operational_role_trigger', 'from_role', OLD.operational_role, 'to_role', NEW.operational_role)
  );
  RETURN NEW;
END; $fn$;
REVOKE ALL ON FUNCTION public._trg_record_promotion_milestone() FROM PUBLIC;

-- 2. Silent backfill (acknowledged_at=now()). MUST run BEFORE CREATE TRIGGER (SPEC §6.3).
--    Cohort at apply time (live, 2026-06-17): 6 members with operational_role='tribe_leader'.
INSERT INTO public.member_milestones
  (member_id, milestone_key, occurred_at, source_type, source_id, acknowledged_at, metadata)
SELECT id, 'promotion', COALESCE(updated_at, created_at, now()), 'promotion', NULL::uuid, now(),
  jsonb_build_object('backfill', true, 'migration', '20260805000204', 'to_role', operational_role)
FROM public.members
WHERE operational_role = 'tribe_leader'
ON CONFLICT (member_id, milestone_key) DO NOTHING;

-- 3. Sanity — every current tribe_leader must now hold the milestone (mirror PR2/PR3).
DO $sanity$
DECLARE v_missing int;
BEGIN
  SELECT count(*) INTO v_missing
  FROM public.members m
  WHERE m.operational_role = 'tribe_leader'
    AND NOT EXISTS (
      SELECT 1 FROM public.member_milestones mm
      WHERE mm.member_id = m.id AND mm.milestone_key = 'promotion'
    );
  IF v_missing > 0 THEN
    RAISE EXCEPTION 'PR4 #766 promotion backfill sanity FAIL: % tribe_leader members lack a milestone', v_missing;
  END IF;
  RAISE NOTICE 'PR4 #766 promotion backfill sanity OK.';
END$sanity$;

-- 4. Trigger (created AFTER the backfill, race-safe). The WHEN clause is the integrity guard:
--    fires only on the transition INTO tribe_leader from a different role.
DROP TRIGGER IF EXISTS trg_record_promotion_milestone ON public.members;
CREATE TRIGGER trg_record_promotion_milestone
  AFTER UPDATE OF operational_role ON public.members
  FOR EACH ROW
  WHEN (NEW.operational_role = 'tribe_leader' AND OLD.operational_role IS DISTINCT FROM 'tribe_leader')
  EXECUTE FUNCTION public._trg_record_promotion_milestone();

COMMENT ON FUNCTION public._trg_record_promotion_milestone() IS
  '#766 PR4: records the promotion member_milestone when a member''s operational_role is elevated to tribe_leader (AFTER UPDATE OF operational_role, WHEN NEW=tribe_leader AND OLD<>tribe_leader; mirrors no sibling — the RPC promote_to_leader_track does not set operational_role). First-occurrence via record_milestone ON CONFLICT DO NOTHING. No directional invariant: operational_role is a mutable cache (demotion is routine), so the structural guard is the WHEN clause + UNIQUE + REVOKE.';

NOTIFY pgrst, 'reload schema';
