-- ════════════════════════════════════════════════════════════════
-- W134a + W134b + W104: Attendance Registration, Dashboard & KPI
-- ════════════════════════════════════════════════════════════════

-- ── Site config entries ──
INSERT INTO site_config (key, value) VALUES
  ('attendance_risk_threshold', '3'),
  ('attendance_weight_geral', '0.4'),
  ('attendance_weight_tribo', '0.6'),
  ('kpi_pilot_count_override', '1')
ON CONFLICT (key) DO NOTHING;

-- ── W134a: Batch attendance registration ──
CREATE OR REPLACE FUNCTION register_attendance_batch(
  p_event_id uuid,
  p_member_ids uuid[],
  p_registered_by uuid
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  inserted integer;
BEGIN
  -- Verify caller is manager/superadmin/tribe_leader
  PERFORM 1 FROM members
  WHERE id = p_registered_by
    AND (is_superadmin = true OR operational_role IN ('manager','deputy_manager','tribe_leader'));
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unauthorized: only managers and tribe leaders can register attendance';
  END IF;

  INSERT INTO attendance (event_id, member_id, present, registered_by)
  SELECT p_event_id, unnest(p_member_ids), true, p_registered_by
  ON CONFLICT (event_id, member_id)
  DO UPDATE SET present = true, registered_by = p_registered_by, updated_at = now();
  GET DIAGNOSTICS inserted = ROW_COUNT;
  RETURN inserted;
END;
$$;

-- ── W134a: Update event actual duration ──
CREATE OR REPLACE FUNCTION update_event_duration(
  p_event_id uuid,
  p_duration_actual integer,
  p_updated_by uuid
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  PERFORM 1 FROM members
  WHERE id = p_updated_by
    AND (is_superadmin = true OR operational_role IN ('manager','deputy_manager','tribe_leader'));
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE events SET duration_actual = p_duration_actual WHERE id = p_event_id;
  RETURN true;
END;
$$;

-- ── W134a: Recent events for dropdown ──
CREATE OR REPLACE FUNCTION get_recent_events(
  p_days_back int DEFAULT 30,
  p_days_forward int DEFAULT 7
) RETURNS TABLE(
  id uuid, date date, type text, title text,
  tribe_id int, tribe_name text, headcount bigint,
  duration_minutes int, duration_actual int
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT e.id, e.date, e.type, e.title, e.tribe_id, t.name as tribe_name,
    (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present) as headcount,
    e.duration_minutes, e.duration_actual
  FROM events e
  LEFT JOIN tribes t ON t.id = e.tribe_id
  WHERE e.date BETWEEN current_date - p_days_back AND current_date + p_days_forward
  ORDER BY e.date DESC;
END;
$$;

-- ── W134b: Attendance summary dashboard ──
CREATE OR REPLACE FUNCTION get_attendance_summary(
  p_cycle_start date DEFAULT '2026-03-01',
  p_cycle_end date DEFAULT '2026-08-31',
  p_tribe_id integer DEFAULT NULL
) RETURNS TABLE(
  member_id uuid,
  member_name text,
  tribe_id integer,
  tribe_name text,
  operational_role text,
  geral_present bigint,
  geral_total bigint,
  geral_pct numeric,
  tribe_present bigint,
  tribe_total bigint,
  tribe_pct numeric,
  combined_pct numeric,
  last_attendance date,
  consecutive_misses integer
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  WITH cycle_gerals AS (
    SELECT count(*) as cnt FROM events
    WHERE type = 'general_meeting' AND date BETWEEN p_cycle_start AND p_cycle_end
  ),
  cycle_tribe_meetings AS (
    SELECT e.tribe_id as tid, count(*) as cnt FROM events e
    WHERE e.type = 'tribe_meeting' AND e.date BETWEEN p_cycle_start AND p_cycle_end
    GROUP BY e.tribe_id
  ),
  member_gerals AS (
    SELECT a.member_id as mid, count(*) as cnt
    FROM attendance a JOIN events e ON e.id = a.event_id
    WHERE a.present AND e.type = 'general_meeting' AND e.date BETWEEN p_cycle_start AND p_cycle_end
    GROUP BY a.member_id
  ),
  member_tribes AS (
    SELECT a.member_id as mid, count(*) as cnt
    FROM attendance a JOIN events e ON e.id = a.event_id
    WHERE a.present AND e.type = 'tribe_meeting' AND e.date BETWEEN p_cycle_start AND p_cycle_end
    GROUP BY a.member_id
  ),
  last_att AS (
    SELECT a.member_id as mid, max(e.date) as last_date
    FROM attendance a JOIN events e ON e.id = a.event_id
    WHERE a.present
    GROUP BY a.member_id
  )
  SELECT m.id, m.name, m.tribe_id, t.name,
    m.operational_role,
    COALESCE(mg.cnt, 0)::bigint,
    (SELECT cnt FROM cycle_gerals)::bigint,
    CASE WHEN (SELECT cnt FROM cycle_gerals) > 0
      THEN round(COALESCE(mg.cnt, 0)::numeric / (SELECT cnt FROM cycle_gerals) * 100, 1)
      ELSE 0 END,
    COALESCE(mt.cnt, 0)::bigint,
    COALESCE(ctm.cnt, 0)::bigint,
    CASE WHEN COALESCE(ctm.cnt, 0) > 0
      THEN round(COALESCE(mt.cnt, 0)::numeric / ctm.cnt * 100, 1)
      ELSE 0 END,
    round(
      0.4 * CASE WHEN (SELECT cnt FROM cycle_gerals) > 0
        THEN COALESCE(mg.cnt, 0)::numeric / (SELECT cnt FROM cycle_gerals) * 100 ELSE 0 END
      + 0.6 * CASE WHEN COALESCE(ctm.cnt, 0) > 0
        THEN COALESCE(mt.cnt, 0)::numeric / ctm.cnt * 100 ELSE 0 END
    , 1),
    la.last_date,
    0 -- consecutive_misses calculated in app layer
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

-- ── W104: KPI Dashboard ──
CREATE OR REPLACE FUNCTION get_kpi_dashboard(
  p_cycle_start date DEFAULT '2026-03-01',
  p_cycle_end date DEFAULT '2026-08-31'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  result jsonb;
  days_elapsed numeric;
  days_total numeric;
  linear_pct numeric;
BEGIN
  days_elapsed := GREATEST(current_date - p_cycle_start, 0);
  days_total := p_cycle_end - p_cycle_start;
  linear_pct := CASE WHEN days_total > 0 THEN round(days_elapsed / days_total * 100, 1) ELSE 0 END;

  SELECT jsonb_build_object(
    'cycle_pct', linear_pct,
    'kpis', jsonb_build_array(
      -- 1. Impact hours
      jsonb_build_object(
        'name', 'Horas de Impacto',
        'current', COALESCE((
          SELECT round(sum(
            COALESCE(e.duration_actual, e.duration_minutes, 60)::numeric
            * (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present)
          ) / 60)
          FROM events e WHERE e.date BETWEEN p_cycle_start AND p_cycle_end
        ), 0),
        'target', 1800,
        'unit', 'h',
        'icon', 'clock'
      ),
      -- 2. Certifications CPMAI
      jsonb_build_object(
        'name', 'Certificação CPMAI',
        'current', (
          SELECT count(*) FROM members
          WHERE is_active AND cpmai_certified = true
        ),
        'target', (SELECT GREATEST(round(count(*) * 0.7), 1) FROM members WHERE is_active AND operational_role IN ('researcher','tribe_leader','manager')),
        'unit', 'membros',
        'icon', 'award'
      ),
      -- 3. Pilots
      jsonb_build_object(
        'name', 'Pilotos de IA',
        'current', COALESCE((SELECT (value)::int FROM site_config WHERE key = 'kpi_pilot_count_override'), 0),
        'target', 3,
        'unit', '',
        'icon', 'rocket'
      ),
      -- 4. Articles
      jsonb_build_object(
        'name', 'Artigos Publicados',
        'current', (
          SELECT count(*) FROM board_items bi
          JOIN project_boards pb ON pb.id = bi.board_id
          WHERE pb.board_name ILIKE '%publica%' AND bi.status IN ('done','published')
        ),
        'target', 10,
        'unit', '',
        'icon', 'file-text'
      ),
      -- 5. Webinars
      jsonb_build_object(
        'name', 'Webinars Realizados',
        'current', (SELECT count(*) FROM events WHERE type = 'webinar' AND date BETWEEN p_cycle_start AND p_cycle_end),
        'target', 6,
        'unit', '',
        'icon', 'video'
      ),
      -- 6. Chapters
      jsonb_build_object(
        'name', 'Capítulos Integrados',
        'current', (SELECT count(DISTINCT chapter) FROM members WHERE is_active AND chapter IS NOT NULL),
        'target', 8,
        'unit', '',
        'icon', 'map-pin'
      )
    )
  ) INTO result;
  RETURN result;
END;
$$;

-- ── Grant execute to authenticated ──
GRANT EXECUTE ON FUNCTION register_attendance_batch(uuid, uuid[], uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION update_event_duration(uuid, integer, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_recent_events(int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION get_attendance_summary(date, date, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION get_kpi_dashboard(date, date) TO authenticated;
