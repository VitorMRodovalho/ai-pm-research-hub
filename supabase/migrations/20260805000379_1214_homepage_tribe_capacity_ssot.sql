-- #1214: landing tribe capacity regressed to "Máx. 10" — expose the capacity SSOT
-- (platform_settings.max_researchers_per_tribe) through get_homepage_stats so the public
-- homepage derives its slot cap from the DB instead of a stale frontend constant.
--
-- 1) tribe_capacity_limit(): align the no-row fallback with the ratified cap (7; the old
--    10 predates the cap-7 decision — a missing setting row must fail toward the stricter
--    gate, not the legacy cap).
-- 2) get_homepage_stats(): add max_researchers_per_tribe via tribe_capacity_limit() —
--    the same helper select_tribe uses, so there is one formula, not two.

CREATE OR REPLACE FUNCTION public.tribe_capacity_limit()
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
    (select (value #>> '{}')::int from public.platform_settings where key = 'max_researchers_per_tribe'),
    7
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_homepage_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN jsonb_build_object(
    -- #625 C1 (homepage instance): same exclusion as get_public_platform_stats.active_members.
    'members', (
      SELECT count(*) FROM members m
      WHERE m.is_active AND m.current_cycle_active
        AND NOT public.member_is_pre_onboarding(m.person_id, m.member_status)
    ),
    'observers', (SELECT count(*) FROM members WHERE member_status = 'observer'),
    'alumni', (SELECT count(*) FROM members WHERE member_status = 'alumni'),
    'tribes', (SELECT count(*) FROM tribes WHERE is_active),
    'initiatives', (
      SELECT count(*) FROM initiatives
      WHERE status = 'active' AND legacy_tribe_id IS NULL
        AND visibility <> 'confidential'  -- #785 PR-3: aggregate excludes confidential
    ),
    'total_initiatives', (
      SELECT count(*) FROM initiatives WHERE status = 'active'
        AND visibility <> 'confidential'  -- #785 PR-3: aggregate excludes confidential
    ),
    'active_leaders', (
      SELECT count(DISTINCT person_id) FROM auth_engagements
      WHERE status = 'active' AND role IN ('leader', 'co_leader', 'co_gp')
    ),
    -- #481: canonical signed-chapter count (was count(DISTINCT members.chapter)=7 incl noise)
    'chapters', (public.get_chapter_metrics()->>'signed')::int,
    -- ADR-0100 #419 metric 1: impact_hours = the single canonical source (was an inline 4th formula).
    -- round() keeps the hero's integer display; cycle_report reads this value and auto-converges.
    'impact_hours', round(public.get_impact_hours_canonical()),
    -- #1214: tribe slot cap for the public landing — same SSOT the select_tribe server
    -- gate uses (platform_settings.max_researchers_per_tribe via tribe_capacity_limit()).
    'max_researchers_per_tribe', public.tribe_capacity_limit()
  );
END;
$function$;
