-- p276 — Bucket A: LGPD / authorization hardening (metric-disparity audit 2026-05-28)
--
-- WHAT: Close four SECURITY DEFINER exposures surfaced by the cross-surface audit.
--   D1  get_public_leaderboard / get_public_trail_ranking  — honor gamification_opt_out on the
--       anon/public surface (ADR-0050). These RPCs are GRANT EXECUTE to anon and were the only
--       leaderboard variants that ignored the member's "hide me" consent toggle.
--   D2  get_attendance_panel  — SECDEF + anon-granted leaked org-wide attendance % + dropout_risk
--       flag + behavioral typology to UNAUTHENTICATED callers. Now requires an active member and
--       masks dropout_risk/typology (HR-adjacent signals) to all but leadership (manage_event) and
--       the caller's own row. The combined_pct ranking itself is preserved (no behavior change for
--       the Home hero self-row nor the Attendance Ranking tab).
--   D3  get_global_research_pipeline  — SECDEF, no in-body auth, leaked author PII via direct RPC
--       (client guard only). Gated to GP leadership (manage_platform), matching the
--       ResearchPipelineWidget audience (superadmin / manager / deputy_manager).
--   D3  get_initiative_attendance_grid (native path)  — had no scope check; any authenticated
--       member could read any non-tribe initiative's grid. Now mirrors get_tribe_attendance_grid:
--       admin (manage_member) OR stakeholder (manage_partner) OR active engagement on the initiative.
--   XP  get_member_cycle_xp  — SECDEF + authenticated-grant let any caller read ANY member's XP/rank
--       by passing an arbitrary p_member_id. Gated self-or-privileged (view_pii).
--
-- WHY: LGPD Art. 18 consent (opt-out) + GC-162 (no PII via ungated SECDEF) + least-privilege.
--      Client-side React/Astro guards are not an access boundary against direct PostgREST RPC calls.
--
-- ROLLBACK: re-apply the prior bodies (pre-p276). All changes are same-signature CREATE OR REPLACE
--      (no DROP, no consumer break). Reverting reopens the exposures.
--
-- NOTE: gamification_opt_out is NOT NULL DEFAULT false, so `= false` is total and matches the
--      reference get_gamification_leaderboard predicate verbatim (consistency is the point).

-- ───────────────────────────────────────────────────────────────────────────
-- D1a — get_public_leaderboard: honor LGPD opt-out on the anon/public surface
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_public_leaderboard(p_limit integer DEFAULT 50)
 RETURNS TABLE(rank_position integer, member_name text, chapter text, tribe_name text, xp_total bigint, level_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH xp AS (
    SELECT gp.member_id, SUM(gp.points) as total
    FROM gamification_points gp
    GROUP BY gp.member_id
  )
  SELECT
    ROW_NUMBER() OVER (ORDER BY COALESCE(xp.total, 0) DESC)::int as rank_position,
    m.name as member_name,
    m.chapter,
    t.name as tribe_name,
    COALESCE(xp.total, 0) as xp_total,
    CASE
      WHEN COALESCE(xp.total, 0) >= 401 THEN 'Lenda'
      WHEN COALESCE(xp.total, 0) >= 201 THEN 'Mestre'
      WHEN COALESCE(xp.total, 0) >= 91 THEN 'Especialista'
      WHEN COALESCE(xp.total, 0) >= 31 THEN 'Praticante'
      ELSE 'Explorador'
    END as level_name
  FROM members m
  LEFT JOIN xp ON xp.member_id = m.id
  LEFT JOIN tribes t ON t.id = m.tribe_id
  WHERE m.is_active = true AND m.current_cycle_active = true
    AND m.gamification_opt_out = false
  ORDER BY COALESCE(xp.total, 0) DESC
  LIMIT p_limit;
$function$;

-- ───────────────────────────────────────────────────────────────────────────
-- D1b — get_public_trail_ranking: honor LGPD opt-out on the anon/public surface
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_public_trail_ranking()
 RETURNS TABLE(member_name text, photo_url text, completed integer, in_progress integer, pct integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH trail_courses AS (
    SELECT id FROM courses WHERE is_trail = true
  ),
  trail_total AS (
    SELECT count(*)::int AS cnt FROM trail_courses
  ),
  eligible_members AS (
    SELECT DISTINCT m.id, m.name, m.photo_url
    FROM members m
    WHERE m.is_active AND m.current_cycle_active
      AND m.gamification_opt_out = false
      AND (
        m.tribe_id IS NOT NULL
        OR EXISTS(
          SELECT 1 FROM engagements e
          WHERE e.person_id = m.person_id AND e.status = 'active'
            AND e.role IN ('leader', 'coordinator', 'manager', 'participant')
        )
      )
  ),
  progress AS (
    SELECT cp.member_id, cp.status
    FROM course_progress cp
    JOIN trail_courses tc ON tc.id = cp.course_id
  ),
  member_stats AS (
    SELECT
      p.member_id,
      COUNT(*) FILTER (WHERE p.status = 'completed') AS completed,
      COUNT(*) FILTER (WHERE p.status = 'in_progress') AS in_progress
    FROM progress p
    GROUP BY p.member_id
  )
  SELECT
    em.name,
    em.photo_url,
    COALESCE(ms.completed, 0)::int,
    COALESCE(ms.in_progress, 0)::int,
    CASE WHEN tt.cnt > 0 THEN ROUND(COALESCE(ms.completed, 0)::numeric / tt.cnt * 100)::int ELSE 0 END
  FROM eligible_members em
  CROSS JOIN trail_total tt
  LEFT JOIN member_stats ms ON ms.member_id = em.id
  ORDER BY COALESCE(ms.completed, 0) DESC, COALESCE(ms.in_progress, 0) DESC, em.name;
$function$;

-- ───────────────────────────────────────────────────────────────────────────
-- D2 — get_attendance_panel: require auth (no anon) + mask dropout_risk/typology
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_attendance_panel(p_cycle_start date DEFAULT '2026-01-01'::date, p_cycle_end date DEFAULT '2026-06-30'::date)
 RETURNS TABLE(member_id uuid, member_name text, tribe_name text, tribe_id integer, operational_role text, general_mandatory integer, general_attended integer, general_pct numeric, tribe_mandatory integer, tribe_attended integer, tribe_pct numeric, combined_pct numeric, last_attendance date, dropout_risk boolean, typology text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_privileged boolean := false;
BEGIN
  -- D2 gate: this RPC is GRANT EXECUTE to anon and has no in-body auth. Require an active member.
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_id IS NULL THEN
    RETURN; -- anon / ghost / inactive: no rows
  END IF;
  -- Leadership (tribe leaders + GP) may see dropout_risk/typology for everyone; others only for self.
  v_privileged := public.can_by_member(v_caller_id, 'manage_event');

  RETURN QUERY
  WITH general_events AS (
    SELECT DISTINCT e.id as event_id, e.date::date as event_date
    FROM public.events e JOIN public.event_tag_assignments eta ON eta.event_id = e.id
    JOIN public.tags t ON t.id = eta.tag_id AND t.name = 'general_meeting'
    WHERE e.date::date BETWEEN p_cycle_start AND LEAST(p_cycle_end, CURRENT_DATE)
      AND (e.status IS NULL OR e.status != 'cancelled')
  ),
  tribe_events AS (
    SELECT DISTINCT e.id as event_id, e.date::date as event_date
    FROM public.events e JOIN public.event_tag_assignments eta ON eta.event_id = e.id
    JOIN public.tags t ON t.id = eta.tag_id AND t.name = 'tribe_meeting'
    WHERE e.date::date BETWEEN p_cycle_start AND LEAST(p_cycle_end, CURRENT_DATE)
      AND (e.status IS NULL OR e.status != 'cancelled')
  ),
  active AS (
    SELECT m.id, m.name as m_name, tr.name as t_name, m.tribe_id as t_id,
           m.operational_role as op_role, m.created_at::date as member_start,
           (m.designations IS NOT NULL AND m.designations @> ARRAY['curator']::text[]) AS is_curator
    FROM public.members m LEFT JOIN public.tribes tr ON tr.id = m.tribe_id
    WHERE m.is_active = true
  ),
  gscores AS (
    SELECT a.id as mid,
      count(*) FILTER (WHERE ge.event_date >= a.member_start AND public.is_event_mandatory_for_member(ge.event_id, a.id)) as mand,
      count(*) FILTER (WHERE ge.event_date >= a.member_start AND att.id IS NOT NULL AND public.is_event_mandatory_for_member(ge.event_id, a.id)) as att
    FROM active a CROSS JOIN general_events ge
    LEFT JOIN public.attendance att ON att.event_id = ge.event_id AND att.member_id = a.id AND att.present = true
    GROUP BY a.id
  ),
  tscores AS (
    SELECT a.id as mid,
      count(*) FILTER (WHERE te.event_date >= a.member_start AND public.is_event_mandatory_for_member(te.event_id, a.id)) as mand,
      count(*) FILTER (WHERE te.event_date >= a.member_start AND att.id IS NOT NULL AND public.is_event_mandatory_for_member(te.event_id, a.id)) as att
    FROM active a CROSS JOIN tribe_events te
    LEFT JOIN public.attendance att ON att.event_id = te.event_id AND att.member_id = a.id AND att.present = true
    GROUP BY a.id
  ),
  last_att AS (
    SELECT a.member_id, MAX(e.date::date) as last_date
    FROM public.attendance a JOIN public.events e ON e.id = a.event_id
    WHERE a.present = true GROUP BY a.member_id
  ),
  computed AS (
    SELECT a.id, a.m_name, a.t_name, a.t_id, a.op_role, a.is_curator,
      COALESCE(gs.mand,0) AS g_mand, COALESCE(gs.att,0) AS g_att,
      CASE WHEN COALESCE(gs.mand,0)>0 THEN ROUND(gs.att::numeric/gs.mand*100,1) ELSE 0 END AS g_pct,
      COALESCE(ts.mand,0) AS t_mand, COALESCE(ts.att,0) AS t_att,
      CASE WHEN COALESCE(ts.mand,0)>0 THEN ROUND(ts.att::numeric/ts.mand*100,1) ELSE 0 END AS t_pct,
      CASE WHEN COALESCE(gs.mand,0)+COALESCE(ts.mand,0)>0
        THEN ROUND((COALESCE(gs.att,0)+COALESCE(ts.att,0))::numeric/(COALESCE(gs.mand,0)+COALESCE(ts.mand,0))*100,1)
        ELSE 0 END AS c_pct,
      la.last_date
    FROM active a
    LEFT JOIN gscores gs ON gs.mid = a.id
    LEFT JOIN tscores ts ON ts.mid = a.id
    LEFT JOIN last_att la ON la.member_id = a.id
  )
  SELECT c.id, c.m_name, c.t_name, c.t_id, c.op_role,
    c.g_mand::int, c.g_att::int, c.g_pct, c.t_mand::int, c.t_att::int, c.t_pct,
    c.c_pct, c.last_date,
    CASE WHEN v_privileged OR c.id = v_caller_id
      THEN (NOT c.is_curator AND (c.g_mand + c.t_mand) > 0 AND c.c_pct < 50)
      ELSE NULL END AS dropout_risk,
    CASE WHEN v_privileged OR c.id = v_caller_id THEN
      CASE
        WHEN c.is_curator                               THEN 'curator'
        WHEN c.g_mand + c.t_mand = 0                    THEN 'no-data'
        WHEN c.c_pct >= 70                              THEN 'healthy'
        WHEN c.c_pct >= 50                              THEN 'borderline'
        WHEN c.g_pct < 30 AND c.t_pct >= 50             THEN 'missing-general'
        WHEN c.t_pct < 30 AND c.g_pct >= 50             THEN 'missing-tribe'
        WHEN c.c_pct < 30                               THEN 'missing-both'
        ELSE 'balanced-low'
      END
      ELSE NULL END AS typology
  FROM computed c
  ORDER BY c.m_name;
END;
$function$;

-- ───────────────────────────────────────────────────────────────────────────
-- D3a — get_global_research_pipeline: gate to GP leadership (manage_platform)
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_global_research_pipeline()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid() AND is_active = true;
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  RETURN (SELECT json_build_object(
    'in_progress', (
      SELECT coalesce(json_agg(row_to_json(r)), '[]')
      FROM (
        SELECT bi.id, bi.title, bi.status, bi.due_date, bi.updated_at,
          pb.board_name, i.legacy_tribe_id AS tribe_id,
          i.title as tribe_name,
          (SELECT string_agg(m.name, ', ') FROM board_item_assignments bia JOIN members m ON m.id = bia.member_id WHERE bia.item_id = bi.id AND bia.role = 'author') as authors
        FROM board_items bi
        JOIN project_boards pb ON pb.id = bi.board_id
        LEFT JOIN initiatives i ON i.id = pb.initiative_id
        WHERE pb.domain_key = 'research_delivery' AND bi.status IN ('in_progress', 'review')
        ORDER BY bi.updated_at DESC
      ) r
    ),
    'recently_done', (
      SELECT coalesce(json_agg(row_to_json(r)), '[]')
      FROM (
        SELECT bi.id, bi.title, bi.updated_at,
          i.legacy_tribe_id AS tribe_id,
          i.title as tribe_name
        FROM board_items bi
        JOIN project_boards pb ON pb.id = bi.board_id
        LEFT JOIN initiatives i ON i.id = pb.initiative_id
        WHERE pb.domain_key = 'research_delivery' AND bi.status = 'done'
        ORDER BY bi.updated_at DESC LIMIT 5
      ) r
    ),
    'summary', (
      SELECT json_object_agg(status, cnt)
      FROM (SELECT bi.status, count(*) as cnt FROM board_items bi JOIN project_boards pb ON pb.id = bi.board_id WHERE pb.domain_key = 'research_delivery' AND bi.status NOT IN ('archived') GROUP BY bi.status) s
    )
  ));
END;
$function$;

-- ───────────────────────────────────────────────────────────────────────────
-- D3b — get_initiative_attendance_grid: add scope check to the native (non-tribe) path
-- ───────────────────────────────────────────────────────────────────────────
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
     AND NOT public.can_by_member(v_caller.id, 'manage_partner')
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
    SELECT e.id, e.date, e.title, e.type, e.status,
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
        ELSE 'absent'
      END AS status
    FROM grid_members gm
    CROSS JOIN grid_events ge
    LEFT JOIN attendance a ON a.member_id = gm.id AND a.event_id = ge.id
  ),
  member_stats AS (
    SELECT
      cs.member_id,
      COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'excused')) AS eligible_count,
      COUNT(*) FILTER (WHERE cs.status = 'present') AS present_count,
      ROUND(
        COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent')), 0), 2
      ) AS rate,
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
      'is_cancelled', (ge.status = 'cancelled')
    ) ORDER BY ge.date), '[]'::jsonb) FROM grid_events ge),
    'members', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', gm.id, 'name', gm.name, 'chapter', gm.chapter,
        'member_status', gm.member_status,
        'rate', COALESCE(ms.rate, 0),
        'hours', COALESCE(ms.hours, 0),
        'eligible_count', COALESCE(ms.eligible_count, 0),
        'present_count', COALESCE(ms.present_count, 0),
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

-- ───────────────────────────────────────────────────────────────────────────
-- XP — get_member_cycle_xp: gate self-or-privileged (view_pii)
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_member_cycle_xp(p_member_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  cycle_start_date date;
  v_rank int;
  v_total int;
  result json;
  v_caller_id uuid;
begin
  -- XP gate: SECDEF + authenticated-grant allowed enumerating any member's XP/rank by id.
  select id into v_caller_id from public.members where auth_id = auth.uid() and is_active = true;
  if v_caller_id is null then
    raise exception 'Not authenticated' using errcode = 'insufficient_privilege';
  end if;
  if p_member_id <> v_caller_id and not public.can_by_member(v_caller_id, 'view_pii') then
    raise exception 'Unauthorized' using errcode = 'insufficient_privilege';
  end if;

  select cycle_start into cycle_start_date
  from public.cycles where is_current = true limit 1;

  if cycle_start_date is null then
    cycle_start_date := '2026-01-01';
  end if;

  WITH ranked AS (
    SELECT member_id, COALESCE(SUM(points), 0) as total_pts,
           ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(points), 0) DESC) as pos
    FROM public.gamification_points
    GROUP BY member_id
  )
  SELECT pos, (SELECT COUNT(DISTINCT member_id) FROM public.gamification_points)
  INTO v_rank, v_total
  FROM ranked WHERE member_id = p_member_id;

  select json_build_object(
    'lifetime_points', coalesce(sum(points), 0)::int,
    'cycle_points', coalesce(sum(points) filter (where created_at >= cycle_start_date), 0)::int,
    'cycle_attendance', coalesce(sum(points) filter (where category = 'attendance' and created_at >= cycle_start_date), 0)::int,
    'cycle_learning', coalesce(sum(points) filter (where category in ('trail', 'course', 'knowledge_ai_pm') and created_at >= cycle_start_date), 0)::int,
    'cycle_certs', coalesce(sum(points) filter (where category in ('cert_pmi_senior', 'cert_cpmai', 'cert_pmi_mid', 'cert_pmi_practitioner', 'cert_pmi_entry') and created_at >= cycle_start_date), 0)::int,
    'cycle_courses', coalesce(sum(points) filter (where category in ('trail', 'course', 'knowledge_ai_pm') and created_at >= cycle_start_date), 0)::int,
    'cycle_artifacts', coalesce(sum(points) filter (where category = 'artifact' and created_at >= cycle_start_date), 0)::int,
    'cycle_showcase', coalesce(sum(points) filter (where category = 'showcase' and created_at >= cycle_start_date), 0)::int,
    'cycle_bonus', coalesce(sum(points) filter (where category not in ('attendance','trail','course','knowledge_ai_pm','cert_pmi_senior','cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry','artifact','badge','specialization','showcase') and created_at >= cycle_start_date), 0)::int,
    'cycle_code', (select cycle_code from public.cycles where is_current = true limit 1),
    'cycle_label', (select cycle_label from public.cycles where is_current = true limit 1),
    'rank_position', coalesce(v_rank, 0),
    'total_ranked', coalesce(v_total, 0)
  ) into result
  from public.gamification_points
  where member_id = p_member_id;

  return coalesce(result, '{}');
end;
$function$;

NOTIFY pgrst, 'reload schema';
