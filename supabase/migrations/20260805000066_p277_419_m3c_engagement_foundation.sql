-- p277 / #419 (ADR-0100) metric 3 — step 3c / PR1: ENGAGEMENT foundation (ADDITIVE, 0 number change).
--
-- SPEC: docs/specs/SPEC_419_M3_ATTENDANCE_TWO_METRIC.md (PM ratified all 10 §6 business-rule decisions).
-- Ships the shared eligibility primitive + the two engagement aggregates + the reliability aggregate.
-- NOTHING consumes these yet — surfaces converge onto them in PR2..PR8 (each with an antes->depois).
--
-- Ratified rules baked here:
--   D1 excused REMOVED from the engagement denominator (neutral; live 76.2%).
--   D2 cohort = operational union {researcher, tribe_leader, manager} (curator is a designation, NOT excluded);
--      aggregate = AVG-of-member-rates.
--   D3 lideranca eligibility = can_by_member('manage_event') (no phantom deputy_manager).
--   D4 tribo eligibility = own tribe via get_member_tribe resolved through initiatives.legacy_tribe_id
--      (events has NO tribe column); org-manager with get_member_tribe=NULL excluded from the tribo dimension.
--   D5 1on1 excluded.  D6 type set = {geral,kickoff,tribo,lideranca} (no evento_externo/comms live).
--   D8 point-in-time eligibility ships OFF (current-membership attribution) — get_member_tribe resolves TODAY;
--      the engagements-timeline / as-of-date path is a later PR (created_at is a useless proxy live).
--   D10 window = cycles.is_current (open => CURRENT_DATE; closed => cycle_end); NO date-literal fallback.
-- D7 hybrid delegation to is_event_mandatory_for_member (panel richness) is layered in PR7; this foundation
-- uses the event-type eligibility CTE that produces the live 76.2% headline.
--
-- LGPD: REVOKE anon/authenticated + GRANT service_role only (these would expose any member's rate;
-- internal SECDEF callers reach them as definer).  ROLLBACK: DROP the four functions.

-- ── shared eligibility source (the single one; consumed by engagement RPCs + future seal) ─────────
CREATE OR REPLACE FUNCTION public._attendance_eligible_events(p_member_id uuid, p_cycle_start date DEFAULT NULL)
RETURNS TABLE(event_id uuid, event_type text, event_date date)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH win AS (
    SELECT
      COALESCE(p_cycle_start, (SELECT c.cycle_start FROM public.cycles c WHERE c.is_current = true LIMIT 1)) AS start_date,
      LEAST(COALESCE((SELECT c.cycle_end FROM public.cycles c WHERE c.is_current = true LIMIT 1), CURRENT_DATE), CURRENT_DATE) AS end_date
  ),
  mt AS (
    SELECT public.get_member_tribe(p_member_id) AS tribe_id
  )
  SELECT e.id, e.type, e.date
  FROM public.events e, win, mt
  WHERE win.start_date IS NOT NULL
    AND e.date >= win.start_date
    AND e.date <= win.end_date
    AND e.status IS DISTINCT FROM 'cancelled'
    AND e.type IN ('geral', 'kickoff', 'tribo', 'lideranca')
    AND (
      e.type IN ('geral', 'kickoff')
      OR (e.type = 'tribo' AND mt.tribe_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.initiatives i
            WHERE i.id = e.initiative_id AND i.legacy_tribe_id = mt.tribe_id))
      OR (e.type = 'lideranca' AND public.can_by_member(p_member_id, 'manage_event'))
    );
$function$;

REVOKE ALL ON FUNCTION public._attendance_eligible_events(uuid, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._attendance_eligible_events(uuid, date) TO service_role;

-- ── ENGAGEMENT per-member (eligible denominator; no-show with no row counts as absent) ────────────
CREATE OR REPLACE FUNCTION public.get_attendance_engagement_rate(p_member_id uuid, p_cycle_start date DEFAULT NULL)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT ROUND(
    count(*) FILTER (WHERE att.present = true)::numeric
    / NULLIF(count(*) FILTER (WHERE att.excused IS NOT TRUE), 0),
    2)
  FROM public._attendance_eligible_events(p_member_id, p_cycle_start) el
  LEFT JOIN public.attendance att ON att.member_id = p_member_id AND att.event_id = el.event_id;
$function$;

REVOKE ALL ON FUNCTION public.get_attendance_engagement_rate(uuid, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_attendance_engagement_rate(uuid, date) TO service_role;

-- ── ENGAGEMENT aggregate (AVG-of-member-rates over the operational cohort + pooled totals) ─────────
CREATE OR REPLACE FUNCTION public.get_attendance_engagement_summary(p_scope text DEFAULT 'global', p_scope_id integer DEFAULT NULL, p_cycle_start date DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH cohort AS (
    SELECT m.id
    FROM public.members m
    WHERE m.is_active = true AND m.current_cycle_active = true
      AND m.operational_role IN ('researcher', 'tribe_leader', 'manager')
      AND (
        p_scope = 'global'
        OR (p_scope = 'tribe' AND public.get_member_tribe(m.id) = p_scope_id)
      )
  ),
  rates AS (
    SELECT c.id, public.get_attendance_engagement_rate(c.id, p_cycle_start) AS rate
    FROM cohort c
  ),
  totals AS (
    SELECT
      count(*) FILTER (WHERE att.present = true)        AS present_total,
      count(*) FILTER (WHERE att.excused IS NOT TRUE)   AS expected_total,
      count(*) FILTER (WHERE att.excused = true)        AS excused_total
    FROM cohort c
    CROSS JOIN LATERAL public._attendance_eligible_events(c.id, p_cycle_start) el
    LEFT JOIN public.attendance att ON att.member_id = c.id AND att.event_id = el.event_id
  )
  SELECT jsonb_build_object(
    'scope', p_scope,
    'scope_id', p_scope_id,
    'cohort_n', (SELECT count(*) FROM rates WHERE rate IS NOT NULL),
    'avg_rate', (SELECT ROUND(AVG(rate), 4) FROM rates WHERE rate IS NOT NULL),
    'present_total', (SELECT present_total FROM totals),
    'expected_total', (SELECT expected_total FROM totals),
    'excused_total', (SELECT excused_total FROM totals),
    'coverage_flag', CASE WHEN (SELECT count(*) FROM rates WHERE rate IS NOT NULL) = 0 THEN 'no_data' ELSE 'ok' END
  );
$function$;

REVOKE ALL ON FUNCTION public.get_attendance_engagement_summary(text, integer, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_attendance_engagement_summary(text, integer, date) TO service_role;

-- ── RELIABILITY aggregate (AVG of get_attendance_rate + recorded totals + a completeness coverage flag) ──
-- coverage = recorded rows / eligible events for the cohort — exposes the under-recording (live ~near 100%
-- reliability vs sparse absent rows). PR6 type-scopes get_attendance_rate; this summary auto-inherits.
CREATE OR REPLACE FUNCTION public.get_attendance_reliability_summary(p_scope text DEFAULT 'global', p_scope_id integer DEFAULT NULL, p_cycle_start date DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH cohort AS (
    SELECT m.id
    FROM public.members m
    WHERE m.is_active = true AND m.current_cycle_active = true
      AND m.operational_role IN ('researcher', 'tribe_leader', 'manager')
      AND (
        p_scope = 'global'
        OR (p_scope = 'tribe' AND public.get_member_tribe(m.id) = p_scope_id)
      )
  ),
  rates AS (
    SELECT c.id, public.get_attendance_rate(c.id, p_cycle_start) AS rate
    FROM cohort c
  ),
  recorded AS (
    SELECT
      count(*) FILTER (WHERE att.present = true)                          AS present_total,
      count(*) FILTER (WHERE att.present = false AND att.excused IS NOT TRUE) AS absent_total,
      count(*) FILTER (WHERE att.excused = true)                          AS excused_total
    FROM cohort c
    JOIN public.attendance att ON att.member_id = c.id
    JOIN public.events e ON e.id = att.event_id
    WHERE e.date >= COALESCE(p_cycle_start, (SELECT cy.cycle_start FROM public.cycles cy WHERE cy.is_current = true LIMIT 1))
      AND e.date <= CURRENT_DATE
      AND e.status IS DISTINCT FROM 'cancelled'
  ),
  elig AS (
    SELECT count(*) AS eligible_total
    FROM cohort c
    CROSS JOIN LATERAL public._attendance_eligible_events(c.id, p_cycle_start) el
  )
  SELECT jsonb_build_object(
    'scope', p_scope,
    'scope_id', p_scope_id,
    'cohort_n', (SELECT count(*) FROM rates WHERE rate IS NOT NULL),
    'avg_rate', (SELECT ROUND(AVG(rate), 4) FROM rates WHERE rate IS NOT NULL),
    'present_total', (SELECT present_total FROM recorded),
    'absent_total', (SELECT absent_total FROM recorded),
    'excused_total', (SELECT excused_total FROM recorded),
    'eligible_total', (SELECT eligible_total FROM elig),
    'coverage_flag', CASE
      WHEN (SELECT eligible_total FROM elig) = 0 THEN 'no_data'
      WHEN ((SELECT present_total + absent_total + excused_total FROM recorded))::numeric / NULLIF((SELECT eligible_total FROM elig), 0) >= 0.90 THEN 'complete'
      WHEN ((SELECT present_total + absent_total + excused_total FROM recorded))::numeric / NULLIF((SELECT eligible_total FROM elig), 0) >= 0.50 THEN 'partial'
      ELSE 'sparse'
    END
  );
$function$;

REVOKE ALL ON FUNCTION public.get_attendance_reliability_summary(text, integer, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_attendance_reliability_summary(text, integer, date) TO service_role;

NOTIFY pgrst, 'reload schema';
