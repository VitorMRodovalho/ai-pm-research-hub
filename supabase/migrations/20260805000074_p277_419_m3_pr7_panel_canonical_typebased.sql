-- p277 / #419 (ADR-0100) metric 3 — PR7: get_attendance_panel → canonical type-based engagement;
--                                          DROP orphan get_attendance_summary.
--
-- SPEC: docs/specs/SPEC_419_M3_ATTENDANCE_TWO_METRIC.md §5 surfaces 2/11 + §7 PR7.
--
-- ── CANONICAL PRINCIPLE (PM ratified 2026-05-29, prerequisite for ALL future attendance metrics) ──────
-- `public._attendance_eligible_events(member, cycle_start)` (type-based: {geral,kickoff,tribo,lideranca},
-- per-member tribo via get_member_tribe, lideranca via can_by_member('manage_event'), cycles.is_current
-- window) is the SINGLE source of attendance eligibility. No surface may reintroduce a parallel
-- tag-based (general_meeting/tribe_meeting) or event_audience_rules-based eligibility model. Rationale:
-- one model, least maintenance, self-consistent. (PR10 p175 gate will forward-defend this.)
--
-- ── WHAT THIS PR DOES ─────────────────────────────────────────────────────────────────────────────────
-- (1) get_attendance_panel was the LAST surface still on a divergent model: it selected candidate events by
--     TAGS (general_meeting / tribe_meeting) and scoped eligibility via is_event_mandatory_for_member
--     (event_audience_rules). That model is alive (334 rules, 73+152 tagged events) but produced a DIFFERENT
--     global number — panel 81.5% / 83.2% operational vs the canonical home/tribe/chapter/cycle/member-detail
--     76.2%. The 3 panel consumers (HomepageHero widget, workspace AttendanceDashboard, /attendance ranking)
--     silently disagreed with every other surface. Root causes of 76.2 vs 81.5: (a) the audience-rule model
--     under-counts denominators for managers + NULL-tribe members (e.g. Roberto Macêdo read 100% on the panel
--     — mandatory for only 2 events — vs 22.2% everywhere else; Vitor's denom 24 audience vs 44 type), and
--     (b) tag candidate set != type candidate set (only 12 of 24 'geral' events carry the general_meeting tag).
--     PM decision B: TYPE-BASED is canonical (simplest, least maintenance, already shipped on 5 surfaces).
--     This rewrites the panel onto _attendance_eligible_events. Roberto now reads 22.2% on the panel too
--     (consistent with his home/member-detail). Most members unchanged (already 100% attendance). The exact
--     18-col TABLE shape, the D2 active-member gate, privileged/own-row visibility, and the C+B anonymous
--     cohort aggregate (avg/percentile/size) are preserved VERBATIM. general bucket = eligible non-tribo
--     (geral/kickoff/lideranca — mirrors the old general_meeting tag grouping); tribe bucket = eligible tribo.
--     Excused excluded from denominators (D1). CREATE OR REPLACE → existing ACL (anon/authenticated/
--     service_role EXECUTE; anon gated to empty rows in-body) preserved; no GRANT/REVOKE here by design.
-- (2) DROP get_attendance_summary(date,date,integer): orphan since PR5a decoupled exec_cycle_report. Verified
--     0 live consumers — not called by any other public function (pg_proc body scan), not registered in the
--     MCP server, not in any Edge Function, not read by any frontend. Dropping = least maintenance (PM
--     directive). Its 0.4/0.6 combined_pct weighting (D9-retired) and '2026-01-01' literals die with it.
--
-- DEFERRED (named, not silent): get_attendance_grid engagement headline (a SEPARATE surface via
-- /api/attendance/grid, present-detection already fixed in m3a #427) → follow-up; get_dropout_risk_members
-- (also on a dead event-type filter) → PR8.
--
-- ROLLBACK: re-CREATE get_attendance_summary from migration that defined it (search prosrc history) +
--   re-apply the prior tag/audience-rule get_attendance_panel body. No data writes.

-- ── 1. get_attendance_panel → canonical type-based (_attendance_eligible_events); 18-col shape preserved ──
CREATE OR REPLACE FUNCTION public.get_attendance_panel(p_cycle_start date DEFAULT NULL::date, p_cycle_end date DEFAULT NULL::date)
RETURNS TABLE(member_id uuid, member_name text, tribe_name text, tribe_id integer, operational_role text,
  general_mandatory integer, general_attended integer, general_pct numeric,
  tribe_mandatory integer, tribe_attended integer, tribe_pct numeric,
  combined_pct numeric, last_attendance date, dropout_risk boolean, typology text,
  cohort_avg_pct numeric, cohort_percentile numeric, cohort_size integer)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_privileged boolean := false;
BEGIN
  -- D2 gate: require an active member (never serve anon/ghost).
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_id IS NULL THEN
    RETURN; -- anon / ghost / inactive: no rows
  END IF;
  -- Leadership (tribe leaders + GP) see the full nominal ranking + dropout_risk/typology.
  v_privileged := public.can_by_member(v_caller_id, 'manage_event');

  RETURN QUERY
  WITH active AS (
    SELECT m.id, m.name AS m_name, tr.name AS t_name, m.tribe_id AS t_id,
           m.operational_role AS op_role,
           (m.designations IS NOT NULL AND m.designations @> ARRAY['curator']::text[]) AS is_curator
    FROM public.members m LEFT JOIN public.tribes tr ON tr.id = m.tribe_id
    WHERE m.is_active = true
  ),
  -- p277 #419 PR7: CANONICAL eligibility (type-based, per-member) — general = non-tribo eligible events
  -- (geral/kickoff/lideranca, mirrors the old general_meeting grouping), tribe = tribo eligible events.
  -- Excused excluded from the mandatory denominator (D1).
  per_member AS (
    SELECT a.id AS mid,
      count(*) FILTER (WHERE el.event_type <> 'tribo' AND att.excused IS NOT TRUE)::int AS g_mand,
      count(*) FILTER (WHERE el.event_type <> 'tribo' AND att.present = true)::int       AS g_att,
      count(*) FILTER (WHERE el.event_type =  'tribo' AND att.excused IS NOT TRUE)::int  AS t_mand,
      count(*) FILTER (WHERE el.event_type =  'tribo' AND att.present = true)::int        AS t_att
    FROM active a
    CROSS JOIN LATERAL public._attendance_eligible_events(a.id, p_cycle_start) el
    LEFT JOIN public.attendance att ON att.member_id = a.id AND att.event_id = el.event_id
    GROUP BY a.id
  ),
  last_att AS (
    SELECT a.member_id, MAX(e.date::date) AS last_date
    FROM public.attendance a JOIN public.events e ON e.id = a.event_id
    WHERE a.present = true GROUP BY a.member_id
  ),
  computed AS (
    SELECT a.id, a.m_name, a.t_name, a.t_id, a.op_role, a.is_curator,
      COALESCE(pm.g_mand,0) AS g_mand, COALESCE(pm.g_att,0) AS g_att,
      CASE WHEN COALESCE(pm.g_mand,0)>0 THEN ROUND(pm.g_att::numeric/pm.g_mand*100,1) ELSE 0 END AS g_pct,
      COALESCE(pm.t_mand,0) AS t_mand, COALESCE(pm.t_att,0) AS t_att,
      CASE WHEN COALESCE(pm.t_mand,0)>0 THEN ROUND(pm.t_att::numeric/pm.t_mand*100,1) ELSE 0 END AS t_pct,
      CASE WHEN COALESCE(pm.g_mand,0)+COALESCE(pm.t_mand,0)>0
        THEN ROUND((COALESCE(pm.g_att,0)+COALESCE(pm.t_att,0))::numeric/(COALESCE(pm.g_mand,0)+COALESCE(pm.t_mand,0))*100,1)
        ELSE 0 END AS c_pct,
      la.last_date
    FROM active a
    LEFT JOIN per_member pm ON pm.mid = a.id
    LEFT JOIN last_att la ON la.member_id = a.id
  ),
  -- C+B anonymous aggregate: comparable population = members with eligible events, excl curators.
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
    CASE WHEN NOT v_privileged AND c.id = v_caller_id THEN (SELECT avg_pct FROM cohort) ELSE NULL END AS cohort_avg_pct,
    CASE WHEN NOT v_privileged AND c.id = v_caller_id THEN (SELECT ahead_pct FROM caller) ELSE NULL END AS cohort_percentile,
    CASE WHEN NOT v_privileged AND c.id = v_caller_id THEN (SELECT sz FROM cohort) ELSE NULL END AS cohort_size
  FROM computed c
  WHERE v_privileged OR c.id = v_caller_id
  ORDER BY c.m_name;
END;
$function$;

-- ── 2. DROP orphan get_attendance_summary (0 live consumers; D9 weighting + date literals die with it) ──
DROP FUNCTION IF EXISTS public.get_attendance_summary(date, date, integer);

NOTIFY pgrst, 'reload schema';
