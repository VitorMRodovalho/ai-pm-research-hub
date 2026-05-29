-- p277 / #419 (ADR-0100) metric 3 (attendance_rate) — step 3b: canonical primitive (FOUNDATION).
--
-- WHAT: the canonical per-member attendance rate (ADR-0100 §2.2/§2.3). The atom that every
--   attendance_rate surface converges onto:
--     numerator   = present = true
--     denominator = recorded events with status in (present, absent) — i.e. excused EXCLUDED
--     window      = current cycle (cycles.is_current), or an explicit caller-passed cycle_start
--     emit        = fraction 0..1 ROUND 2; NULL when there are no eligible events (surfaces COALESCE / N/A)
--   Cancelled + future events never count.
--
--   This is the per-(member,event) model the ADR fixes: the denominator is the events where the member
--   has a recorded present/absent status, NOT an "expected events" projection (that was the
--   calc_attendance_pct fork). Aggregate surfaces (home hero, tribe avg, admin grid) take AVG over their
--   cohort of this per-member value; per-member surfaces read it directly.
--
-- ADDITIVE: nothing consumes this yet, so it changes ZERO live numbers. The ~21 attendance_rate
--   computation sites converge onto it in subsequent per-surface PRs, each with an antes->depois.
--
-- LGPD: not granted to anon/authenticated — it would expose any member's rate. Internal SECDEF callers
--   (the converging RPCs, owned by postgres) reach it as definer; service_role for tests/admin paths.
--
-- ROLLBACK: DROP FUNCTION public.get_attendance_rate(uuid, date);

CREATE OR REPLACE FUNCTION public.get_attendance_rate(p_member_id uuid, p_cycle_start date DEFAULT NULL)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT ROUND(
    count(*) FILTER (WHERE a.present = true)::numeric
    / NULLIF(count(*) FILTER (WHERE a.excused IS NOT TRUE), 0),
    2)
  FROM public.attendance a
  JOIN public.events e ON e.id = a.event_id
  WHERE a.member_id = p_member_id
    AND e.date >= COALESCE(p_cycle_start, (SELECT c.cycle_start FROM public.cycles c WHERE c.is_current = true LIMIT 1), '2026-03-01')
    AND e.date <= CURRENT_DATE
    AND e.status IS DISTINCT FROM 'cancelled';
$function$;

REVOKE ALL ON FUNCTION public.get_attendance_rate(uuid, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_attendance_rate(uuid, date) TO service_role;

COMMENT ON FUNCTION public.get_attendance_rate(uuid, date) IS
  'Canonical per-member attendance rate (ADR-0100 #419 metric 3): present / (present + absent), excused '
  'excluded, current-cycle window (cycles.is_current), fraction 0..1 ROUND 2, NULL when no eligible events. '
  'Building block — surfaces aggregate it (AVG over cohort) or read it per member. Not anon/authenticated-'
  'granted (internal SECDEF callers + service_role only).';

NOTIFY pgrst, 'reload schema';
