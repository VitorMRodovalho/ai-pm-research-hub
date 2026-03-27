-- GC-149: Cycle Evolution RPC for C2→C3 report section
DROP FUNCTION IF EXISTS get_cycle_evolution();
CREATE OR REPLACE FUNCTION get_cycle_evolution()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE result jsonb; v_c2_members int; v_c3_members int;
BEGIN
  SELECT count(DISTINCT member_id) INTO v_c2_members FROM member_cycle_history WHERE cycle_code = 'cycle_2';
  SELECT count(DISTINCT member_id) INTO v_c3_members FROM member_cycle_history WHERE cycle_code = 'cycle_3';
  SELECT jsonb_build_object(
    'cycles', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'cycle_code', sub.cycle_code, 'cycle_label', sub.cycle_label, 'members', sub.members,
        'chapters', CASE sub.cycle_code WHEN 'pilot' THEN 1 WHEN 'cycle_1' THEN 1 WHEN 'cycle_2' THEN 2 WHEN 'cycle_3' THEN 5 END,
        'tribes', CASE sub.cycle_code WHEN 'pilot' THEN 3 WHEN 'cycle_1' THEN 5 WHEN 'cycle_2' THEN 5 WHEN 'cycle_3' THEN 8 END,
        'events', CASE sub.cycle_code
          WHEN 'cycle_2' THEN (SELECT count(*) FROM events WHERE date >= '2025-07-01' AND date < '2026-01-01')
          WHEN 'cycle_3' THEN (SELECT count(*) FROM events WHERE date >= '2026-01-01') ELSE NULL END,
        'growth', CASE sub.cycle_code
          WHEN 'cycle_1' THEN ROUND(((sub.members - 8.0) / GREATEST(8,1)) * 100)
          WHEN 'cycle_2' THEN ROUND(((sub.members - 22.0) / GREATEST(22,1)) * 100)
          WHEN 'cycle_3' THEN ROUND(((sub.members - 31.0) / GREATEST(31,1)) * 100) ELSE NULL END
      ) ORDER BY sub.start_date), '[]'::jsonb)
      FROM (SELECT cycle_code, cycle_label, count(DISTINCT member_id) as members, min(cycle_start) as start_date
        FROM member_cycle_history GROUP BY cycle_code, cycle_label) sub),
    'highlights', jsonb_build_object(
      'new_chapters', 3, 'chapter_names', 'PMI-DF, PMI-MG, PMI-RS',
      'platform_version', 'v2.0.0', 'governance_digital', true, 'mcp_server', true,
      'total_articles', (SELECT count(*) FROM publication_submissions),
      'total_events_c3', (SELECT count(*) FROM events WHERE date >= '2026-01-01'),
      'total_attendance', (SELECT count(*) FROM attendance WHERE present = true),
      'active_members', (SELECT count(*) FROM members WHERE is_active AND current_cycle_active),
      'blog_posts', (SELECT count(*) FROM blog_posts),
      'change_requests', (SELECT count(*) FROM change_requests WHERE status != 'withdrawn'),
      'board_items', (SELECT count(*) FROM board_items WHERE status != 'archived'),
      'gamification_points', (SELECT count(*) FROM gamification_points),
      'growth_c2_c3', CASE WHEN v_c2_members > 0 THEN ROUND(((v_c3_members - v_c2_members)::numeric / v_c2_members) * 100) ELSE 0 END)
  ) INTO result;
  RETURN result;
END;
$$;
GRANT EXECUTE ON FUNCTION get_cycle_evolution() TO authenticated;
NOTIFY pgrst, 'reload schema';
