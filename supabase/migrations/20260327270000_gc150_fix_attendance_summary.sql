-- GC-150: Fix get_attendance_summary — wrong event types + wrong date range
-- Root cause: used 'general_meeting'/'tribe_meeting' but actual types are 'geral'/'tribo'
-- Also: default dates were 2026-03-01 but C3 starts 2026-01-01 (2 months of data excluded)

CREATE OR REPLACE FUNCTION get_attendance_summary(
  p_cycle_start date DEFAULT '2026-01-01',
  p_cycle_end date DEFAULT '2026-06-30',
  p_tribe_id integer DEFAULT NULL
) RETURNS TABLE(
  member_id uuid, member_name text, tribe_id integer, tribe_name text,
  operational_role text, geral_present bigint, geral_total bigint, geral_pct numeric,
  tribe_present bigint, tribe_total bigint, tribe_pct numeric, combined_pct numeric,
  last_attendance date, consecutive_misses integer
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
BEGIN
  RETURN QUERY
  WITH cycle_gerals AS (
    SELECT count(*) as cnt FROM events WHERE type = 'geral' AND date BETWEEN p_cycle_start AND p_cycle_end
  ),
  cycle_tribe_meetings AS (
    SELECT e.tribe_id as tid, count(*) as cnt FROM events e
    WHERE e.type = 'tribo' AND e.date BETWEEN p_cycle_start AND p_cycle_end
    GROUP BY e.tribe_id
  ),
  member_gerals AS (
    SELECT a.member_id as mid, count(*) as cnt
    FROM attendance a JOIN events e ON e.id = a.event_id
    WHERE a.present AND e.type = 'geral' AND e.date BETWEEN p_cycle_start AND p_cycle_end
    GROUP BY a.member_id
  ),
  member_tribes AS (
    SELECT a.member_id as mid, count(*) as cnt
    FROM attendance a JOIN events e ON e.id = a.event_id
    WHERE a.present AND e.type = 'tribo' AND e.date BETWEEN p_cycle_start AND p_cycle_end
    GROUP BY a.member_id
  ),
  last_att AS (
    SELECT a.member_id as mid, max(e.date) as last_date
    FROM attendance a JOIN events e ON e.id = a.event_id WHERE a.present GROUP BY a.member_id
  )
  SELECT m.id, m.name, m.tribe_id, t.name, m.operational_role,
    COALESCE(mg.cnt, 0)::bigint,
    (SELECT cnt FROM cycle_gerals)::bigint,
    CASE WHEN (SELECT cnt FROM cycle_gerals) > 0
      THEN round(COALESCE(mg.cnt, 0)::numeric / (SELECT cnt FROM cycle_gerals) * 100, 1) ELSE 0 END,
    COALESCE(mt.cnt, 0)::bigint,
    COALESCE(ctm.cnt, 0)::bigint,
    CASE WHEN COALESCE(ctm.cnt, 0) > 0
      THEN round(COALESCE(mt.cnt, 0)::numeric / ctm.cnt * 100, 1) ELSE 0 END,
    round(
      0.4 * CASE WHEN (SELECT cnt FROM cycle_gerals) > 0
        THEN COALESCE(mg.cnt, 0)::numeric / (SELECT cnt FROM cycle_gerals) * 100 ELSE 0 END
      + 0.6 * CASE WHEN COALESCE(ctm.cnt, 0) > 0
        THEN COALESCE(mt.cnt, 0)::numeric / ctm.cnt * 100 ELSE 0 END
    , 1),
    la.last_date, 0
  FROM members m
  LEFT JOIN tribes t ON t.id = m.tribe_id
  LEFT JOIN member_gerals mg ON mg.mid = m.id
  LEFT JOIN member_tribes mt ON mt.mid = m.id
  LEFT JOIN cycle_tribe_meetings ctm ON ctm.tid = m.tribe_id
  LEFT JOIN last_att la ON la.mid = m.id
  WHERE m.is_active = true
    AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'guest', 'none')
    AND (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
  ORDER BY combined_pct ASC NULLS FIRST;
END;
$$;

GRANT EXECUTE ON FUNCTION get_attendance_summary(date, date, integer) TO authenticated;

-- Also fix exec_cycle_report date range (C3 = Jan-Jun 2026)
-- Already fixed via execute_sql earlier in this session

NOTIFY pgrst, 'reload schema';
