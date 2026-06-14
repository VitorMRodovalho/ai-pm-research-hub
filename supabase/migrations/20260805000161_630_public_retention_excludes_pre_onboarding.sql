-- =====================================================================================
-- #630 / #625 fold: public retention_rate excludes the pre-onboarding cohort.
--
-- Context:
--   Migration 20260805000143 made the public homepage active-member headline exclude
--   Camada 0/pre-onboarding via public.member_is_pre_onboarding(person_id, member_status),
--   but get_public_platform_stats.retention_rate still used the legacy denominator:
--     member_status IN ('active','alumni','observer')
--   That denominator can include active pre-onboarding members, depressing public retention.
--
-- Fix:
--   Recreate get_public_platform_stats() with the same public aggregate shape, applying
--   NOT public.member_is_pre_onboarding(m.person_id, m.member_status) to the retention
--   cohort. This keeps the numerator and denominator on the same operating-member base.
--
-- Scope:
--   Public aggregate only. No PII added. Signature unchanged. Body-only CREATE OR REPLACE.
--
-- Rollback:
--   Restore get_public_platform_stats() from
--   20260805000143_homepage_stats_pre_onboarding_and_next_general_meeting.sql.
-- =====================================================================================

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
    )
  );
$function$;

COMMENT ON FUNCTION public.get_public_platform_stats() IS
  '#630/#625: public aggregate stats. active_members and retention_rate exclude Camada 0/pre-onboarding via member_is_pre_onboarding(person_id, member_status). Zero PII public surface.';

REVOKE ALL ON FUNCTION public.get_public_platform_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_platform_stats() TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
