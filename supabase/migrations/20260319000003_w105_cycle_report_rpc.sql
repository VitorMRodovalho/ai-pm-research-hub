-- ═══════════════════════════════════════════════════════════════════════════
-- W105 — Cycle Report (Executive Dashboard)
-- Date: 2026-03-12
-- Purpose: Aggregate all cycle data into a single executive report object
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.exec_cycle_report(p_cycle_code text DEFAULT 'cycle3-2026')
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_result jsonb;
  v_kpis jsonb;
  v_members jsonb;
  v_tribes jsonb;
  v_production jsonb;
  v_engagement jsonb;
  v_curation jsonb;
  v_cycle jsonb;
  v_total_members int;
  v_active_members int;
BEGIN
  -- Permission check: admin, sponsor, chapter_liaison
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF v_caller.is_superadmin IS NOT TRUE
     AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
     AND NOT (v_caller.designations ?| ARRAY['sponsor', 'chapter_liaison']) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- Cycle info
  SELECT jsonb_build_object(
    'code', COALESCE(c.code, p_cycle_code),
    'name', COALESCE(c.name, 'Ciclo 3 — 2026/1'),
    'start_date', c.start_date,
    'end_date', c.end_date
  ) INTO v_cycle
  FROM public.cycles c
  WHERE c.code = p_cycle_code OR c.is_current = true
  LIMIT 1;

  IF v_cycle IS NULL THEN
    v_cycle := jsonb_build_object('code', p_cycle_code, 'name', 'Ciclo 3 — 2026/1', 'start_date', null, 'end_date', null);
  END IF;

  -- KPIs (delegate to exec_portfolio_health)
  v_kpis := public.exec_portfolio_health(p_cycle_code);

  -- Members
  SELECT COUNT(*) INTO v_total_members FROM public.members;
  SELECT COUNT(*) INTO v_active_members FROM public.members WHERE current_cycle_active = true;

  SELECT jsonb_build_object(
    'total', v_total_members,
    'active', v_active_members,
    'by_chapter', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('chapter', chapter, 'count', cnt) ORDER BY cnt DESC)
      FROM (SELECT chapter, count(*) AS cnt FROM public.members WHERE current_cycle_active = true AND chapter IS NOT NULL GROUP BY chapter) sub
    ), '[]'::jsonb),
    'by_role', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('role', operational_role, 'count', cnt) ORDER BY cnt DESC)
      FROM (SELECT COALESCE(operational_role, 'none') AS operational_role, count(*) AS cnt FROM public.members WHERE current_cycle_active = true GROUP BY operational_role) sub
    ), '[]'::jsonb),
    'retention_rate', ROUND(COALESCE(
      (SELECT COUNT(*) FILTER (WHERE jsonb_array_length(cycles) > 1)::numeric * 100
       / NULLIF(COUNT(*), 0)
       FROM public.members WHERE current_cycle_active = true AND cycles IS NOT NULL),
      0
    )),
    'new_this_cycle', (
      SELECT COUNT(*) FROM public.members
      WHERE current_cycle_active = true
        AND (cycles IS NULL OR jsonb_array_length(cycles) <= 1)
    )
  ) INTO v_members;

  -- Tribes
  SELECT COALESCE(jsonb_agg(tribe_data ORDER BY tribe_data->>'name'), '[]'::jsonb) INTO v_tribes
  FROM (
    SELECT jsonb_build_object(
      'id', t.id,
      'name', t.name,
      'leader', COALESCE((SELECT m.name FROM public.members m WHERE m.tribe_id = t.id AND m.operational_role = 'tribe_leader' LIMIT 1), '—'),
      'member_count', (SELECT COUNT(*) FROM public.members m WHERE m.tribe_id = t.id AND m.current_cycle_active = true),
      'board_items_total', COALESCE((
        SELECT COUNT(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        WHERE pb.tribe_id = t.id
      ), 0),
      'board_items_completed', COALESCE((
        SELECT COUNT(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        WHERE pb.tribe_id = t.id AND bi.status IN ('done', 'published', 'approved')
      ), 0),
      'completion_pct', COALESCE(
        ROUND(
          (SELECT COUNT(*) FROM public.board_items bi
           JOIN public.project_boards pb ON pb.id = bi.board_id
           WHERE pb.tribe_id = t.id AND bi.status IN ('done', 'published', 'approved'))::numeric * 100
          / NULLIF((SELECT COUNT(*) FROM public.board_items bi
                    JOIN public.project_boards pb ON pb.id = bi.board_id
                    WHERE pb.tribe_id = t.id), 0)
        ), 0
      ),
      'articles_produced', COALESCE((
        SELECT COUNT(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        WHERE pb.tribe_id = t.id AND (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')
          AND bi.status IN ('done', 'published', 'approved')
      ), 0)
    ) AS tribe_data
    FROM public.tribes t
    WHERE t.is_active = true
  ) sub;

  -- Production
  SELECT jsonb_build_object(
    'articles_submitted', (
      SELECT COUNT(*) FROM public.board_items bi
      JOIN public.project_boards pb ON pb.id = bi.board_id
      WHERE pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%'
    ),
    'articles_published', (
      SELECT COUNT(*) FROM public.board_items bi
      JOIN public.project_boards pb ON pb.id = bi.board_id
      WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')
        AND bi.status IN ('published', 'approved', 'done')
    ),
    'articles_in_review', (
      SELECT COUNT(*) FROM public.board_items bi
      JOIN public.project_boards pb ON pb.id = bi.board_id
      WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')
        AND bi.status IN ('review', 'in_progress')
    ),
    'webinars_completed', (SELECT COUNT(*) FROM public.events WHERE type = 'webinar' AND date <= now()),
    'webinars_planned', (SELECT COUNT(*) FROM public.events WHERE type = 'webinar' AND date > now())
  ) INTO v_production;

  -- Engagement
  SELECT jsonb_build_object(
    'total_events', (SELECT COUNT(*) FROM public.events),
    'total_attendance_hours', COALESCE((SELECT total_impact_hours FROM public.impact_hours_total LIMIT 1), 0),
    'avg_attendance_per_event', COALESCE(
      (SELECT ROUND(AVG(attendee_count)) FROM (
        SELECT COUNT(*) AS attendee_count FROM public.attendance WHERE present = true GROUP BY event_id
      ) sub),
      0
    ),
    'certification_completion_rate', ROUND(COALESCE(
      (SELECT COUNT(*) FILTER (WHERE cpmai_certified = true)::numeric * 100
       / NULLIF(COUNT(*), 0)
       FROM public.members WHERE current_cycle_active = true),
      0
    )),
    'course_progress_avg', 0  -- No course_progress table; placeholder
  ) INTO v_engagement;

  -- Curation
  SELECT jsonb_build_object(
    'items_submitted', COALESCE((SELECT COUNT(*) FROM public.curation_review_log), 0),
    'items_approved', COALESCE((SELECT COUNT(*) FROM public.curation_review_log WHERE decision = 'approved'), 0),
    'items_in_review', COALESCE((
      SELECT COUNT(*) FROM public.board_items WHERE status = 'review'
    ), 0),
    'avg_review_days', COALESCE((
      SELECT ROUND(AVG(EXTRACT(EPOCH FROM (completed_at - created_at)) / 86400)::numeric, 1)
      FROM public.curation_review_log
    ), 0),
    'sla_compliance_rate', COALESCE((
      SELECT ROUND(
        COUNT(*) FILTER (WHERE completed_at <= due_date)::numeric * 100
        / NULLIF(COUNT(*) FILTER (WHERE due_date IS NOT NULL), 0)
      )
      FROM public.curation_review_log
    ), 0)
  ) INTO v_curation;

  -- Assemble
  v_result := jsonb_build_object(
    'cycle', v_cycle,
    'kpis', v_kpis,
    'members', v_members,
    'tribes', v_tribes,
    'production', v_production,
    'engagement', v_engagement,
    'curation', v_curation
  );

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.exec_cycle_report(text) TO authenticated;

COMMIT;
