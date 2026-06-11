-- Migration: homepage public stats exclude the pre-onboarding cohort + data-driven next general meeting
-- Issue: homepage "Pesquisadores ativos" showed 72 while /admin/members shows 48 operando (#625 C0/C1 class).
--   Grounded 2026-06-11: 72 = 47 operando + 25 pre-onboarding (rule from #626 / mig 20260805000142).
--   PM decision 2026-06-11: public stat counts only members OPERATING in the current cycle (47 at ship time).
--   Also: the homepage "Reunião Geral" line was a hardcoded i18n string ("Toda quinta-feira · 19:30 BRT")
--   while the real cadence (events table) is BIWEEKLY Thursdays 19:00–20:30 BRT → new public RPC
--   get_next_general_meeting() so the component renders the actual next occurrence (PM: data-driven).
--
-- Contents:
--   1. public.member_is_pre_onboarding(uuid, text) — single source for the #626 cohort rule
--      (extracted from admin_list_members' inline LATERAL; #625 C1 should refactor that RPC to
--      call this helper so the rule cannot drift). NOT exposed to anon/authenticated (callers
--      are SECURITY DEFINER owned by postgres, which bypasses ACLs).
--   2. get_public_platform_stats.active_members — excludes the cohort (rest of body verbatim
--      from live pg_get_functiondef, 2026-06-11).
--   3. get_homepage_stats.members — same exclusion (consumed by HomepageHero + TribesSection;
--      keeping both RPCs consistent so the hero and the stats strip can't diverge).
--   4. get_next_general_meeting() — anon-executable public surface, NO personal data
--      (institutional agenda only: next type='geral' event date/time_start/duration_minutes).
--      initiative_id IS NULL is load-bearing: tribe weekly meetings also carry type='geral'.
--      RoPA: docs/audit/LGPD_ROPA_PUBLIC_SURFACES.md (surface added in the same PR).
--
-- ROLLBACK:
--   - get_public_platform_stats / get_homepage_stats: restore bodies captured in
--     20260805000094_p481_chapter_fork_cleanup_invariants.sql (members expression
--     `is_active AND current_cycle_active` without the helper call).
--   - DROP FUNCTION public.get_next_general_meeting();
--   - DROP FUNCTION public.member_is_pre_onboarding(uuid, text);
--
-- After apply: NOTIFY pgrst, 'reload schema'.

-- ── 1. Cohort-rule helper (single source; rule verbatim from mig 20260805000142) ──────────────
CREATE OR REPLACE FUNCTION public.member_is_pre_onboarding(p_person_id uuid, p_member_status text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- #625 C0 rule (mig 142): pré-onboarding = ativo cujo ÚNICO vínculo são engagements
  -- aguardando termo. Operacional = kind sem exigência de termo OU termo satisfeito;
  -- existir 1 operacional tira o membro da coorte.
  SELECT p_member_status = 'active'
    AND EXISTS (
      SELECT 1 FROM engagements e
      WHERE e.person_id = p_person_id AND e.status = 'active'
    )
    AND NOT EXISTS (
      SELECT 1 FROM engagements e
      JOIN engagement_kinds ek ON ek.slug = e.kind
      WHERE e.person_id = p_person_id AND e.status = 'active'
        AND (ek.requires_agreement IS NOT TRUE OR e.agreement_certificate_id IS NOT NULL)
    );
$function$;

COMMENT ON FUNCTION public.member_is_pre_onboarding(uuid, text) IS
  '#625/#626 cohort rule, single source. Used by get_public_platform_stats + get_homepage_stats; admin_list_members still inlines the same rule (consolidation tracked under #625 C1). Not API-exposed (no anon/authenticated EXECUTE).';

REVOKE EXECUTE ON FUNCTION public.member_is_pre_onboarding(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.member_is_pre_onboarding(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.member_is_pre_onboarding(uuid, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.member_is_pre_onboarding(uuid, text) TO service_role;

-- ── 2. get_public_platform_stats: active_members excludes pre-onboarding ──────────────────────
CREATE OR REPLACE FUNCTION public.get_public_platform_stats()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT json_build_object(
    -- #625 C1 (homepage instance): pre-onboarding cohort excluded — "Pesquisadores ativos"
    -- counts only members OPERATING in the current cycle (PM 2026-06-11; was 72 = 47 + 25 pre).
    'active_members', (
      SELECT COUNT(*) FROM members m
      WHERE m.is_active AND m.current_cycle_active
        AND NOT public.member_is_pre_onboarding(m.person_id, m.member_status)
    ),
    'total_tribes', (SELECT COUNT(*) FROM tribes WHERE is_active),
    'total_initiatives', (
      SELECT count(*) FROM initiatives
      WHERE status = 'active' AND legacy_tribe_id IS NULL
    ),
    -- #481: canonical signed-chapter count (was count(DISTINCT chapter) WHERE chapter != 'Externo'=7; the
    -- !='Externo' filter was a no-op since no member carries chapter='Externo').
    'total_chapters', (public.get_chapter_metrics()->>'signed')::int,
    'total_events', (SELECT COUNT(*) FROM events WHERE date >= '2026-01-01'),
    'total_resources', (SELECT COUNT(*) FROM hub_resources WHERE is_active),
    'retention_rate', (
      SELECT ROUND(
        COUNT(*) FILTER (WHERE current_cycle_active)::numeric /
        NULLIF(COUNT(*) FILTER (WHERE is_active OR member_status = 'alumni'), 0) * 100, 1
      )
      FROM members WHERE member_status IN ('active','alumni','observer')
    )
  );
$function$;

-- ── 3. get_homepage_stats: members excludes pre-onboarding (hero/tribes consistency) ──────────
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
    ),
    'total_initiatives', (
      SELECT count(*) FROM initiatives WHERE status = 'active'
    ),
    'active_leaders', (
      SELECT count(DISTINCT person_id) FROM auth_engagements
      WHERE status = 'active' AND role IN ('leader', 'co_leader', 'co_gp')
    ),
    -- #481: canonical signed-chapter count (was count(DISTINCT members.chapter)=7 incl noise)
    'chapters', (public.get_chapter_metrics()->>'signed')::int,
    -- ADR-0100 #419 metric 1: impact_hours = the single canonical source (was an inline 4th formula).
    -- round() keeps the hero's integer display; cycle_report reads this value and auto-converges.
    'impact_hours', round(public.get_impact_hours_canonical())
  );
END;
$function$;

-- ── 4. get_next_general_meeting: public, data-driven agenda line (zero PII) ────────────────────
CREATE OR REPLACE FUNCTION public.get_next_general_meeting()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- initiative_id IS NULL is load-bearing: tribe weekly meetings also use type='geral'.
  -- events.date for the geral series is midnight UTC (calendar date); time_start carries the
  -- BRT wall-clock — consumers must render the date part as-is (no tz shift) + time_start.
  SELECT json_build_object(
    'date', e.date::date,
    'time_start', e.time_start,
    'duration_minutes', e.duration_minutes
  )
  FROM events e
  WHERE e.type = 'geral'
    AND e.initiative_id IS NULL
    AND COALESCE(e.status, 'scheduled') <> 'cancelled'
    AND e.date >= CURRENT_DATE
  ORDER BY e.date ASC
  LIMIT 1;
$function$;

COMMENT ON FUNCTION public.get_next_general_meeting() IS
  'Public surface (anon EXECUTE): next general meeting of the Núcleo — date/time_start/duration_minutes only. NO personal data (institutional agenda; LGPD n/a — RoPA entry in docs/audit/LGPD_ROPA_PUBLIC_SURFACES.md). Consumer: WeeklyScheduleSection.astro (homepage).';

REVOKE ALL ON FUNCTION public.get_next_general_meeting() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_next_general_meeting() TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
