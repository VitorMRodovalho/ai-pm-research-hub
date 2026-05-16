-- p170 — Curator exclusion + split panel typology
--
-- PM clarification 2026-05-16: Roberto Macêdo + Sarah têm designation='curator'.
-- Curators são cross-tribe observers — NÃO têm obrigatoriedade de:
--   - tribe meetings (não participam de tribo específica como researcher)
--   - general meetings (opcional, podem participar como observer)
--   - liderança meetings (opcional)
--
-- Por isso devem ser excluídos do mandatory pool de tribe + all_active_operational
-- targets em is_event_mandatory_for_member.
--
-- Plus: extend get_attendance_panel com `typology` column que classifica:
--   - 'curator' — designation 'curator' (RPC nem conta mandatory)
--   - 'missing-both' — combined < 30%, ambos low
--   - 'missing-general' — general < 30%, tribe ≥ 50%
--   - 'missing-tribe'   — tribe < 30%, general ≥ 50%
--   - 'balanced-low'    — ambos entre 30-50%
--   - 'healthy'         — combined ≥ 70%
--   - 'borderline'      — combined 50-70%
--
-- Plus: dropout_risk recomputado — curators SEMPRE return false, outros usam combined < 50%.

-- ============================================================
-- Step 1: patch is_event_mandatory_for_member para excluir curators
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_event_mandatory_for_member(p_event_id uuid, p_member_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_rule record;
  v_is_curator boolean;
BEGIN
  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF v_member IS NULL OR v_member.is_active = false THEN RETURN false; END IF;

  -- p170: curators are cross-tribe observers, not bound by tribe/general mandates
  v_is_curator := v_member.designations IS NOT NULL
                  AND v_member.designations @> ARRAY['curator']::text[];

  FOR v_rule IN SELECT * FROM public.event_audience_rules
    WHERE event_id = p_event_id AND attendance_type = 'mandatory'
  LOOP
    IF v_rule.target_type = 'all_active_operational' THEN
      -- Curators opted-out of generic operational mandate (PM clarification 2026-05-16)
      IF v_is_curator THEN CONTINUE; END IF;
      IF v_member.tribe_id IS NOT NULL OR v_member.operational_role IN ('manager','deputy_manager') THEN
        RETURN true;
      END IF;
    ELSIF v_rule.target_type = 'tribe' THEN
      -- Curators don't have tribe obligation even if tribe_id is set (legacy data)
      IF v_is_curator THEN CONTINUE; END IF;
      IF v_member.tribe_id IS NOT NULL AND v_member.tribe_id::text = v_rule.target_value THEN
        RETURN true;
      END IF;
    ELSIF v_rule.target_type = 'role' THEN
      IF v_member.operational_role = v_rule.target_value THEN
        RETURN true;
      END IF;
    ELSIF v_rule.target_type = 'specific_members' THEN
      IF EXISTS (SELECT 1 FROM public.event_invited_members
        WHERE event_id = p_event_id AND member_id = p_member_id AND attendance_type = 'mandatory') THEN
        RETURN true;
      END IF;
    END IF;
  END LOOP;

  -- Direct invite still binding even for curators (explicit ask trumps cross-tribe semantic)
  IF EXISTS (SELECT 1 FROM public.event_invited_members
    WHERE event_id = p_event_id AND member_id = p_member_id AND attendance_type = 'mandatory') THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$function$;

COMMENT ON FUNCTION public.is_event_mandatory_for_member(uuid, uuid) IS
  'p170 — patched para excluir curators (designation=curator) de target_type tribe/all_active_operational. PM clarification 2026-05-16: curators são cross-tribe observers, participação geral+lideranca é opcional. Direct invite (event_invited_members) ainda obriga curators — explicit ask trumps semantic.';

-- ============================================================
-- Step 2: extend get_attendance_panel com typology
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_attendance_panel(
  p_cycle_start date DEFAULT '2026-01-01'::date,
  p_cycle_end date DEFAULT '2026-06-30'::date
)
RETURNS TABLE(member_id uuid, member_name text, tribe_name text, tribe_id integer, operational_role text,
              general_mandatory integer, general_attended integer, general_pct numeric,
              tribe_mandatory integer, tribe_attended integer, tribe_pct numeric,
              combined_pct numeric, last_attendance date, dropout_risk boolean,
              typology text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  WITH general_events AS (
    SELECT DISTINCT e.id as event_id, e.date::date as event_date
    FROM public.events e
    JOIN public.event_tag_assignments eta ON eta.event_id = e.id
    JOIN public.tags t ON t.id = eta.tag_id AND t.name = 'general_meeting'
    WHERE e.date::date BETWEEN p_cycle_start AND LEAST(p_cycle_end, CURRENT_DATE)
      AND (e.status IS NULL OR e.status != 'cancelled')
  ),
  tribe_events AS (
    SELECT DISTINCT e.id as event_id, e.date::date as event_date
    FROM public.events e
    JOIN public.event_tag_assignments eta ON eta.event_id = e.id
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
  SELECT
    c.id, c.m_name, c.t_name, c.t_id, c.op_role,
    c.g_mand::int, c.g_att::int, c.g_pct,
    c.t_mand::int, c.t_att::int, c.t_pct,
    c.c_pct, c.last_date,
    -- dropout_risk: curators NEVER at risk; others < 50% combined
    (NOT c.is_curator AND (c.g_mand + c.t_mand) > 0 AND c.c_pct < 50) AS dropout_risk,
    -- typology
    CASE
      WHEN c.is_curator                               THEN 'curator'
      WHEN c.g_mand + c.t_mand = 0                    THEN 'no-data'
      WHEN c.c_pct >= 70                              THEN 'healthy'
      WHEN c.c_pct >= 50                              THEN 'borderline'
      WHEN c.g_pct < 30 AND c.t_pct >= 50             THEN 'missing-general'
      WHEN c.t_pct < 30 AND c.g_pct >= 50             THEN 'missing-tribe'
      WHEN c.c_pct < 30                               THEN 'missing-both'
      ELSE 'balanced-low'
    END AS typology
  FROM computed c
  ORDER BY c.m_name;
END;
$function$;

COMMENT ON FUNCTION public.get_attendance_panel(date, date) IS
  'p170 — typology column + curator-aware dropout_risk. PM 2026-05-16: curators (Roberto, Sarah) excluded de mandatory; dropout_risk SEMPRE false pra curators.';

NOTIFY pgrst, 'reload schema';
