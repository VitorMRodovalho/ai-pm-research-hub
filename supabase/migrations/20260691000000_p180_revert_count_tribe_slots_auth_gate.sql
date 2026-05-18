-- ============================================================================
-- p180 REVERT — count_tribe_slots auth gate removal
-- ============================================================================
-- 2026-05-17 · session p180 close · code-reviewer regression surfaced
-- Issue: p180 migration 20260689000000 added `IF auth.uid() IS NULL THEN RAISE`
-- to count_tribe_slots as defensive auth gate. Close council code-reviewer
-- surfaced LIVE regression: TribesSection.astro is rendered on the PUBLIC
-- landing page (/index, /en/index, /es/index) and calls count_tribe_slots
-- via `getSb()` → window.navGetSb() which returns the supabase client. For
-- anonymous visitors (no auth.uid()), the new auth gate throws → console
-- error → tribeCounts stays empty → UI shows "0/7" for all tribes (broken
-- counts).
--
-- Anon visitors hit this on first page load. Counts are PUBLIC-by-design
-- aggregate data (no PII surface — just tribe occupancy numbers). Original
-- migration 20260309200000 deliberately `GRANT EXECUTE TO anon`.
--
-- Revert: restore pre-p180 body (pure SQL, no auth gate). p180 V4 scope
-- adjusts to 3 V4 refactors + 2 cron parity + 1 fix (count_tribe_slots
-- defensive gate dropped as out-of-scope expansion that broke anon UX).
--
-- Rollback of this revert: re-add `IF auth.uid() IS NULL THEN RAISE` AND
-- update TribesSection.astro to guard `if (!member) return;` before calling
-- (Option B path) OR create a separate get_public_tribe_counts() variant
-- (Option C path). PM-decided Option A (this revert) at p180 close.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.count_tribe_slots()
 RETURNS json
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT coalesce(
    json_object_agg(tribe_id, cnt),
    '{}'::json
  )
  FROM (
    SELECT tribe_id, count(*)::int as cnt
    FROM public.members
    WHERE member_status = 'active'
      AND tribe_id IS NOT NULL
      AND operational_role NOT IN ('sponsor', 'chapter_liaison', 'guest', 'none')
    GROUP BY tribe_id
  ) sub;
$function$;

NOTIFY pgrst, 'reload schema';
