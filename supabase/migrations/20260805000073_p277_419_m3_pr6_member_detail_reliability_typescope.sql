-- p277 / #419 (ADR-0100) metric 3 — PR6: get_member_detail two-metric + reliability type-scope.
--
-- SPEC: docs/specs/SPEC_419_M3_ATTENDANCE_TWO_METRIC.md §5 surface 9 + §7 PR6.
-- WHAT:
--   (1) get_attendance_rate (RELIABILITY per-member primitive): + event-type scope {geral,kickoff,tribo,
--       lideranca}; - remove the '2026-03-01' COALESCE fallback (cycles.is_current is the canonical window).
--       This makes reliability share engagement's eligible event-type set so the two metrics are comparable.
--       Cascade: get_attendance_reliability_summary.avg_rate (which AVGs get_attendance_rate) auto-inherits;
--       cycle-report + chapter-dashboard reliability percentages converge onto the eligible roster.
--   (2) get_attendance_reliability_summary: type-scope the `recorded` CTE too (P/A/E COUNTS do NOT auto-inherit
--       from get_attendance_rate — only avg_rate does). Without this the raw counts shown on cycle-report +
--       chapter dashboard would stay inflated by 1on1/entrevista/iniciativa/parceria rows (12 such rows live for
--       the global operational cohort; PMI-GO P198 -> 191). Caught by the PR5b 3-lens review (spec MEDIUM-3).
--   (3) get_member_detail.attendance: fixes 3 bugs + shows BOTH canonical metrics per-member:
--         (a) attended = count(a.id) counted ANY row (absent/excused) -> present-filtered;
--         (b) rate = count(a.id)/count(DISTINCT e.id) was a silent 3rd denominator (all-events denom, any-row
--             numer, no type filter) -> replaced by ENGAGEMENT (Participacao) headline + RELIABILITY
--             (Confiabilidade) diagnostic, both via the canonical per-member primitives;
--         (c) recent[].present = (att.id IS NOT NULL) i.e. "a row exists" -> att.present = true.
--       Raw present/absent/excused/no_record counts surfaced (D10 — reliability always with raw counts; admin
--       surface gated view_internal_analytics). recent[] now lists the member's ELIGIBLE events (type-scoped,
--       member-scoped via _attendance_eligible_events), not all events (a tribo of another tribe was being
--       shown as an absence).
-- WHY:  §7 PR6 + the PR5b review carry. ROLLBACK: re-apply prior bodies (migrations 065 / 072 / the prior
--       get_member_detail). No data writes.

-- ── 1. get_attendance_rate — RELIABILITY primitive: + type scope, - '2026-03-01' fallback ─────────────
CREATE OR REPLACE FUNCTION public.get_attendance_rate(p_member_id uuid, p_cycle_start date DEFAULT NULL::date)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT ROUND(
    count(*) FILTER (WHERE a.present = true)::numeric
    / NULLIF(count(*) FILTER (WHERE a.excused IS NOT TRUE), 0),
    2)
  FROM public.attendance a
  JOIN public.events e ON e.id = a.event_id
  WHERE a.member_id = p_member_id
    AND e.date >= COALESCE(p_cycle_start, (SELECT c.cycle_start FROM public.cycles c WHERE c.is_current = true LIMIT 1))
    AND e.date <= CURRENT_DATE
    AND e.status IS DISTINCT FROM 'cancelled'
    AND e.type IN ('geral', 'kickoff', 'tribo', 'lideranca');
$function$;

REVOKE ALL ON FUNCTION public.get_attendance_rate(uuid, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_attendance_rate(uuid, date) TO service_role;
COMMENT ON FUNCTION public.get_attendance_rate(uuid, date) IS
  'RELIABILITY per-member: present / (present+absent), excused excluded, over RECORDED rows at event types '
  '{geral,kickoff,tribo,lideranca} within cycles.is_current (open => CURRENT_DATE). p277 #419 PR6 added the '
  'event-type scope + removed the 2026-03-01 date-literal fallback so it converges with engagement.';

-- ── 2. get_attendance_reliability_summary — type-scope the `recorded` CTE (same 4-arg sig) ────────────
CREATE OR REPLACE FUNCTION public.get_attendance_reliability_summary(p_scope text DEFAULT 'global', p_scope_id integer DEFAULT NULL, p_cycle_start date DEFAULT NULL, p_chapter text DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH cohort AS (
    SELECT m.id
    FROM public.members m
    WHERE CASE
      WHEN p_scope = 'chapter' THEN (m.member_status = 'active' AND m.chapter = p_chapter)
      ELSE (
        m.is_active = true AND m.current_cycle_active = true
        AND m.operational_role IN ('researcher', 'tribe_leader', 'manager')
        AND (
          p_scope = 'global'
          OR (p_scope = 'tribe' AND public.get_member_tribe(m.id) = p_scope_id)
        )
      )
    END
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
      AND e.type IN ('geral', 'kickoff', 'tribo', 'lideranca')
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

REVOKE ALL ON FUNCTION public.get_attendance_reliability_summary(text, integer, date, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_attendance_reliability_summary(text, integer, date, text) TO service_role;

-- ── 3. get_member_detail — attendance block: 3 bugs fixed + two-metric + raw P/A/E + eligible recent[] ─
CREATE OR REPLACE FUNCTION public.get_member_detail(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT jsonb_build_object(
    'member', (SELECT jsonb_build_object(
      'id', m.id, 'full_name', m.name, 'email', m.email, 'photo_url', m.photo_url,
      'operational_role', m.operational_role, 'designations', m.designations,
      'is_superadmin', m.is_superadmin, 'is_active', m.is_active,
      'tribe_id', m.tribe_id, 'tribe_name', t.name, 'chapter', m.chapter,
      'auth_id', m.auth_id, 'credly_username', m.credly_url,
      'last_seen_at', m.last_seen_at, 'total_sessions', COALESCE(m.total_sessions, 0),
      'credly_badges', COALESCE(m.credly_badges, '[]'::jsonb),
      'interview_booking_url', m.interview_booking_url
    ) FROM public.members m LEFT JOIN public.tribes t ON t.id = m.tribe_id WHERE m.id = p_member_id),
    'cycles', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'cycle', mch.cycle_label,
      'tribe_id', mch.tribe_id,
      'tribe_name', t.name,
      'operational_role', mch.operational_role,
      'designations', mch.designations,
      'status', CASE WHEN mch.is_active THEN 'ativo' ELSE 'inativo' END
    ) ORDER BY mch.cycle_start DESC), '[]'::jsonb)
    FROM public.member_cycle_history mch
    LEFT JOIN public.tribes t ON t.id = mch.tribe_id
    WHERE mch.member_id = p_member_id),
    'gamification', (
      WITH agg AS (
        SELECT member_id, SUM(points)::int AS total_points
        FROM public.gamification_points
        GROUP BY member_id
      ),
      ranked AS (
        SELECT member_id, total_points,
               ROW_NUMBER() OVER (ORDER BY total_points DESC) AS rk
        FROM agg
      )
      SELECT jsonb_build_object(
        'total_xp', COALESCE((SELECT total_points FROM ranked WHERE member_id = p_member_id), 0),
        'rank', (SELECT rk FROM ranked WHERE member_id = p_member_id),
        'categories', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'category', gp.category, 'xp', gp.points, 'description', gp.reason
        )), '[]'::jsonb) FROM public.gamification_points gp WHERE gp.member_id = p_member_id)
      )
    ),
    -- p277 #419 m3 PR6: two-metric per-member. ENGAGEMENT (Participacao) headline + RELIABILITY
    -- (Confiabilidade) diagnostic, both via canonical per-member primitives (no inline rate re-impl).
    -- Raw present/absent/excused/no_record over the member's ELIGIBLE events (type-scoped, member-scoped).
    -- recent[] lists eligible events with present = att.present = true (not "a row exists") + an excused flag.
    'attendance', (
      -- TWO populations, kept separate so each metric's raw counts reconcile with its own rate (PR6 review MED):
      --   elig = the member's ELIGIBLE events (pairs with engagement / Participacao)
      --   rec  = the member's type-scoped RECORDED rows = exactly get_attendance_rate's population (pairs with
      --          reliability / Confiabilidade). rec mirrors get_attendance_rate's WHERE (member + cycle window +
      --          type set); reliability_pct itself stays the canonical primitive (no inline rate re-impl).
      WITH elig AS (
        SELECT a.present, a.excused
        FROM public._attendance_eligible_events(p_member_id) el
        LEFT JOIN public.attendance a ON a.member_id = p_member_id AND a.event_id = el.event_id
      ),
      rec AS (
        SELECT a.present, a.excused
        FROM public.attendance a
        JOIN public.events e ON e.id = a.event_id
        WHERE a.member_id = p_member_id
          AND e.date >= (SELECT c.cycle_start FROM public.cycles c WHERE c.is_current = true LIMIT 1)
          AND e.date <= CURRENT_DATE
          AND e.status IS DISTINCT FROM 'cancelled'
          AND e.type IN ('geral', 'kickoff', 'tribo', 'lideranca')
      )
      SELECT jsonb_build_object(
        'engagement_pct', ROUND(COALESCE(public.get_attendance_engagement_rate(p_member_id), 0) * 100, 1),
        'reliability_pct', ROUND(COALESCE(public.get_attendance_rate(p_member_id), 0) * 100, 1),
        -- engagement breakdown (eligible population):
        'eligible_total', (SELECT count(*) FROM elig),
        'present', (SELECT count(*) FILTER (WHERE present = true) FROM elig),
        'absent', (SELECT count(*) FILTER (WHERE present = false AND excused IS NOT TRUE) FROM elig),
        'excused', (SELECT count(*) FILTER (WHERE excused = true) FROM elig),
        'no_record', (SELECT count(*) FILTER (WHERE present IS NULL) FROM elig),
        -- reliability breakdown (recorded population — reconciles with reliability_pct):
        'recorded_total', (SELECT count(*) FROM rec),
        'recorded_present', (SELECT count(*) FILTER (WHERE present = true) FROM rec),
        'recorded_absent', (SELECT count(*) FILTER (WHERE present = false AND excused IS NOT TRUE) FROM rec),
        'recorded_excused', (SELECT count(*) FILTER (WHERE excused = true) FROM rec),
        'recent', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'event_name', ev.title, 'event_date', el.event_date,
          'present', a.present, 'excused', COALESCE(a.excused, false)
        ) ORDER BY el.event_date DESC), '[]'::jsonb)
        FROM (SELECT * FROM public._attendance_eligible_events(p_member_id) ORDER BY event_date DESC LIMIT 20) el
        JOIN public.events ev ON ev.id = el.event_id
        LEFT JOIN public.attendance a ON a.event_id = el.event_id AND a.member_id = p_member_id)
      )
    ),
    'publications', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ps.id, 'title', ps.title, 'status', ps.status,
      'submitted_at', ps.submission_date, 'target_type', ps.target_type
    ) ORDER BY ps.submission_date DESC), '[]'::jsonb)
    FROM public.publication_submissions ps
    JOIN public.publication_submission_authors psa ON psa.submission_id = ps.id
    WHERE psa.member_id = p_member_id),
    'audit_log', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'action', al.action, 'changes', al.changes, 'actor_name', actor.name, 'created_at', al.created_at
    ) ORDER BY al.created_at DESC), '[]'::jsonb)
    FROM public.admin_audit_log al
    LEFT JOIN public.members actor ON actor.id = al.actor_id
    WHERE al.target_id = p_member_id AND al.target_type = 'member' LIMIT 20)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
