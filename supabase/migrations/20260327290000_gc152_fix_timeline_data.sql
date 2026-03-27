-- GC-152: Fix timeline data — correct tribes/chapters per cycle + Carlos Magno email
-- Root: Pilot had 0 tribes (conceptual only), C1 had 2 chapters (GO+CE not just GO),
-- C3 has 7 active tribes (not 8 — T3 inactivated)

-- Fix Carlos Magno email
UPDATE members SET email = 'magno@araguaia.net'
WHERE name ILIKE '%carlos magno%' AND email LIKE '%placeholder%';

-- Recreate get_cycle_evolution with correct data
DROP FUNCTION IF EXISTS get_cycle_evolution();
CREATE OR REPLACE FUNCTION get_cycle_evolution()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE result jsonb; v_c2_members int; v_c3_members int;
BEGIN
  SELECT count(DISTINCT member_id) INTO v_c2_members FROM member_cycle_history WHERE cycle_code = 'cycle_2';
  SELECT count(DISTINCT member_id) INTO v_c3_members FROM member_cycle_history WHERE cycle_code = 'cycle_3';
  SELECT jsonb_build_object(
    'cycles', jsonb_build_array(
      jsonb_build_object('cycle_code','pilot','cycle_label','Piloto 2024','members',8,
        'chapters',1,'tribes',0,
        'events',(SELECT count(*) FROM events WHERE date BETWEEN '2024-06-01' AND '2024-12-31' AND title ILIKE '%Núcleo%'),
        'growth',null),
      jsonb_build_object('cycle_code','cycle_1','cycle_label','Ciclo 1 (2025/1)',
        'members',(SELECT count(DISTINCT member_id) FROM member_cycle_history WHERE cycle_code='cycle_1'),
        'chapters',2,'tribes',5,
        'events',(SELECT count(*) FROM events WHERE date BETWEEN '2025-01-01' AND '2025-06-30'),
        'growth',ROUND(((SELECT count(DISTINCT member_id) FROM member_cycle_history WHERE cycle_code='cycle_1')-8.0)/8*100)),
      jsonb_build_object('cycle_code','cycle_2','cycle_label','Ciclo 2 (2025/2)',
        'members',v_c2_members,'chapters',2,'tribes',5,
        'events',(SELECT count(*) FROM events WHERE date BETWEEN '2025-07-01' AND '2025-12-31'),
        'growth',ROUND(((v_c2_members-(SELECT count(DISTINCT member_id) FROM member_cycle_history WHERE cycle_code='cycle_1')::numeric)/GREATEST((SELECT count(DISTINCT member_id) FROM member_cycle_history WHERE cycle_code='cycle_1'),1))*100)),
      jsonb_build_object('cycle_code','cycle_3','cycle_label','Ciclo 3 (2026/1)',
        'members',v_c3_members,'chapters',5,'tribes',7,
        'events',(SELECT count(*) FROM events WHERE date >= '2026-01-01'),
        'growth',CASE WHEN v_c2_members>0 THEN ROUND(((v_c3_members-v_c2_members)::numeric/v_c2_members)*100) ELSE 0 END)
    ),
    'highlights', jsonb_build_object(
      'new_chapters',3,'chapter_names','PMI-DF, PMI-MG, PMI-RS',
      'platform_version','v2.0.0','governance_digital',true,'mcp_server',true,
      'total_articles',(SELECT count(*) FROM publication_submissions),
      'total_events_c3',(SELECT count(*) FROM events WHERE date >= '2026-01-01'),
      'total_attendance',(SELECT count(*) FROM attendance WHERE present = true),
      'active_members',(SELECT count(*) FROM members WHERE is_active AND current_cycle_active),
      'blog_posts',(SELECT count(*) FROM blog_posts),
      'change_requests',(SELECT count(*) FROM change_requests WHERE status != 'withdrawn'),
      'board_items',(SELECT count(*) FROM board_items WHERE status != 'archived'),
      'gamification_points',(SELECT count(*) FROM gamification_points),
      'growth_c2_c3',CASE WHEN v_c2_members>0 THEN ROUND(((v_c3_members-v_c2_members)::numeric/v_c2_members)*100) ELSE 0 END)
  ) INTO result;
  RETURN result;
END;
$$;
GRANT EXECUTE ON FUNCTION get_cycle_evolution() TO authenticated;
NOTIFY pgrst, 'reload schema';
