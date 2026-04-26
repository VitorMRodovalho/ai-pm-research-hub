-- Track R Phase R3 — COMMENT ON TABLE/VIEW for 20 intentional public objects
-- See docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md (Track R section).
--
-- Polish step: each of the 20 tables/views that legitimately retain
-- anon SELECT grant gets an inline COMMENT documenting WHY the public
-- exposure is intentional. This:
--   1. Provides audit trail in the schema itself (auditors see intent
--      without reading external docs)
--   2. Suppresses `pg_graphql_anon_table_exposed` lint output per
--      Supabase advisor doc pattern (lint accepts annotated objects)
--   3. Establishes ADR-0024 documentation pattern as default for
--      future intentional public exposures

-- ============================================================
-- A. Homepage / anon-tier .from() callers (8)
-- ============================================================
COMMENT ON TABLE public.announcements IS
  'Public-by-design: rendered by AnnouncementBanner.astro on every page (BaseLayout), including anon-tier visitors. Filter `is_active = true AND (ends_at IS NULL OR ends_at > now())`. No PII — operational announcements only. Track R Phase R3 (p59).';

COMMENT ON TABLE public.blog_posts IS
  'Public-by-design: rendered by /blog public pages (anon accessible). RLS filter `status = ''published''` ensures only published posts visible. Track R Phase R3 (p59).';

COMMENT ON TABLE public.events IS
  'Public-by-design: homepage HeroSection + HomepageHero render upcoming events. Anon RLS policy (`events_read_anon`) restricts to type IN (geral, webinar). Track R Phase R3 (p59).';

COMMENT ON TABLE public.home_schedule IS
  'Public-by-design: lib/schedule.ts loads on homepage for anon visitors. Operational meeting schedule data — no PII. Track R Phase R3 (p59).';

COMMENT ON TABLE public.hub_resources IS
  'Public-by-design: ResourcesSection.astro homepage card + library.astro public catalog. Resource library (articles, videos, tools) for visitors. Track R Phase R3 (p59).';

COMMENT ON TABLE public.site_config IS
  'Public-by-design: ChaptersSection + WeeklyScheduleSection + ReportPage on homepage. Operational config (chapter list, schedule labels, etc.) — no PII. Track R Phase R3 (p59).';

COMMENT ON TABLE public.tribe_meeting_slots IS
  'Public-by-design: homepage TribesSection + WeeklyScheduleSection display tribe meeting times for visitors. Schedule metadata only — no PII. Track R Phase R3 (p59).';

COMMENT ON TABLE public.tribes IS
  'Public-by-design: homepage TribesSection + HeroSection + HomepageHero render tribe catalog. Tribe metadata (name, color, status) — no PII. Track R Phase R3 (p59).';

-- ============================================================
-- B. Explicit USING true public reference data (8)
-- ============================================================
COMMENT ON TABLE public.courses IS
  'Public-by-design: course catalog (trail courses + electives) for visitors and members. RLS policy `Public courses USING true`. No PII — course metadata only. Track R Phase R3 (p59).';

COMMENT ON TABLE public.cycles IS
  'Public-by-design: research cycle metadata (cycle_code, label, dates) used by lib/cycles.ts utility loaded across many pages including homepage. RLS policy `cycles_read_all USING true`. No PII. Track R Phase R3 (p59).';

COMMENT ON TABLE public.help_journeys IS
  'Public-by-design: help.astro public help center renders persona-keyed navigation. RLS policy `Public reads help journeys USING true`. Visitor-facing onboarding nav. Track R Phase R3 (p59).';

COMMENT ON TABLE public.ia_pilots IS
  'Public-by-design: AI pilot showcase data displayed publicly to demonstrate platform impact. RLS policy `ia_pilots_read USING true`. Aggregate pilot metadata — no PII. Track R Phase R3 (p59).';

COMMENT ON TABLE public.offboard_reason_categories IS
  'Public-by-design: reference data for offboarding workflow form taxonomy. RLS policy `offboard_reason_categories_read USING true`. Reference data only — no PII. Track R Phase R3 (p59).';

COMMENT ON TABLE public.quadrants IS
  'Public-by-design: research quadrant taxonomy reference data. RLS policy `quadrants_read_all USING true`. Reference data only. Track R Phase R3 (p59).';

COMMENT ON TABLE public.release_items IS
  'Public-by-design: release notes line items rendered on /changelog public page. Anon+authenticated RLS policy with `visible = true` filter. Track R Phase R3 (p59).';

COMMENT ON TABLE public.releases IS
  'Public-by-design: platform release history rendered on /changelog public page. RLS policy `Anyone can view releases USING true`. Release metadata only. Track R Phase R3 (p59).';

-- ============================================================
-- C. Public KPI / publication / certification (4)
-- ============================================================
COMMENT ON TABLE public.portfolio_kpi_quarterly_targets IS
  'Public-by-design: quarterly KPI targets dashboard data for transparency to all visitors. RLS policy `quarterly_targets_read USING true`. Aggregate target values — no PII. Track R Phase R3 (p59).';

COMMENT ON TABLE public.portfolio_kpi_targets IS
  'Public-by-design: annual KPI targets dashboard data for transparency. RLS policy `anon_read_kpi_targets` explicit anon role grant USING true. Aggregate target values — no PII. Track R Phase R3 (p59).';

COMMENT ON TABLE public.public_publications IS
  'Public-by-design: published research articles, frameworks, and toolkits visible at /publications public page. RLS policy `pub_read_published` filter `is_published = true`. Publication metadata + author credits — author names are public-by-definition. Track R Phase R3 (p59).';

COMMENT ON TABLE public.webinars IS
  'Public-by-design: webinar catalog for /webinars public page + homepage radar. RLS policy `webinars_read_anon` explicit anon role with `status IN (confirmed, completed)` filter. Webinar metadata — no PII. Track R Phase R3 (p59).';

-- ============================================================
-- D. Intentional public views per ADR-0024 / ADR-0010 (2)
-- ============================================================
COMMENT ON VIEW public.public_members IS
  'Public-by-design (ADR-0024 accepted risk): exposes leadership member metadata (name, photo, chapter, designations) for homepage TeamSection + TribesSection + CpmaiSection. SECURITY DEFINER — view creator (postgres) bypasses RLS to filter to public-safe columns. Advisor flags this as ERROR but ADR-0024 accepts the risk: leadership identities are intentionally public per PMI institutional pattern. Track R Phase R3 (p59) — see ADR-0024.';

COMMENT ON VIEW public.members_public_safe IS
  'Public-by-design (ADR-0010): exposes only public-safe member columns (id, name, operational_role, tribe_id, current_cycle_active, photo_url) for homepage + tribe pages. No PII fields (email, phone, pmi_id, auth_id excluded). Track R Phase R3 (p59).';

-- ============================================================
-- E. Gamification leaderboard (anon-readable per public flow) (2)
-- ============================================================
COMMENT ON TABLE public.gamification_points IS
  'Public-by-design (ADR-0024 pattern): exposes gamification points for /gamification page public leaderboard (loadLeaderboard runs for anon visitors). Member XP and ranking are intentionally public per gamified community pattern. No financial or PII data — only points/category/reason metadata. Track R Phase R3 (p59).';

COMMENT ON TABLE public.tribe_selections IS
  'Public-by-design: rendered by TribesSection.astro on homepage (selected tribe member counts) + gamification.astro public tribe ranking. RLS policies `Public tribe counts USING true` and `anon_read_tribe_selections`. Tribe membership metadata — no PII beyond member_id linkage which is also public via public_members view. Track R Phase R3 (p59).';

-- Notify PostgREST to refresh schema cache
NOTIFY pgrst, 'reload schema';
