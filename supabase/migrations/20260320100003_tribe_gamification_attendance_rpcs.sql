-- ============================================================
-- P2-2 + P2-3: Tribe Dashboard Gamification + Attendance RPCs
-- Spec: docs/SPEC_TRIBE_DASHBOARD_GAMIFICATION_ATTENDANCE.md
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- RPC 1: get_tribe_gamification(p_tribe_id)
-- Returns: summary, members XP breakdown, tribe ranking, monthly trend
-- ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_tribe_gamification(p_tribe_id integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_caller record;
  v_result jsonb;
  v_summary jsonb;
  v_members jsonb;
  v_ranking jsonb;
  v_trend jsonb;
  v_total_xp bigint;
  v_member_count int;
BEGIN
  -- Auth: tribe_leader (own tribe), GP/admin (any tribe)
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF v_caller.is_superadmin IS NOT TRUE
     AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
     AND NOT (v_caller.operational_role = 'tribe_leader' AND v_caller.tribe_id = p_tribe_id)
     AND NOT (v_caller.designations && ARRAY['sponsor', 'chapter_liaison']) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- Member count
  SELECT count(*) INTO v_member_count FROM members WHERE tribe_id = p_tribe_id AND is_active = true;

  -- Members XP breakdown from gamification_leaderboard
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', gl.member_id,
    'name', gl.name,
    'total_points', gl.total_points,
    'cycle_points', gl.cycle_points,
    'attendance_points', gl.attendance_points,
    'cert_points', gl.cert_points,
    'badge_points', gl.badge_points,
    'learning_points', gl.learning_points,
    'credly_badge_count', COALESCE(jsonb_array_length(m.credly_badges), 0),
    'has_cpmai', COALESCE(m.cpmai_certified, false),
    'trail_progress', (
      SELECT count(*) FROM gamification_points gp
      WHERE gp.member_id = gl.member_id AND gp.category = 'trail'
    )
  ) ORDER BY gl.total_points DESC), '[]'::jsonb)
  INTO v_members
  FROM gamification_leaderboard gl
  JOIN members m ON m.id = gl.member_id
  WHERE m.tribe_id = p_tribe_id AND m.is_active = true;

  -- Total XP
  SELECT COALESCE(SUM((elem->>'total_points')::bigint), 0) INTO v_total_xp
  FROM jsonb_array_elements(v_members) elem;

  -- Summary
  v_summary := jsonb_build_object(
    'total_xp', v_total_xp,
    'avg_xp', CASE WHEN v_member_count > 0 THEN ROUND(v_total_xp::numeric / v_member_count) ELSE 0 END,
    'tribe_rank', (
      SELECT rk FROM (
        SELECT t.id, RANK() OVER (ORDER BY COALESCE(SUM(gl2.total_points), 0) DESC) AS rk
        FROM tribes t
        LEFT JOIN members m2 ON m2.tribe_id = t.id AND m2.is_active = true
        LEFT JOIN gamification_leaderboard gl2 ON gl2.member_id = m2.id
        WHERE t.is_active = true
        GROUP BY t.id
      ) ranked WHERE ranked.id = p_tribe_id
    ),
    'cert_coverage', CASE WHEN v_member_count > 0 THEN ROUND(
      (SELECT count(*) FROM members WHERE tribe_id = p_tribe_id AND is_active = true
       AND (cpmai_certified = true OR jsonb_array_length(COALESCE(credly_badges, '[]'::jsonb)) > 0)
      )::numeric / v_member_count, 2
    ) ELSE 0 END,
    'trail_completion', CASE WHEN v_member_count > 0 THEN ROUND(
      (SELECT count(DISTINCT gp.member_id) FROM gamification_points gp
       JOIN members m3 ON m3.id = gp.member_id
       WHERE m3.tribe_id = p_tribe_id AND m3.is_active = true AND gp.category = 'trail'
       GROUP BY gp.member_id HAVING count(*) >= 6
      )::numeric / v_member_count, 2
    ) ELSE 0 END
  );

  -- Tribe ranking (all tribes)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'tribe_id', t.id, 'tribe_name', t.name,
    'total_xp', COALESCE(SUM(gl3.total_points), 0)
  ) ORDER BY COALESCE(SUM(gl3.total_points), 0) DESC), '[]'::jsonb)
  INTO v_ranking
  FROM tribes t
  LEFT JOIN members m4 ON m4.tribe_id = t.id AND m4.is_active = true
  LEFT JOIN gamification_leaderboard gl3 ON gl3.member_id = m4.id
  WHERE t.is_active = true
  GROUP BY t.id, t.name;

  -- Monthly trend (XP by month for this tribe)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'month', to_char(month, 'YYYY-MM'),
    'xp', month_xp
  ) ORDER BY month), '[]'::jsonb)
  INTO v_trend
  FROM (
    SELECT date_trunc('month', gp.created_at) AS month, SUM(gp.points) AS month_xp
    FROM gamification_points gp
    JOIN members m5 ON m5.id = gp.member_id
    WHERE m5.tribe_id = p_tribe_id AND m5.is_active = true
      AND gp.created_at >= (SELECT cycle_start FROM cycles WHERE is_current = true LIMIT 1)
    GROUP BY date_trunc('month', gp.created_at)
  ) sub;

  RETURN jsonb_build_object(
    'summary', v_summary,
    'members', v_members,
    'tribe_ranking', v_ranking,
    'monthly_trend', v_trend
  );
END; $$;

-- ──────────────────────────────────────────────────────────────
-- RPC 2: get_tribe_attendance_grid(p_tribe_id, p_event_type)
-- Returns: summary, events, members with attendance map, tribe ranking
-- ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_tribe_attendance_grid(
  p_tribe_id integer,
  p_event_type text DEFAULT NULL  -- NULL=all, 'geral', 'tribe_meeting', 'leadership'
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_caller record;
  v_cycle_start date;
  v_events jsonb;
  v_members jsonb;
  v_summary jsonb;
  v_ranking jsonb;
BEGIN
  -- Auth
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF v_caller.is_superadmin IS NOT TRUE
     AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
     AND NOT (v_caller.operational_role = 'tribe_leader' AND v_caller.tribe_id = p_tribe_id)
     AND NOT (v_caller.designations && ARRAY['sponsor', 'chapter_liaison']) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  -- Events for the cycle
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', e.id, 'date', e.date, 'title', e.title, 'type', e.type,
    'is_tribe_event', (e.tribe_id = p_tribe_id),
    'is_leadership', (e.type = 'leadership' OR e.audience_level = 'leadership')
  ) ORDER BY e.date), '[]'::jsonb)
  INTO v_events
  FROM events e
  WHERE e.date >= v_cycle_start
    AND (p_event_type IS NULL OR e.type = p_event_type
         OR (p_event_type = 'tribe_meeting' AND e.tribe_id = p_tribe_id));

  -- Members with attendance map
  SELECT COALESCE(jsonb_agg(member_row ORDER BY (member_row->>'rate')::numeric ASC), '[]'::jsonb)
  INTO v_members
  FROM (
    SELECT jsonb_build_object(
      'id', m.id,
      'name', m.name,
      'attendance', (
        SELECT jsonb_object_agg(e.id::text,
          CASE
            -- Eligible?
            WHEN e.type IN ('general', 'geral', 'kickoff') THEN
              CASE WHEN EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id AND a.member_id = m.id) THEN 'present' ELSE 'absent' END
            WHEN e.tribe_id = p_tribe_id THEN
              CASE WHEN EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id AND a.member_id = m.id) THEN 'present' ELSE 'absent' END
            WHEN e.type = 'leadership' OR e.audience_level = 'leadership' THEN
              CASE WHEN m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader') OR m.designations && ARRAY['sponsor'] THEN
                CASE WHEN EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id AND a.member_id = m.id) THEN 'present' ELSE 'absent' END
              ELSE 'na' END
            ELSE 'na'
          END
        )
        FROM events e WHERE e.date >= v_cycle_start
          AND (p_event_type IS NULL OR e.type = p_event_type
               OR (p_event_type = 'tribe_meeting' AND e.tribe_id = p_tribe_id))
      ),
      'rate', ROUND(
        COALESCE(
          (SELECT count(*) FILTER (WHERE a_status = 'present')::numeric
           / NULLIF(count(*) FILTER (WHERE a_status IN ('present', 'absent')), 0)
           FROM (
             SELECT CASE
               WHEN e2.type IN ('general', 'geral', 'kickoff') THEN
                 CASE WHEN EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e2.id AND a.member_id = m.id) THEN 'present' ELSE 'absent' END
               WHEN e2.tribe_id = p_tribe_id THEN
                 CASE WHEN EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e2.id AND a.member_id = m.id) THEN 'present' ELSE 'absent' END
               WHEN e2.type = 'leadership' OR e2.audience_level = 'leadership' THEN
                 CASE WHEN m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader') OR m.designations && ARRAY['sponsor'] THEN
                   CASE WHEN EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e2.id AND a.member_id = m.id) THEN 'present' ELSE 'absent' END
                 ELSE 'na' END
               ELSE 'na'
             END AS a_status
             FROM events e2 WHERE e2.date >= v_cycle_start
               AND (p_event_type IS NULL OR e2.type = p_event_type
                    OR (p_event_type = 'tribe_meeting' AND e2.tribe_id = p_tribe_id))
           ) sub
          ), 0
        )::numeric, 2
      ),
      'eligible_count', (
        SELECT count(*) FILTER (WHERE a_status IN ('present', 'absent'))
        FROM (
          SELECT CASE
            WHEN e3.type IN ('general', 'geral', 'kickoff') THEN 'present'
            WHEN e3.tribe_id = p_tribe_id THEN 'present'
            WHEN (e3.type = 'leadership' OR e3.audience_level = 'leadership')
              AND (m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader') OR m.designations && ARRAY['sponsor']) THEN 'present'
            ELSE 'na'
          END AS a_status
          FROM events e3 WHERE e3.date >= v_cycle_start
        ) sub
      ),
      'present_count', (
        SELECT count(*) FROM attendance a
        JOIN events e4 ON e4.id = a.event_id
        WHERE a.member_id = m.id AND e4.date >= v_cycle_start
      )
    ) AS member_row
    FROM members m
    WHERE m.tribe_id = p_tribe_id AND m.is_active = true
      AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'guest', 'none')
  ) sub;

  -- Summary
  v_summary := jsonb_build_object(
    'overall_rate', COALESCE((SELECT ROUND(AVG((elem->>'rate')::numeric), 2) FROM jsonb_array_elements(v_members) elem), 0),
    'tribe_rank', (
      SELECT rk FROM (
        SELECT t.id, RANK() OVER (ORDER BY COALESCE(avg_rate, 0) DESC) AS rk
        FROM tribes t
        LEFT JOIN LATERAL (
          SELECT ROUND(AVG(
            CASE WHEN count_eligible > 0 THEN count_present::numeric / count_eligible ELSE 0 END
          ), 2) AS avg_rate
          FROM (
            SELECT m2.id,
              (SELECT count(*) FROM attendance a JOIN events e ON e.id = a.event_id WHERE a.member_id = m2.id AND e.date >= v_cycle_start) AS count_present,
              (SELECT count(*) FROM events e WHERE e.date >= v_cycle_start AND (e.type IN ('general', 'geral', 'kickoff') OR e.tribe_id = t.id)) AS count_eligible
            FROM members m2 WHERE m2.tribe_id = t.id AND m2.is_active = true
              AND m2.operational_role NOT IN ('sponsor', 'chapter_liaison', 'guest', 'none')
          ) sub
        ) lat ON true
        WHERE t.is_active = true
        GROUP BY t.id, lat.avg_rate
      ) ranked WHERE ranked.id = p_tribe_id
    ),
    'perfect_attendance', (SELECT count(*) FROM jsonb_array_elements(v_members) elem WHERE (elem->>'rate')::numeric >= 1.0),
    'below_50', (SELECT count(*) FROM jsonb_array_elements(v_members) elem WHERE (elem->>'rate')::numeric < 0.5 AND (elem->>'rate')::numeric > 0)
  );

  -- Tribe ranking by attendance
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'tribe_id', t.id, 'tribe_name', t.name, 'rate', COALESCE(lat.avg_rate, 0)
  ) ORDER BY COALESCE(lat.avg_rate, 0) DESC), '[]'::jsonb)
  INTO v_ranking
  FROM tribes t
  LEFT JOIN LATERAL (
    SELECT ROUND(AVG(
      CASE WHEN count_eligible > 0 THEN count_present::numeric / count_eligible ELSE 0 END
    ), 2) AS avg_rate
    FROM (
      SELECT m2.id,
        (SELECT count(*) FROM attendance a JOIN events e ON e.id = a.event_id WHERE a.member_id = m2.id AND e.date >= v_cycle_start) AS count_present,
        (SELECT count(*) FROM events e WHERE e.date >= v_cycle_start AND (e.type IN ('general', 'geral', 'kickoff') OR e.tribe_id = t.id)) AS count_eligible
      FROM members m2 WHERE m2.tribe_id = t.id AND m2.is_active = true
        AND m2.operational_role NOT IN ('sponsor', 'chapter_liaison', 'guest', 'none')
    ) sub
  ) lat ON true
  WHERE t.is_active = true;

  RETURN jsonb_build_object(
    'summary', v_summary,
    'events', v_events,
    'members', v_members,
    'tribe_ranking', v_ranking
  );
END; $$;
