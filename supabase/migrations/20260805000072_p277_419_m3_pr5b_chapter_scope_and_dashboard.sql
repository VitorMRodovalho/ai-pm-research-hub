-- p277 / #419 (ADR-0100) metric 3 — PR5b: 'chapter' scope on the summaries + get_chapter_dashboard converge.
--
-- SPEC: docs/specs/SPEC_419_M3_ATTENDANCE_TWO_METRIC.md §5 surface 7 + §7 PR5 (reports).
-- WHAT:
--   (1) get_attendance_engagement_summary + get_attendance_reliability_summary gain a 4th param
--       p_chapter text DEFAULT NULL and a 'chapter' scope. DROP+CREATE (arg-count change → cannot
--       CREATE OR REPLACE without creating an ambiguous overload). The 1-2-arg callers PR2..PR4
--       (calc_attendance_pct / get_tribe_stats / exec_tribe_dashboard / exec_cross_initiative_comparison)
--       call ('global') or ('tribe', t.id) and resolve unchanged to the 4-arg (defaults fill the rest).
--       Chapter cohort = member_status='active' AND chapter=p_chapter (the §7 carve-out — the chapter
--       dashboard's existing population definition; deliberately NOT the operational-role union used by
--       global/tribe, so chapter Participação reflects the whole active chapter, not just researchers/leaders).
--   (2) get_chapter_dashboard.attendance was distinct-present-members / chapter-members over a 90-day rolling
--       window with NO event-type filter (leaked entrevista/1on1/parceria/iniciativa) — a "reach" metric
--       mislabelled as attendance. Now: engagement (headline, Participação) + reliability (ops diagnostic,
--       WITH raw present/absent/excused counts) via the new 'chapter' scope + a real hub_engagement_pct
--       (was a hardcoded 70 baseline in the FE chart). The volume helpers avg_events_per_member /
--       total_events_attended now share the {geral,kickoff,tribo,lideranca} type set + the cycles.is_current
--       window. members[].attendance_pct converges to per-member engagement (was all-time present/recorded).
-- WHY:  D9/D10 + chapter must consume the canonical aggregate (PR10 gate forbids inline rate re-impl).
-- ROLLBACK: DROP the 4-arg summaries + re-CREATE the 3-arg bodies (migration 20260805000071/066) and
--           re-apply the prior get_chapter_dashboard body (90d rate_pct/hub_participation_pct). No data writes.

-- ── 1. ENGAGEMENT aggregate → 4-arg with 'chapter' scope (DROP+CREATE; keeps at_risk_count from PR5a) ──
DROP FUNCTION IF EXISTS public.get_attendance_engagement_summary(text, integer, date);
CREATE OR REPLACE FUNCTION public.get_attendance_engagement_summary(p_scope text DEFAULT 'global', p_scope_id integer DEFAULT NULL, p_cycle_start date DEFAULT NULL, p_chapter text DEFAULT NULL)
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
    'at_risk_count', (SELECT count(*) FROM rates WHERE rate IS NOT NULL AND rate < 0.50),
    'present_total', (SELECT present_total FROM totals),
    'expected_total', (SELECT expected_total FROM totals),
    'excused_total', (SELECT excused_total FROM totals),
    'coverage_flag', CASE WHEN (SELECT count(*) FROM rates WHERE rate IS NOT NULL) = 0 THEN 'no_data' ELSE 'ok' END
  );
$function$;

REVOKE ALL ON FUNCTION public.get_attendance_engagement_summary(text, integer, date, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_attendance_engagement_summary(text, integer, date, text) TO service_role;

-- ── 2. RELIABILITY aggregate → 4-arg with 'chapter' scope (DROP+CREATE; body otherwise = foundation) ──
DROP FUNCTION IF EXISTS public.get_attendance_reliability_summary(text, integer, date);
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

-- ── 3. get_chapter_dashboard — attendance block → engagement+reliability + members[] engagement ───────
CREATE OR REPLACE FUNCTION public.get_chapter_dashboard(p_chapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_chapter text;
  v_result jsonb;
  v_hub_members int;
  v_hub_avg_xp numeric;
  v_hub_certs int;
  v_ch_members int;
BEGIN
  SELECT m.id, m.chapter INTO v_caller_id, v_caller_chapter
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- V4 gate (Path Y per ADR-0030 precedent):
  -- Cross-chapter institutional access OR own-chapter member access
  IF public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    v_chapter := COALESCE(p_chapter, v_caller_chapter);
  ELSIF p_chapter IS NULL OR p_chapter = v_caller_chapter THEN
    v_chapter := v_caller_chapter;
  ELSE
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF v_chapter IS NULL THEN
    RETURN jsonb_build_object('error', 'No chapter specified');
  END IF;

  SELECT count(*) INTO v_hub_members FROM public.members WHERE is_active AND current_cycle_active;
  SELECT count(*) INTO v_ch_members FROM public.members WHERE chapter = v_chapter AND is_active;
  SELECT COALESCE(avg(t.xp), 0) INTO v_hub_avg_xp FROM (SELECT sum(points) AS xp FROM public.gamification_points GROUP BY member_id) t;
  SELECT count(*) INTO v_hub_certs FROM public.gamification_points WHERE category IN ('cert_pmi_senior','cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry');

  SELECT jsonb_build_object(
    'chapter', v_chapter,
    'cycle', 3,
    'people', (SELECT jsonb_build_object(
      'active', count(*) FILTER (WHERE member_status = 'active'),
      'observers', count(*) FILTER (WHERE member_status = 'observer'),
      'alumni', count(*) FILTER (WHERE member_status = 'alumni'),
      'hub_total', v_hub_members,
      'by_role', (SELECT jsonb_object_agg(role, cnt) FROM (SELECT operational_role AS role, count(*) AS cnt FROM public.members WHERE chapter = v_chapter AND member_status = 'active' GROUP BY operational_role) r)
    ) FROM public.members WHERE chapter = v_chapter),
    'output', jsonb_build_object(
      'board_cards_completed', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_assignments bia ON bia.item_id = bi.id JOIN public.members m ON m.id = bia.member_id WHERE m.chapter = v_chapter AND bi.status = 'done'),
      'publications_submitted', (SELECT count(*) FROM public.publication_submissions ps JOIN public.members m ON m.id = ps.primary_author_id WHERE m.chapter = v_chapter)
    ),
    -- p277 #419 m3 PR5b: chapter attendance = canonical engagement (headline, Participacao) + reliability
    -- (ops diagnostic, raw counts). Chapter cohort = member_status='active' (carve-out KEPT). The volume
    -- helpers now share the {geral,kickoff,tribo,lideranca} type set + the cycles.is_current window (was a
    -- 90-day rolling window with no type filter — leaked entrevista/1on1/parceria/iniciativa).
    'attendance', jsonb_build_object(
      'engagement', public.get_attendance_engagement_summary('chapter', NULL, NULL, v_chapter),
      'reliability', public.get_attendance_reliability_summary('chapter', NULL, NULL, v_chapter),
      'hub_engagement_pct', ROUND(COALESCE((public.get_attendance_engagement_summary('global') ->> 'avg_rate')::numeric, 0) * 100, 1),
      'avg_events_per_member', (SELECT ROUND(COUNT(a.id)::numeric / NULLIF(v_ch_members, 0), 1) FROM public.attendance a JOIN public.members m ON a.member_id = m.id JOIN public.events e ON a.event_id = e.id WHERE m.chapter = v_chapter AND m.is_active AND a.present AND e.type IN ('geral','kickoff','tribo','lideranca') AND e.status IS DISTINCT FROM 'cancelled' AND e.date >= (SELECT cycle_start FROM public.cycles WHERE is_current = true LIMIT 1)),
      'total_events_attended', (SELECT COUNT(a.id) FROM public.attendance a JOIN public.members m ON a.member_id = m.id JOIN public.events e ON a.event_id = e.id WHERE m.chapter = v_chapter AND m.is_active AND a.present AND e.type IN ('geral','kickoff','tribo','lideranca') AND e.status IS DISTINCT FROM 'cancelled' AND e.date >= (SELECT cycle_start FROM public.cycles WHERE is_current = true LIMIT 1))
    ),
    'hours', (SELECT jsonb_build_object(
      'total_hours', COALESCE(round(sum(CASE WHEN a.present THEN COALESCE(e.duration_minutes, 60) / 60.0 ELSE 0 END)::numeric, 1), 0),
      'pdu_equivalent', LEAST(COALESCE(round(sum(CASE WHEN a.present THEN COALESCE(e.duration_minutes, 60) / 60.0 ELSE 0 END)::numeric, 1), 0), 25)
    ) FROM public.attendance a JOIN public.events e ON e.id = a.event_id JOIN public.members m ON m.id = a.member_id WHERE m.chapter = v_chapter AND m.member_status = 'active'),
    'certifications', (SELECT jsonb_build_object(
      'pmp', count(*) FILTER (WHERE gp.category = 'cert_pmi_senior'),
      'cpmai', count(*) FILTER (WHERE gp.category = 'cert_cpmai'),
      'total_certs', count(*) FILTER (WHERE gp.category IN ('cert_pmi_senior','cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry')),
      'hub_total_certs', v_hub_certs
    ) FROM public.gamification_points gp JOIN public.members m ON m.id = gp.member_id WHERE m.chapter = v_chapter AND m.member_status = 'active'),
    'partnerships', (SELECT jsonb_build_object(
      'active', count(*) FILTER (WHERE pe.status = 'active'),
      'negotiation', count(*) FILTER (WHERE pe.status = 'negotiation'),
      'total', count(*)
    ) FROM public.partner_entities pe WHERE pe.chapter = v_chapter),
    'gamification', (SELECT jsonb_build_object(
      'avg_xp', COALESCE(round(avg(total_xp)), 0),
      'hub_avg_xp', round(v_hub_avg_xp),
      'top_contributors', (SELECT jsonb_agg(row_to_json(tc) ORDER BY tc.total_xp DESC) FROM (
        SELECT m.name, m.photo_url, sum(gp.points) AS total_xp
        FROM public.gamification_points gp JOIN public.members m ON m.id = gp.member_id
        WHERE m.chapter = v_chapter AND m.member_status = 'active'
        GROUP BY m.id, m.name, m.photo_url
        ORDER BY total_xp DESC LIMIT 3
      ) tc)
    ) FROM (SELECT sum(gp.points) AS total_xp FROM public.gamification_points gp JOIN public.members m ON m.id = gp.member_id WHERE m.chapter = v_chapter AND m.member_status = 'active' GROUP BY gp.member_id) t),
    'members', (SELECT jsonb_agg(row_to_json(ml) ORDER BY ml.total_xp DESC) FROM (
      SELECT m.id, m.name, m.photo_url, m.operational_role, m.designations,
        COALESCE((SELECT sum(points) FROM public.gamification_points WHERE member_id = m.id), 0) AS total_xp,
        COALESCE(ROUND(public.get_attendance_engagement_rate(m.id) * 100), 0) AS attendance_pct,
        (SELECT count(*) FROM public.gamification_points WHERE member_id = m.id AND category = 'trail') AS trail_count
      FROM public.members m WHERE m.chapter = v_chapter AND m.member_status = 'active'
    ) ml),
    'available_chapters', (SELECT jsonb_agg(DISTINCT m.chapter ORDER BY m.chapter) FROM public.members m WHERE m.chapter IS NOT NULL AND m.member_status = 'active')
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
