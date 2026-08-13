-- #1710 — a TERCEIRA grade de presenca tambem publica `roster_sealed_at`.
--
-- `get_initiative_attendance_grid` aplica a mesma regra do #1657 (sem linha em evento nao selado e
-- 'unrecorded', nao falta) e, como as outras duas antes desta onda, nao dizia o que separa os dois
-- estados. Sem o carimbo, a tela de iniciativa exibe a consequencia do selo sem poder nomea-la.
--
-- Corpo derivado do vivo: a unica mudanca e a chave nova no payload de eventos.

CREATE OR REPLACE FUNCTION public.get_initiative_attendance_grid(p_initiative_id uuid, p_event_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_tribe_id int;
  v_cycle_start date;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  v_tribe_id := public.resolve_tribe_id(p_initiative_id);

  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_attendance_grid(v_tribe_id, p_event_type);
  END IF;

  -- D3: native (non-tribe) path had no scope check — any authenticated member could read any
  -- initiative's grid. Mirror get_tribe_attendance_grid: admin (manage_member) OR stakeholder
  -- (manage_partner) OR active engagement on the initiative.
  IF NOT public.can_by_member(v_caller.id, 'manage_member')
     AND NOT public.can_by_member(v_caller.id, 'view_partner')
     AND NOT EXISTS (
       SELECT 1 FROM engagements e
       WHERE e.person_id = v_caller.person_id
         AND e.initiative_id = p_initiative_id
         AND e.status = 'active'
     ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  WITH
  grid_events AS (
    SELECT e.id, e.date, e.title, e.type, e.status, e.roster_sealed_at,
           COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes,
           EXTRACT(WEEK FROM e.date)::int AS week_number
    FROM events e
    WHERE e.initiative_id = p_initiative_id
      AND e.date >= v_cycle_start
      AND (p_event_type IS NULL OR e.type = p_event_type)
    ORDER BY e.date
  ),
  grid_members AS (
    SELECT DISTINCT m.id, m.name, m.chapter, m.operational_role, m.designations, m.member_status
    FROM engagements eng
    JOIN members m ON m.person_id = eng.person_id
    WHERE eng.initiative_id = p_initiative_id AND eng.status = 'active'
    UNION
    SELECT DISTINCT m.id, m.name, m.chapter, m.operational_role, m.designations, m.member_status
    FROM members m
    JOIN attendance a ON a.member_id = m.id
    JOIN grid_events ge ON ge.id = a.event_id
  ),
  cell_status AS (
    SELECT
      gm.id AS member_id, ge.id AS event_id,
      CASE
        WHEN ge.status = 'cancelled' THEN 'na'
        WHEN ge.date > CURRENT_DATE THEN
          CASE WHEN gm.member_status != 'active' THEN 'na' ELSE 'scheduled' END
        WHEN a.id IS NOT NULL AND a.excused = true THEN 'excused'
        WHEN a.id IS NOT NULL AND a.present = true THEN 'present'
        WHEN a.id IS NOT NULL THEN 'absent'
        -- #1656: mesmo contrato do #1657 na grade de tribo (ver get_attendance_grid).
        -- Medido em 10/08: 33 celulas, 5 membros, 0 com linha real de falta.
        WHEN ge.roster_sealed_at IS NULL THEN 'unrecorded'
        ELSE 'absent'
      END AS status
    FROM grid_members gm
    CROSS JOIN grid_events ge
    LEFT JOIN attendance a ON a.member_id = gm.id AND a.event_id = ge.id
  ),
  member_stats AS (
    SELECT
      cs.member_id,
      COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'excused', 'unrecorded')) AS eligible_count,
      COUNT(*) FILTER (WHERE cs.status = 'present') AS present_count,
      COUNT(*) FILTER (WHERE cs.status = 'unrecorded') AS unrecorded_count,
      ROUND(
        COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'unrecorded')), 0), 2
      ) AS rate,
      ROUND(
        COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'unrecorded')), 0) * 100, 1
      ) AS rate_pct,
      ROUND(
        SUM(CASE WHEN cs.status = 'present' THEN ge.duration_minutes ELSE 0 END)::numeric / 60, 1
      ) AS hours
    FROM cell_status cs
    JOIN grid_events ge ON ge.id = cs.event_id
    GROUP BY cs.member_id
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT COUNT(DISTINCT id) FROM grid_members WHERE member_status = 'active'),
      'overall_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active'), 0),
      'overall_rate_pct', COALESCE((SELECT ROUND(AVG(ms.rate_pct), 1) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active'), 0),
      'unrecorded_cells', COALESCE((SELECT SUM(ms.unrecorded_count) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active'), 0),
      'total_events', (SELECT COUNT(*) FROM grid_events),
      'past_events', (SELECT COUNT(*) FROM grid_events WHERE date <= CURRENT_DATE),
      'cancelled_events', (SELECT COUNT(*) FROM grid_events WHERE status = 'cancelled'),
      'total_hours', COALESCE((SELECT ROUND(SUM(ms.hours), 1) FROM member_stats ms), 0)
    ),
    'events', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ge.id, 'date', ge.date, 'title', ge.title, 'type', ge.type,
      'status', ge.status,
      'duration_minutes', ge.duration_minutes, 'week_number', ge.week_number,
      'is_tribe_event', false,
      'is_future', (ge.date > CURRENT_DATE),
      'is_cancelled', (ge.status = 'cancelled'),
      -- #1710: a TERCEIRA grade tambem aplica a regra do #1657 (sem linha em evento nao selado e
      -- 'unrecorded') e tambem nao dizia por que. As tres publicam o mesmo carimbo.
      'roster_sealed_at', ge.roster_sealed_at
    ) ORDER BY ge.date), '[]'::jsonb) FROM grid_events ge),
    'members', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', gm.id, 'name', gm.name, 'chapter', gm.chapter,
        'member_status', gm.member_status,
        'rate', COALESCE(ms.rate, 0),
        'rate_pct', COALESCE(ms.rate_pct, 0),
        'hours', COALESCE(ms.hours, 0),
        'eligible_count', COALESCE(ms.eligible_count, 0),
        'present_count', COALESCE(ms.present_count, 0),
        'unrecorded_count', COALESCE(ms.unrecorded_count, 0),
        'detractor_status', 'regular',
        'consecutive_absences', 0,
        'attendance', (
          SELECT COALESCE(jsonb_object_agg(cs.event_id::text, cs.status), '{}'::jsonb)
          FROM cell_status cs WHERE cs.member_id = gm.id
        )
      ) ORDER BY COALESCE(ms.rate, 0) ASC), '[]'::jsonb)
      FROM grid_members gm
      LEFT JOIN member_stats ms ON ms.member_id = gm.id
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
