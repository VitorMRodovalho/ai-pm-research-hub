-- ════════════════════════════════════════════════════════════════
-- W134c: Dropout risk detection RPC
-- ════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION get_dropout_risk_members(
  p_threshold integer DEFAULT 3
) RETURNS TABLE(
  member_id uuid,
  member_name text,
  tribe_id integer,
  tribe_name text,
  operational_role text,
  last_attendance_date date,
  days_since_last bigint,
  missed_events integer
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  WITH active_members AS (
    SELECT m.id, m.name, m.tribe_id, t.name as tname, m.operational_role
    FROM members m
    LEFT JOIN tribes t ON t.id = m.tribe_id
    WHERE m.is_active AND m.operational_role IN ('researcher','tribe_leader','manager')
  ),
  member_expected_events AS (
    SELECT am.id as mid, e.id as eid, e.date,
      ROW_NUMBER() OVER (PARTITION BY am.id ORDER BY e.date DESC) as rn
    FROM active_members am
    CROSS JOIN LATERAL (
      SELECT e2.id, e2.date FROM events e2
      WHERE e2.date <= current_date
        AND (
          e2.type IN ('general_meeting','kickoff')
          OR (e2.type = 'tribe_meeting' AND e2.tribe_id = am.tribe_id)
          OR (e2.type = 'leadership_meeting' AND am.operational_role IN ('manager','tribe_leader'))
        )
      ORDER BY e2.date DESC
      LIMIT p_threshold
    ) e
  ),
  member_misses AS (
    SELECT mee.mid,
      count(*) FILTER (WHERE a.id IS NULL) as missed,
      count(*) as expected
    FROM member_expected_events mee
    LEFT JOIN attendance a ON a.event_id = mee.eid AND a.member_id = mee.mid AND a.present
    WHERE mee.rn <= p_threshold
    GROUP BY mee.mid
  ),
  last_att AS (
    SELECT a.member_id as mid, max(e.date) as last_date
    FROM attendance a JOIN events e ON e.id = a.event_id
    WHERE a.present
    GROUP BY a.member_id
  )
  SELECT am.id, am.name, am.tribe_id, am.tname, am.operational_role,
    la.last_date,
    (current_date - COALESCE(la.last_date, '2025-01-01'))::bigint,
    mm.missed::integer
  FROM active_members am
  JOIN member_misses mm ON mm.mid = am.id
  LEFT JOIN last_att la ON la.mid = am.id
  WHERE mm.missed >= p_threshold
  ORDER BY la.last_date ASC NULLS FIRST;
END;
$$;

GRANT EXECUTE ON FUNCTION get_dropout_risk_members(integer) TO authenticated;
