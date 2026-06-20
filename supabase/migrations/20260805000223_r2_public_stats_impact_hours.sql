-- R2 (Ciclo 4): Prova viva única — add impact_hours to the public proof RPC.
-- Single canonical source shared with the hero: get_homepage_stats.impact_hours
-- and this both use round(get_impact_hours_canonical()) => identical headline (807h).
-- Additive change (one key in json_build_object); signature unchanged => CREATE OR REPLACE.
CREATE OR REPLACE FUNCTION public.get_public_platform_stats()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT json_build_object(
    -- #625 C1 (homepage instance): pre-onboarding cohort excluded -- "Pesquisadores ativos"
    -- counts only members OPERATING in the current cycle.
    'active_members', (
      SELECT COUNT(*) FROM public.members m
      WHERE m.is_active AND m.current_cycle_active
        AND NOT public.member_is_pre_onboarding(m.person_id, m.member_status)
    ),
    'total_tribes', (SELECT COUNT(*) FROM public.tribes WHERE is_active),
    'total_initiatives', (
      SELECT count(*) FROM public.initiatives
      WHERE status = 'active' AND legacy_tribe_id IS NULL
    ),
    -- Cycle 4: community verticals (ADR-0103) surfaced as a live counter.
    'total_verticals', (
      SELECT count(*) FROM public.initiatives
      WHERE kind = 'community_vertical' AND status = 'active'
    ),
    -- #481: canonical signed-chapter count.
    'total_chapters', (public.get_chapter_metrics()->>'signed')::int,
    'total_events', (SELECT COUNT(*) FROM public.events WHERE date >= '2026-01-01'),
    'total_resources', (SELECT COUNT(*) FROM public.hub_resources WHERE is_active),
    'retention_rate', (
      SELECT ROUND(
        COUNT(*) FILTER (WHERE m.current_cycle_active)::numeric /
        NULLIF(COUNT(*) FILTER (WHERE m.is_active OR m.member_status = 'alumni'), 0) * 100, 1
      )
      FROM public.members m
      WHERE m.member_status IN ('active','alumni','observer')
        AND NOT public.member_is_pre_onboarding(m.person_id, m.member_status)
    ),
    -- R2 (Ciclo 4): canonical impact-hours, shared with the hero headline (single denominator).
    'impact_hours', round(public.get_impact_hours_canonical())
  );
$function$;

REVOKE ALL ON FUNCTION public.get_public_platform_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_platform_stats() TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
