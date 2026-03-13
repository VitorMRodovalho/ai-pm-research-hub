-- W115: Chapter Dashboard RPC
-- Gap G5.2/G6.2: Sponsors/liaisons need per-chapter contribution view

CREATE OR REPLACE FUNCTION exec_chapter_dashboard(p_chapter text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_role text;
  v_is_admin boolean;
  v_desigs text[];
  v_chapter text;
  v_result jsonb;
  v_year_start date;
  v_members jsonb;
  v_production jsonb;
  v_engagement jsonb;
  v_certification jsonb;
BEGIN
  -- ACL: admin, sponsor, chapter_liaison, or member of the chapter
  SELECT operational_role, is_superadmin, designations, chapter
  INTO v_role, v_is_admin, v_desigs, v_chapter
  FROM members WHERE auth_id = auth.uid();

  IF NOT (
    v_is_admin
    OR v_role IN ('manager', 'deputy_manager')
    OR v_desigs && ARRAY['sponsor', 'chapter_liaison']
    OR v_chapter = p_chapter
  ) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  -- Temporal anchor (year kickoff)
  v_year_start := make_date(EXTRACT(year FROM now())::int, 1, 1);
  BEGIN
    SELECT date INTO v_year_start FROM events
    WHERE type = 'general' AND title ILIKE '%kick%off%'
    AND EXTRACT(year FROM date) = EXTRACT(year FROM now())
    ORDER BY date ASC LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_year_start := make_date(EXTRACT(year FROM now())::int, 1, 1);
  END;
  v_year_start := COALESCE(v_year_start, make_date(EXTRACT(year FROM now())::int, 1, 1));

  -- Members
  SELECT jsonb_build_object(
    'total', count(*),
    'active', count(*) FILTER (WHERE current_cycle_active),
    'by_role', COALESCE((SELECT jsonb_object_agg(operational_role, cnt)
      FROM (SELECT operational_role, count(*) cnt
            FROM members WHERE chapter = p_chapter AND current_cycle_active
            GROUP BY operational_role) sub), '{}'::jsonb),
    'tribes', COALESCE((SELECT jsonb_agg(DISTINCT t.name)
      FROM members m2 JOIN tribes t ON t.id = m2.tribe_id
      WHERE m2.chapter = p_chapter AND m2.current_cycle_active), '[]'::jsonb)
  ) INTO v_members FROM members WHERE chapter = p_chapter;

  -- Production
  BEGIN
    SELECT jsonb_build_object(
      'articles_in_pipeline', count(*) FILTER (WHERE bi.curation_status IS NOT NULL AND bi.curation_status != 'draft'),
      'articles_published', count(*) FILTER (WHERE bi.curation_status = 'approved'),
      'board_items_total', count(*)
    ) INTO v_production
    FROM board_item_assignments bia
    JOIN members m ON m.id = bia.member_id
    JOIN board_items bi ON bi.id = bia.item_id
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
    FROM attendance a
    JOIN events e ON e.id = a.event_id
    JOIN members m ON m.id = a.member_id
    WHERE m.chapter = p_chapter AND e.date >= v_year_start AND a.status = 'present';
  EXCEPTION WHEN OTHERS THEN
    v_engagement := jsonb_build_object('attendance_events', 0, 'total_hours', 0, 'members_present', 0);
  END;

  -- Certification
  SELECT jsonb_build_object(
    'cpmai_certified', count(*) FILTER (WHERE cpmai_certified),
    'total_active', count(*)
  ) INTO v_certification
  FROM members
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

GRANT EXECUTE ON FUNCTION exec_chapter_dashboard(text) TO authenticated;

-- RPC for cross-chapter comparison (GP only)
CREATE OR REPLACE FUNCTION exec_chapter_comparison()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_member members%ROWTYPE;
  v_result jsonb;
BEGIN
  SELECT * INTO v_member FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR NOT (
    v_member.is_superadmin
    OR v_member.operational_role IN ('manager', 'deputy_manager')
  ) THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  SELECT jsonb_agg(row_to_json(r)) INTO v_result
  FROM (
    SELECT
      m.chapter,
      count(*) AS total_members,
      count(*) FILTER (WHERE m.current_cycle_active) AS active_members,
      count(*) FILTER (WHERE m.cpmai_certified) AS cpmai_certified,
      COALESCE((SELECT count(*) FROM board_item_assignments bia2
        JOIN board_items bi2 ON bi2.id = bia2.item_id
        WHERE bia2.member_id = ANY(array_agg(m.id))
        AND bi2.curation_status = 'approved'), 0) AS articles_approved,
      COALESCE((SELECT count(DISTINCT a2.event_id) FROM attendance a2
        WHERE a2.member_id = ANY(array_agg(m.id))
        AND a2.status = 'present'), 0) AS attendance_events
    FROM members m
    WHERE m.chapter IS NOT NULL
    GROUP BY m.chapter
    ORDER BY count(*) FILTER (WHERE m.current_cycle_active) DESC
  ) r;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION exec_chapter_comparison() TO authenticated;
