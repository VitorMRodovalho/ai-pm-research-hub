-- p277 / #419 (ADR-0100) metric 3 — PR2: converge calc_attendance_pct onto canonical ENGAGEMENT.
--
-- SPEC docs/specs/SPEC_419_M3_ATTENDANCE_TWO_METRIC.md, surface [1]. calc_attendance_pct() was the buggy
-- platform-average attendance %: hardcoded '2026-01-01' window (not cycles.is_current), counted 1on1
-- coaching events, included guests in the cohort, used the LEGACY members.tribe_id (not V4 get_member_tribe),
-- and used an "expected events" denominator that mixed scopes. Live = 64.4%.
--
-- Now DELEGATES to the canonical get_attendance_engagement_summary('global') (PR1 foundation): cohort =
-- operational union {researcher,tribe_leader,manager} (37, D2), denominator = eligible events (D6 type set,
-- D4 own-tribe via V4 get_member_tribe + initiatives bridge), excused excluded (D1), window cycles.is_current
-- (D10). NO inline rate re-implementation (delegation only — satisfies the PR10 p175 gate). Same 0-arg
-- signature (single caller get_annual_kpis → admin/portfolio + ChapterDashboard).
--
-- ANTES -> DEPOIS: 64.4% (buggy hybrid) -> 76.2% (canonical engagement). The 64.4% was wrong, not lower
-- participation; communicate the correction (ADR-0100 §4).
--
-- DEFERRED (not this PR): get_public_impact_data hardcoded '2026-03-01' window — it carries NO attendance
-- rate (only total_events / total_attendance_hours), and the literal equals the current cycle_start so there
-- is 0 number change today; it is a window-invariant hygiene item (§2.1), tracked separately.
-- FLAGGED (data/intent, NOT mutated here): Roberto Macêdo (member 49836a70, legacy tribe_id=8) reads
-- get_member_tribe=NULL because his active tribe-8 engagement is a NON-'volunteer' kind (he is curator /
-- publicações / LATAM). Whether he should be a tribe-8 volunteer member is a PM data decision; the V4-consistent
-- treatment (exclude tribe-8 from his eligible set) is what this convergence applies — strictly more correct
-- than calc_attendance_pct's prior legacy-tribe_id path.
--
-- ROLLBACK: re-CREATE calc_attendance_pct with the prior expected-denominator body.

CREATE OR REPLACE FUNCTION public.calc_attendance_pct()
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT ROUND((public.get_attendance_engagement_summary('global') ->> 'avg_rate')::numeric * 100, 1);
$function$;

NOTIFY pgrst, 'reload schema';
