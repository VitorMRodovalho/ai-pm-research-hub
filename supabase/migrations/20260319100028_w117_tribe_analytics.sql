-- W117: Tribe Analytics Dashboard
-- ============================================================
-- RPCs: exec_tribe_dashboard, exec_all_tribes_summary
-- Zero new tables — aggregation over existing data
-- ============================================================

-- ============================================================
-- 1. EXEC_TRIBE_DASHBOARD
--    Returns full dashboard data for a single tribe.
-- ============================================================
CREATE OR REPLACE FUNCTION public.exec_tribe_dashboard(
  p_tribe_id int,
  p_cycle text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_tribe record;
  v_leader record;
  v_cycle_start date;
  v_result jsonb;

  -- members
  v_members_total int;
  v_members_active int;
  v_members_by_role jsonb;
  v_members_by_chapter jsonb;
  v_members_list jsonb;

  -- production
  v_board record;
  v_prod_total int := 0;
  v_prod_by_status jsonb := '{}'::jsonb;
  v_articles_submitted int := 0;
  v_articles_approved int := 0;
  v_articles_published int := 0;
  v_curation_pending int := 0;
  v_avg_days_to_approval numeric := 0;

  -- engagement
  v_attendance_rate numeric := 0;
  v_total_meetings int := 0;
  v_total_hours numeric := 0;
  v_avg_attendance numeric := 0;
  v_members_with_streak int := 0;
  v_members_inactive_30d int := 0;
  v_last_meeting_date date;
  v_next_meeting jsonb := '{}'::jsonb;

  -- gamification
  v_tribe_total_xp int := 0;
  v_tribe_avg_xp numeric := 0;
  v_top_contributors jsonb := '[]'::jsonb;
  v_cpmai_certified int := 0;

  -- trends
  v_attendance_by_month jsonb := '[]'::jsonb;
  v_production_by_month jsonb := '[]'::jsonb;

  -- meeting slots
  v_meeting_slots jsonb := '[]'::jsonb;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Get tribe
  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe IS NULL THEN
    RAISE EXCEPTION 'Tribe not found';
  END IF;

  -- 3. Permission check
  IF v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
    AND NOT (v_caller.operational_role = 'tribe_leader' AND v_caller.tribe_id = p_tribe_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.members m2
      WHERE m2.id = v_caller.id
        AND ('sponsor' = ANY(m2.designations) OR 'chapter_liaison' = ANY(m2.designations))
        AND m2.chapter IN (SELECT chapter FROM public.members WHERE tribe_id = p_tribe_id AND chapter IS NOT NULL LIMIT 1)
    )
  THEN
    RAISE EXCEPTION 'Unauthorized: insufficient permissions for tribe %', p_tribe_id;
  END IF;

  -- 4. Cycle start anchor
  v_cycle_start := COALESCE(
    (SELECT MIN(date) FROM public.events
     WHERE title ILIKE '%kick%off%' AND date >= '2026-01-01'),
    '2026-03-05'::date
  );

  -- 5. Get leader
  SELECT id, name, photo_url INTO v_leader
  FROM public.members
  WHERE id = v_tribe.leader_member_id;

  -- 6. Meeting slots
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'day_of_week', tms.day_of_week,
      'time_start', tms.time_start,
      'time_end', tms.time_end
    )
  ), '[]'::jsonb) INTO v_meeting_slots
  FROM public.tribe_meeting_slots tms
  WHERE tms.tribe_id = p_tribe_id AND tms.is_active = true;

  -- ═══ MEMBERS ═══
  SELECT COUNT(*) INTO v_members_total
  FROM public.members WHERE tribe_id = p_tribe_id AND is_active = true;

  SELECT COUNT(*) INTO v_members_active
  FROM public.members WHERE tribe_id = p_tribe_id AND is_active = true AND current_cycle_active = true;

  SELECT COALESCE(jsonb_object_agg(role, cnt), '{}'::jsonb) INTO v_members_by_role
  FROM (
    SELECT operational_role AS role, COUNT(*) AS cnt
    FROM public.members
    WHERE tribe_id = p_tribe_id AND is_active = true
    GROUP BY operational_role
  ) sub;

  SELECT COALESCE(jsonb_object_agg(ch, cnt), '{}'::jsonb) INTO v_members_by_chapter
  FROM (
    SELECT COALESCE(chapter, 'N/A') AS ch, COUNT(*) AS cnt
    FROM public.members
    WHERE tribe_id = p_tribe_id AND is_active = true
    GROUP BY chapter
  ) sub;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', m.id,
      'name', m.name,
      'chapter', m.chapter,
      'operational_role', m.operational_role,
      'xp_total', COALESCE((SELECT SUM(points) FROM public.gamification_points WHERE member_id = m.id), 0),
      'attendance_rate', COALESCE(
        (SELECT ROUND(
          COUNT(*) FILTER (WHERE a.present = true)::numeric /
          NULLIF(COUNT(*), 0), 2
        ) FROM public.attendance a
        JOIN public.events e ON e.id = a.event_id
        WHERE a.member_id = m.id AND e.tribe_id = p_tribe_id AND e.date >= v_cycle_start),
        0
      ),
      'cpmai_certified', COALESCE(m.cpmai_certified, false),
      'certifications', COALESCE(m.certifications, ''),
      'last_activity_at', GREATEST(
        m.updated_at,
        (SELECT MAX(a2.created_at) FROM public.attendance a2 WHERE a2.member_id = m.id)
      )
    ) ORDER BY COALESCE((SELECT SUM(points) FROM public.gamification_points WHERE member_id = m.id), 0) DESC
  ), '[]'::jsonb) INTO v_members_list
  FROM public.members m
  WHERE m.tribe_id = p_tribe_id AND m.is_active = true;

  -- ═══ PRODUCTION ═══
  SELECT * INTO v_board
  FROM public.project_boards
  WHERE tribe_id = p_tribe_id AND domain_key = 'research_delivery' AND is_active = true
  LIMIT 1;

  IF v_board.id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_prod_total
    FROM public.board_items WHERE board_id = v_board.id;

    SELECT COALESCE(jsonb_object_agg(status, cnt), '{}'::jsonb) INTO v_prod_by_status
    FROM (
      SELECT status, COUNT(*) AS cnt
      FROM public.board_items
      WHERE board_id = v_board.id
      GROUP BY status
    ) sub;

    -- Articles submitted/approved/published via curation_status
    SELECT
      COUNT(*) FILTER (WHERE curation_status IN ('submitted', 'under_review', 'approved', 'published')) INTO v_articles_submitted
    FROM public.board_items WHERE board_id = v_board.id;

    SELECT COUNT(*) FILTER (WHERE curation_status = 'approved')
    INTO v_articles_approved
    FROM public.board_items WHERE board_id = v_board.id;

    SELECT COUNT(*) FILTER (WHERE curation_status = 'published')
    INTO v_articles_published
    FROM public.board_items WHERE board_id = v_board.id;

    SELECT COUNT(*) FILTER (WHERE curation_status IN ('submitted', 'under_review'))
    INTO v_curation_pending
    FROM public.board_items WHERE board_id = v_board.id;
  END IF;

  -- ═══ ENGAGEMENT ═══
  SELECT
    COUNT(DISTINCT e.id),
    COALESCE(SUM(COALESCE(e.duration_actual, e.duration_minutes, 60)) / 60.0, 0)
  INTO v_total_meetings, v_total_hours
  FROM public.events e
  WHERE e.tribe_id = p_tribe_id AND e.date >= v_cycle_start;

  IF v_total_meetings > 0 AND v_members_active > 0 THEN
    SELECT ROUND(
      COUNT(*) FILTER (WHERE a.present = true)::numeric /
      NULLIF(v_members_active * v_total_meetings, 0), 2
    ) INTO v_attendance_rate
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    WHERE e.tribe_id = p_tribe_id AND e.date >= v_cycle_start;

    SELECT ROUND(
      COUNT(*) FILTER (WHERE a.present = true)::numeric /
      NULLIF(v_total_meetings, 0), 1
    ) INTO v_avg_attendance
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    WHERE e.tribe_id = p_tribe_id AND e.date >= v_cycle_start;
  END IF;

  -- Last meeting date
  SELECT MAX(e.date) INTO v_last_meeting_date
  FROM public.events e
  WHERE e.tribe_id = p_tribe_id AND e.date <= CURRENT_DATE;

  -- Members inactive 30d
  SELECT COUNT(*) INTO v_members_inactive_30d
  FROM public.members m
  WHERE m.tribe_id = p_tribe_id AND m.is_active = true
    AND NOT EXISTS (
      SELECT 1 FROM public.attendance a
      JOIN public.events e ON e.id = a.event_id
      WHERE a.member_id = m.id AND a.present = true
        AND e.date >= (CURRENT_DATE - INTERVAL '30 days')
    );

  -- Next meeting from meeting slots
  SELECT jsonb_build_object(
    'day_of_week', tms.day_of_week,
    'time_start', tms.time_start
  ) INTO v_next_meeting
  FROM public.tribe_meeting_slots tms
  WHERE tms.tribe_id = p_tribe_id AND tms.is_active = true
  LIMIT 1;

  -- ═══ GAMIFICATION ═══
  SELECT COALESCE(SUM(gp.points), 0) INTO v_tribe_total_xp
  FROM public.gamification_points gp
  WHERE gp.member_id IN (SELECT id FROM public.members WHERE tribe_id = p_tribe_id AND is_active = true);

  v_tribe_avg_xp := CASE WHEN v_members_active > 0
    THEN ROUND(v_tribe_total_xp::numeric / v_members_active, 1) ELSE 0 END;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object('name', sub.name, 'xp', sub.xp, 'rank', sub.rn)
  ), '[]'::jsonb) INTO v_top_contributors
  FROM (
    SELECT m.name, SUM(gp.points) AS xp, ROW_NUMBER() OVER (ORDER BY SUM(gp.points) DESC) AS rn
    FROM public.gamification_points gp
    JOIN public.members m ON m.id = gp.member_id
    WHERE m.tribe_id = p_tribe_id AND m.is_active = true
    GROUP BY m.id, m.name
    ORDER BY xp DESC
    LIMIT 5
  ) sub;

  SELECT COUNT(*) INTO v_cpmai_certified
  FROM public.members
  WHERE tribe_id = p_tribe_id AND is_active = true AND cpmai_certified = true;

  -- ═══ TRENDS ═══
  -- Attendance by month
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object('month', sub.month, 'rate', sub.rate)
    ORDER BY sub.month
  ), '[]'::jsonb) INTO v_attendance_by_month
  FROM (
    SELECT
      TO_CHAR(e.date, 'YYYY-MM') AS month,
      ROUND(
        COUNT(*) FILTER (WHERE a.present = true)::numeric /
        NULLIF(COUNT(*), 0), 2
      ) AS rate
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    WHERE e.tribe_id = p_tribe_id AND e.date >= v_cycle_start
    GROUP BY TO_CHAR(e.date, 'YYYY-MM')
  ) sub;

  -- Production by month
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object('month', sub.month, 'cards_created', sub.created, 'cards_completed', sub.completed)
    ORDER BY sub.month
  ), '[]'::jsonb) INTO v_production_by_month
  FROM (
    SELECT
      TO_CHAR(bi.created_at, 'YYYY-MM') AS month,
      COUNT(*) AS created,
      COUNT(*) FILTER (WHERE bi.status = 'done') AS completed
    FROM public.board_items bi
    WHERE bi.board_id = v_board.id AND bi.created_at >= v_cycle_start
    GROUP BY TO_CHAR(bi.created_at, 'YYYY-MM')
  ) sub;

  -- ═══ BUILD RESULT ═══
  v_result := jsonb_build_object(
    'tribe', jsonb_build_object(
      'id', v_tribe.id,
      'name', v_tribe.name,
      'quadrant', v_tribe.quadrant,
      'quadrant_name', v_tribe.quadrant_name,
      'leader', CASE WHEN v_leader.id IS NOT NULL THEN jsonb_build_object(
        'id', v_leader.id, 'name', v_leader.name, 'avatar_url', v_leader.photo_url
      ) ELSE NULL END,
      'meeting_slots', v_meeting_slots,
      'whatsapp_url', v_tribe.whatsapp_url,
      'drive_url', v_tribe.drive_url
    ),
    'members', jsonb_build_object(
      'total', v_members_total,
      'active', v_members_active,
      'by_role', v_members_by_role,
      'by_chapter', v_members_by_chapter,
      'list', v_members_list
    ),
    'production', jsonb_build_object(
      'total_cards', v_prod_total,
      'by_status', v_prod_by_status,
      'articles_submitted', v_articles_submitted,
      'articles_approved', v_articles_approved,
      'articles_published', v_articles_published,
      'curation_pending', v_curation_pending,
      'avg_days_to_approval', v_avg_days_to_approval
    ),
    'engagement', jsonb_build_object(
      'attendance_rate', v_attendance_rate,
      'total_meetings', v_total_meetings,
      'total_hours', ROUND(v_total_hours, 1),
      'avg_attendance_per_meeting', v_avg_attendance,
      'members_inactive_30d', v_members_inactive_30d,
      'last_meeting_date', v_last_meeting_date,
      'next_meeting', v_next_meeting
    ),
    'gamification', jsonb_build_object(
      'tribe_total_xp', v_tribe_total_xp,
      'tribe_avg_xp', v_tribe_avg_xp,
      'top_contributors', v_top_contributors,
      'certification_progress', jsonb_build_object(
        'cpmai_certified', v_cpmai_certified
      )
    ),
    'trends', jsonb_build_object(
      'attendance_by_month', v_attendance_by_month,
      'production_by_month', v_production_by_month
    )
  );

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.exec_tribe_dashboard(int, text) TO authenticated;

-- ============================================================
-- 2. EXEC_ALL_TRIBES_SUMMARY
--    Returns summary array for cross-tribe comparison.
--    GP/DM/superadmin only.
-- ============================================================
CREATE OR REPLACE FUNCTION public.exec_all_tribes_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_result jsonb;
  v_cycle_start date;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. GP/DM/superadmin only
  IF v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager', 'deputy_manager') THEN
    RAISE EXCEPTION 'Unauthorized: GP or DM required';
  END IF;

  -- 3. Cycle start
  v_cycle_start := COALESCE(
    (SELECT MIN(date) FROM public.events
     WHERE title ILIKE '%kick%off%' AND date >= '2026-01-01'),
    '2026-03-05'::date
  );

  -- 4. Build summary
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'tribe_id', t.id,
      'name', t.name,
      'quadrant', t.quadrant,
      'member_count', (SELECT COUNT(*) FROM public.members WHERE tribe_id = t.id AND is_active = true),
      'attendance_rate', COALESCE(
        (SELECT ROUND(
          COUNT(*) FILTER (WHERE a.present = true)::numeric /
          NULLIF(COUNT(*), 0), 2
        ) FROM public.attendance a
        JOIN public.events e ON e.id = a.event_id
        WHERE e.tribe_id = t.id AND e.date >= v_cycle_start),
        0
      ),
      'articles_count', COALESCE(
        (SELECT COUNT(*) FROM public.board_items bi
         JOIN public.project_boards pb ON pb.id = bi.board_id
         WHERE pb.tribe_id = t.id AND bi.curation_status IN ('submitted', 'approved', 'published')),
        0
      ),
      'xp_total', COALESCE(
        (SELECT SUM(gp.points) FROM public.gamification_points gp
         WHERE gp.member_id IN (SELECT id FROM public.members WHERE tribe_id = t.id AND is_active = true)),
        0
      ),
      'leader_name', (SELECT name FROM public.members WHERE id = t.leader_member_id)
    ) ORDER BY t.id
  ), '[]'::jsonb) INTO v_result
  FROM public.tribes t
  WHERE t.is_active = true AND t.workstream_type = 'research';

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.exec_all_tribes_summary() TO authenticated;
