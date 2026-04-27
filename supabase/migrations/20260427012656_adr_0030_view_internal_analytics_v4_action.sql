-- ADR-0030 (Accepted, p66): view_internal_analytics V4 action
-- Phase B'' V3→V4 conversion of can_read_internal_analytics, exec_role_transitions, exec_chapter_dashboard.
-- See docs/adr/ADR-0030-view-internal-analytics-v4-action.md
--
-- PM ratified Q1-Q4 (2026-04-26 p66):
--   Q1 curator (Path A drop): SIM — drift correction (Sarah perde access)
--   Q2 own-chapter clause (Path Y preserve): SIM
--   Q3 migrate helper to pure V4: SIM
--   Q4 timing: p66 mesmo
--
-- Privilege expansion safety check (verified pre-apply):
--   legacy_count = 12 (V3 set incl curator + chapter_liaison designations)
--   v4_count    = 10
--   would_gain   = []
--   would_lose   = [Sarah Faria (curator-only), João Uzejka (chapter_liaison
--                  designation sem V4 engagement chapter_board×liaison)]
--   Both are V3-designation-without-V4-engagement drift cases — same pattern
--   as Mayanna in ADR-0026 batch 1. Per ADR Path A: documented as expected
--   drift correction. PM may create engagements post-fact if needed.

-- ============================================================
-- 1. Adicionar action view_internal_analytics ao engagement_kind_permissions
-- ============================================================
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope)
VALUES
  ('volunteer',     'co_gp',          'view_internal_analytics', 'organization'),
  ('volunteer',     'manager',        'view_internal_analytics', 'organization'),
  ('volunteer',     'deputy_manager', 'view_internal_analytics', 'organization'),
  ('sponsor',       'sponsor',        'view_internal_analytics', 'organization'),
  ('chapter_board', 'liaison',        'view_internal_analytics', 'organization')
ON CONFLICT (kind, role, action) DO NOTHING;

-- ============================================================
-- 2. Convert can_read_internal_analytics() helper to pure V4
-- ============================================================
CREATE OR REPLACE FUNCTION public.can_read_internal_analytics()
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN false;
  END IF;

  RETURN public.can_by_member(v_caller_id, 'view_internal_analytics');
END;
$$;
COMMENT ON FUNCTION public.can_read_internal_analytics() IS
  'Phase B'' V4 conversion (ADR-0030, p66): pure delegation to can_by_member(_, view_internal_analytics). Was hybrid V3+V4 (manage_member OR designations co_gp/sponsor/chapter_liaison/curator).';

-- ============================================================
-- 3. Convert exec_chapter_dashboard (Path Y — preserve own-chapter clause)
-- ============================================================
CREATE OR REPLACE FUNCTION public.exec_chapter_dashboard(p_chapter text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_result jsonb;
  v_year_start date;
  v_members jsonb;
  v_production jsonb;
  v_engagement jsonb;
  v_certification jsonb;
BEGIN
  -- ACL: V4 view_internal_analytics OR own-chapter access (Path Y per ADR-0030)
  SELECT m.id, m.chapter INTO v_caller_id, v_caller_chapter
  FROM public.members m
  WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'authentication_required');
  END IF;

  IF NOT (
    public.can_by_member(v_caller_id, 'view_internal_analytics')
    OR v_caller_chapter = p_chapter
  ) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  -- Temporal anchor (year kickoff)
  v_year_start := make_date(EXTRACT(year FROM now())::int, 1, 1);
  BEGIN
    SELECT date INTO v_year_start
    FROM public.events
    WHERE type = 'general'
      AND title ILIKE '%kick%off%'
      AND EXTRACT(year FROM date) = EXTRACT(year FROM now())
    ORDER BY date ASC
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_year_start := make_date(EXTRACT(year FROM now())::int, 1, 1);
  END;
  v_year_start := COALESCE(v_year_start, make_date(EXTRACT(year FROM now())::int, 1, 1));

  -- Members
  SELECT jsonb_build_object(
    'total', count(*),
    'active', count(*) FILTER (WHERE current_cycle_active),
    'by_role', COALESCE((SELECT jsonb_object_agg(operational_role, cnt) FROM (SELECT operational_role, count(*) cnt FROM public.members WHERE chapter = p_chapter AND current_cycle_active GROUP BY operational_role) sub), '{}'::jsonb),
    'tribes', COALESCE((SELECT jsonb_agg(DISTINCT t.name) FROM public.members m2 JOIN public.tribes t ON t.id = m2.tribe_id WHERE m2.chapter = p_chapter AND m2.current_cycle_active), '[]'::jsonb)
  ) INTO v_members
  FROM public.members
  WHERE chapter = p_chapter;

  -- Production
  BEGIN
    SELECT jsonb_build_object(
      'articles_in_pipeline', count(*) FILTER (WHERE bi.curation_status IS NOT NULL AND bi.curation_status != 'draft'),
      'articles_published', count(*) FILTER (WHERE bi.curation_status = 'approved'),
      'board_items_total', count(*)
    ) INTO v_production
    FROM public.board_item_assignments bia
    JOIN public.members m ON m.id = bia.member_id
    JOIN public.board_items bi ON bi.id = bia.item_id
    WHERE m.chapter = p_chapter AND bi.created_at >= v_year_start;
  EXCEPTION WHEN OTHERS THEN
    v_production := jsonb_build_object('articles_in_pipeline', 0, 'articles_published', 0, 'board_items_total', 0);
  END;

  -- Engagement
  BEGIN
    SELECT jsonb_build_object(
      'attendance_events', count(DISTINCT a.event_id),
      'total_hours', COALESCE(round(SUM(e.duration_actual / 60.0)::numeric, 1), 0),
      'members_present', count(DISTINCT a.member_id)
    ) INTO v_engagement
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    JOIN public.members m ON m.id = a.member_id
    WHERE m.chapter = p_chapter AND e.date >= v_year_start AND a.present = true;
  EXCEPTION WHEN OTHERS THEN
    v_engagement := jsonb_build_object('attendance_events', 0, 'total_hours', 0, 'members_present', 0);
  END;

  -- Certification
  SELECT jsonb_build_object(
    'cpmai_certified', count(*) FILTER (WHERE cpmai_certified),
    'total_active', count(*)
  ) INTO v_certification
  FROM public.members
  WHERE chapter = p_chapter AND current_cycle_active;

  v_result := jsonb_build_object(
    'chapter', p_chapter,
    'members', v_members,
    'production', v_production,
    'engagement', v_engagement,
    'certification', v_certification
  );

  RETURN v_result;
END;
$$;
COMMENT ON FUNCTION public.exec_chapter_dashboard(text) IS
  'Phase B'' V4 conversion (ADR-0030, p66): can_by_member(_, view_internal_analytics) OR own-chapter access (Path Y preserves member-facing chapter snapshot via /admin/chapter-report nav minTier=observer).';

-- exec_role_transitions body unchanged — helper conversion (step 2) cascades.

NOTIFY pgrst, 'reload schema';
