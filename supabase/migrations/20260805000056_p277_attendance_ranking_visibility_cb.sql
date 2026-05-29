-- p277 — Attendance ranking visibility model C+B (metric-disparity audit follow-up to D2)
--
-- WHAT: Resolve the PM product/privacy decision left open by D2. After D2 we masked the
--   dropout_risk BOOLEAN for non-leaders, but the raw combined_pct stayed visible — and the
--   flag is just `combined_pct < 50`, so any member could re-derive "who is at risk" by eye.
--   Model C+B closes that coherently:
--     C  non-privileged caller sees ONLY their own row + an ANONYMOUS cohort aggregate
--        (cohort average %, the caller's ahead-of-cohort %, cohort size). No other members'
--        names/%. Leadership (manage_event) + GP see the full nominal ranking (unchanged).
--     B  the gamification visibility opt-out (ADR-0050) governs PEER-nominal appearance; under
--        C there is no peer-nominal surface for rank-and-file, so opt-out keeps its XP-leaderboard
--        meaning and the unified "hide me from rankings" story holds. Leaders intentionally keep
--        operational visibility (legitimate interest — volunteer-commitment duty of care), so
--        opt-out does NOT blind a leader to attendance. This mirrors the audit's documented
--        admin/leader opt-out carve-out.
--
--   Signature gains 3 nullable columns (cohort_avg_pct, cohort_percentile, cohort_size),
--   populated ONLY on the caller's own row when NOT privileged. The cohort aggregate is computed
--   from the existing `computed` CTE — NO new inline attendance formula is introduced (ADR-0100).
--   Column-count change requires DROP + CREATE (GC-097). Also REVOKE the leftover anon/PUBLIC
--   execute grant (D2 already returns 0 rows to anon; this removes the ability to invoke at all).
--
-- WHY: LGPD data minimization (Art. 6 III) — a member keeps the motivational signal (own % vs
--   anonymous cohort) without seeing any third party's personal attendance datum; peer-nominal
--   attendance has no clean legitimate-interest basis and exceeds a volunteer's reasonable
--   expectation. Completes D2 (no more % re-derivation of the risk flag).
--
-- ROLLBACK: DROP + re-CREATE the p276 (migration 20260805000055) body without the 3 cohort
--   columns / self-row WHERE, and restore the broader grant. Reverting reopens the % re-derivation.
--
-- Consumers: Home hero reads its own row by column name (extra columns ignored — safe). The
--   /attendance Ranking tab branches on cohort_size to render a "sua presença" standing card for
--   non-privileged callers and the full nominal list for leadership.

DROP FUNCTION IF EXISTS public.get_attendance_panel(date, date);

CREATE OR REPLACE FUNCTION public.get_attendance_panel(p_cycle_start date DEFAULT '2026-01-01'::date, p_cycle_end date DEFAULT '2026-06-30'::date)
 RETURNS TABLE(member_id uuid, member_name text, tribe_name text, tribe_id integer, operational_role text, general_mandatory integer, general_attended integer, general_pct numeric, tribe_mandatory integer, tribe_attended integer, tribe_pct numeric, combined_pct numeric, last_attendance date, dropout_risk boolean, typology text, cohort_avg_pct numeric, cohort_percentile numeric, cohort_size integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_privileged boolean := false;
BEGIN
  -- D2 gate: require an active member (this RPC must never serve anon/ghost callers).
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_id IS NULL THEN
    RETURN; -- anon / ghost / inactive: no rows
  END IF;
  -- Leadership (tribe leaders + GP) see the full nominal ranking + dropout_risk/typology.
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
  ),
  -- C+B anonymous aggregate: comparable population = members with mandatory events, excl curators.
  cohort AS (
    SELECT ROUND(AVG(c.c_pct), 1) AS avg_pct, COUNT(*)::int AS sz
    FROM computed c
    WHERE (c.g_mand + c.t_mand) > 0 AND NOT c.is_curator
  ),
  caller AS (
    SELECT
      ROUND(100.0 * (
        SELECT COUNT(*) FROM computed c2
        WHERE (c2.g_mand + c2.t_mand) > 0 AND NOT c2.is_curator AND c2.c_pct < c.c_pct
      ) / NULLIF((SELECT COUNT(*) FROM computed c3 WHERE (c3.g_mand + c3.t_mand) > 0 AND NOT c3.is_curator), 0), 0) AS ahead_pct
    FROM computed c WHERE c.id = v_caller_id
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
      ELSE NULL END AS typology,
    -- C: anonymous cohort aggregate only on the caller's own row, only when NOT privileged
    CASE WHEN NOT v_privileged AND c.id = v_caller_id THEN (SELECT avg_pct FROM cohort) ELSE NULL END AS cohort_avg_pct,
    CASE WHEN NOT v_privileged AND c.id = v_caller_id THEN (SELECT ahead_pct FROM caller) ELSE NULL END AS cohort_percentile,
    CASE WHEN NOT v_privileged AND c.id = v_caller_id THEN (SELECT sz FROM cohort) ELSE NULL END AS cohort_size
  FROM computed c
  WHERE v_privileged OR c.id = v_caller_id     -- C: non-privileged caller gets only their own row
  ORDER BY c.m_name;
END;
$function$;

-- Least-privilege: anon must not even be able to invoke (D2 gate already returns 0 rows).
-- NOTE: Supabase ALTER DEFAULT PRIVILEGES re-grants EXECUTE to anon on new public functions,
-- so the explicit `FROM anon` revoke is required in addition to `FROM PUBLIC`.
REVOKE EXECUTE ON FUNCTION public.get_attendance_panel(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_attendance_panel(date, date) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
