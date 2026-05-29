-- p277 / #419 (ADR-0100) — metric 1: impact_hours converges onto the single canonical source.
--
-- WHAT: get_homepage_stats computed impact_hours with its OWN inline formula (a 4th variant — audit
--   D4): COALESCE(duration_actual, duration_minutes, 60) * present-attendee-count, hardcoded start
--   '2026-01-01', ROUND 0, and NO excused exclusion. The canonical primitive get_impact_hours_canonical
--   (ADR-0096) is the agreed source (excludes excused, COALESCE(actual,minutes) with no 60 fallback,
--   dynamic year window, ROUND 1) and is what the homepage KpiSection card + the Admin dashboard KPI
--   already use — so the homepage hero (#stat-hours) and its own KpiSection currently disagree.
--
--   This points get_homepage_stats.impact_hours at get_impact_hours_canonical(). round() preserves the
--   hero's integer display (697 today; canonical YTD = 696.8 → round = 697, i.e. NO visible change),
--   and get_cycle_report — which reads get_homepage_stats()->'impact_hours' — auto-converges. The
--   4-way fork collapses to one source; future excused/duration drift can no longer split the surfaces.
--
-- WHY: ADR-0100 §2.3 + §3.2 (single canonical metric; "every hours surface calls
--   get_impact_hours_canonical"). First metric of the #419 program (one metric per PR). The
--   contract test locks the forward-defense: get_homepage_stats must NOT re-implement the formula inline.
--
-- SCOPE: org-level impact_hours only (homepage + cycle_report). Chapter-scoped hours
--   (get_chapter_dashboard / exec_chapter_dashboard) use different windows/scope and converge in a
--   later #419 step (needs a scope-parameterized canonical). active_members / attendance_rate / roster
--   / XP / trail remain subsequent #419 PRs.
--
-- ROLLBACK: re-CREATE the prior get_homepage_stats body with the inline impact_hours subquery.

CREATE OR REPLACE FUNCTION public.get_homepage_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN jsonb_build_object(
    'members', (SELECT count(*) FROM members WHERE is_active AND current_cycle_active),
    'observers', (SELECT count(*) FROM members WHERE member_status = 'observer'),
    'alumni', (SELECT count(*) FROM members WHERE member_status = 'alumni'),
    'tribes', (SELECT count(*) FROM tribes WHERE is_active),
    'initiatives', (
      SELECT count(*) FROM initiatives
      WHERE status = 'active' AND legacy_tribe_id IS NULL
    ),
    'total_initiatives', (
      SELECT count(*) FROM initiatives WHERE status = 'active'
    ),
    'active_leaders', (
      SELECT count(DISTINCT person_id) FROM auth_engagements
      WHERE status = 'active' AND role IN ('leader', 'co_leader', 'co_gp')
    ),
    'chapters', (SELECT COUNT(DISTINCT chapter) FROM members WHERE is_active = true AND chapter IS NOT NULL),
    -- ADR-0100 #419 metric 1: impact_hours = the single canonical source (was an inline 4th formula).
    -- round() keeps the hero's integer display; cycle_report reads this value and auto-converges.
    'impact_hours', round(public.get_impact_hours_canonical())
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
