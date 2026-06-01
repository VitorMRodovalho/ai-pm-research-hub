-- #419 metric 6 (trail_completion + cpmai_certified) — ADR-0100 canonical.
--
-- TRAIL (D-M6-TRAIL): calc_trail_completion_pct was ALREADY partial-credit; the two defects fixed here:
--   (1) hardcoded /6.0 -> dynamic NULLIF(count(courses WHERE is_trail), 0);
--   (2) cohort included operational_role='guest' (2 guests at 0/6) that get_public_trail_ranking EXCLUDES.
-- After: home == ranking (same 35-member cohort, dynamic total). Antes 44 -> depois 47 (integer ROUND;
-- the ranking shows 46.66 at 2dp — same metric, display rounding differs).
--
-- CPMAI (D-M6-CPMAI): the GOAL metric counts members who CERTIFIED DURING THE GOAL YEAR
--   (cpmai_certified AND cpmai_certified_at in [year, year+1)). A member who arrived already holding
--   CPMAI (cert dated before the goal year — e.g. Pedro 2025-10-23) is on the certificate WALL
--   (all-time) but NOT the goal metric. PMI-GO-board-pactuated business rule. Canonical helper
--   get_cpmai_certified_goal_count(p_year) repoints the 3 goal surfaces:
--     exec_portfolio_health.cpmai_certified  (was already goal-year-windowed; now via the helper) = 1
--     get_kpi_dashboard "Certificação CPMAI" (was is_active∧cpmai NO date — coincidentally 1)      -> 1
--     get_annual_kpis.cpmai_certified_count  (was cpmai NO date/active = 2)                  2 -> 1
--   Live: goal-year-2026 (meta) = 1 (Marcos 2026-03-04); wall all-time = 2 (+ Pedro 2025-10-23).
--   Canonical source = the DATED boolean, NOT the gamification cert_cpmai ledger, NOT a date-free count.
--
-- NOT touched (deferred to #425 coaching cockpit — avoids triple-touching the big gamification RPCs that
-- metric 4 + metric 5 also converge): the GI-1 trail_completion hardcoded 0 in get_tribe_gamification /
-- get_initiative_gamification. The credly/course-management cpmai surfaces (get_cpmai_*, enroll_in_cpmai_course,
-- update_cpmai_progress, get_my_credly_status, get_tribe_credly_status) are not the GOAL metric — left as-is.

-- ── Canonical cpmai goal-metric helper ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_cpmai_certified_goal_count(p_year integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Goal metric: certifications EARNED in the goal year. A pre-goal-year cert (member arrived
  -- already certified) belongs on the all-time wall, not the goal. p_year NULL => current year.
  SELECT COUNT(*)::int
  FROM public.members m
  WHERE m.cpmai_certified = true
    AND m.cpmai_certified_at >= make_date(COALESCE(p_year, EXTRACT(year FROM now())::int), 1, 1)
    AND m.cpmai_certified_at <  make_date(COALESCE(p_year, EXTRACT(year FROM now())::int) + 1, 1, 1);
$function$;

COMMENT ON FUNCTION public.get_cpmai_certified_goal_count(integer) IS
  '#419 metric 6 canonical CPMAI GOAL count = members who certified DURING the goal year (cpmai_certified AND cpmai_certified_at in [year, year+1)). PMI-GO board rule: pre-goal-year certs are on the all-time wall, not the goal. NOT the gamification cert_cpmai ledger. p_year NULL => current year.';

REVOKE ALL ON FUNCTION public.get_cpmai_certified_goal_count(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_cpmai_certified_goal_count(integer) TO authenticated, service_role;

-- ── Trail: dynamic total + exclude guests (align cohort to get_public_trail_ranking) ─────────────
CREATE OR REPLACE FUNCTION public.calc_trail_completion_pct()
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- #419 metric 6 (D-M6-TRAIL): partial-credit AVG-of-member-rates over the SHARED trail-eligible
  -- cohort (drop 'guest' so this == get_public_trail_ranking's cohort), DYNAMIC is_trail total
  -- (no hardcoded 6). Native-initiative N/A is a per-surface concern (this is the org headline).
  SELECT ROUND(COALESCE(AVG(member_pct) * 100, 0))
  FROM (
    SELECT COALESCE(COUNT(cp.id) FILTER (WHERE cp.status = 'completed'), 0)::numeric
           / NULLIF((SELECT COUNT(*) FROM courses WHERE is_trail = true), 0) AS member_pct
    FROM public.members m
    LEFT JOIN public.course_progress cp ON cp.member_id = m.id
      AND cp.course_id IN (SELECT id FROM courses WHERE is_trail = true)
    WHERE m.current_cycle_active = true AND m.is_active = true
      AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor', 'guest')
    GROUP BY m.id
  ) sub;
$function$;

-- ── cpmai goal-metric surface repoints (same-signature CREATE OR REPLACE; only the cpmai line changed) ─
CREATE OR REPLACE FUNCTION public.exec_portfolio_health(p_cycle_code text DEFAULT 'cycle3-2026'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb := '[]'::jsonb;
  v_cycle_code text;
  v_target record;
  v_current numeric;
  v_progress numeric;
  v_status text;
  v_year_start date;
  v_current_quarter int;
  v_q_target numeric;
  v_q_cumulative numeric;
  v_q_progress numeric;
  v_q_status text;
BEGIN
  v_year_start := make_date(EXTRACT(year FROM now())::int, 1, 1);
  v_current_quarter := EXTRACT(quarter FROM now())::int;

  -- GI-3 resilient cycle resolution: never silently return zero metrics. If the requested
  -- code has no targets (NULL/blank, or a namespace-mismatched code like cycles 'cycle_3'),
  -- fall back to the most-recently-created cycle_code that has targets.
  v_cycle_code := NULLIF(trim(p_cycle_code), '');
  IF v_cycle_code IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.portfolio_kpi_targets WHERE cycle_code = v_cycle_code) THEN
    SELECT cycle_code INTO v_cycle_code
    FROM public.portfolio_kpi_targets
    GROUP BY cycle_code
    ORDER BY MAX(created_at) DESC
    LIMIT 1;
  END IF;

  FOR v_target IN
    SELECT * FROM public.portfolio_kpi_targets
    WHERE cycle_code = v_cycle_code
    ORDER BY display_order
  LOOP
    CASE v_target.metric_key

      WHEN 'chapters_participating' THEN
        SELECT COUNT(DISTINCT chapter)::numeric INTO v_current
        FROM public.members
        WHERE current_cycle_active = true AND chapter IS NOT NULL;

      WHEN 'partner_entities' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.partner_entities
        WHERE entity_type IN ('academia', 'governo', 'empresa')
          AND status = 'active'
          AND partnership_date >= v_year_start;

      WHEN 'certification_trail' THEN
        SELECT calc_trail_completion_pct() INTO v_current;

      WHEN 'cpmai_certified' THEN
        v_current := public.get_cpmai_certified_goal_count(EXTRACT(year FROM v_year_start)::int);

      WHEN 'articles_published' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')
          AND bi.curation_status = 'approved'
          AND bi.created_at >= v_year_start::timestamptz;

      WHEN 'webinars_completed' THEN
        v_current := public.get_webinars_count(v_year_start, current_date, 'realized');

      WHEN 'ia_pilots' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.ia_pilots
        WHERE start_date >= v_year_start
          AND status IN ('active', 'completed');

      WHEN 'meeting_hours' THEN
        SELECT COALESCE(ROUND(SUM(COALESCE(e.duration_actual, e.duration_minutes)::numeric / 60.0)), 0)
        INTO v_current
        FROM public.events e
        WHERE e.date >= v_year_start AND e.date <= current_date;

      WHEN 'impact_hours' THEN
        v_current := public.get_impact_hours_canonical(v_year_start, current_date);

      ELSE
        v_current := 0;
    END CASE;

    v_progress := CASE
      WHEN v_target.target_value > 0 THEN ROUND((v_current / v_target.target_value) * 100)
      ELSE 0
    END;

    v_status := CASE
      WHEN v_current >= v_target.target_value THEN 'green'
      WHEN v_current >= v_target.warning_threshold THEN 'yellow'
      ELSE 'red'
    END;

    SELECT qt.quarter_target, qt.quarter_cumulative_target
    INTO v_q_target, v_q_cumulative
    FROM public.portfolio_kpi_quarterly_targets qt
    WHERE qt.kpi_target_id = v_target.id
      AND qt.quarter = v_current_quarter;

    v_q_progress := CASE
      WHEN COALESCE(v_q_cumulative, 0) > 0 THEN ROUND((v_current / v_q_cumulative) * 100)
      ELSE 0
    END;

    v_q_status := CASE
      WHEN v_current >= COALESCE(v_q_cumulative, 0) THEN 'green'
      WHEN COALESCE(v_q_cumulative, 0) > 0 AND v_current >= v_q_cumulative * 0.5 THEN 'yellow'
      ELSE 'red'
    END;

    v_result := v_result || jsonb_build_object(
      'metric_key', v_target.metric_key,
      'label', v_target.metric_label,
      'target', ROUND(v_target.target_value),
      'current', ROUND(v_current),
      'progress_pct', v_progress,
      'status', v_status,
      'unit', v_target.unit,
      'display_order', v_target.display_order,
      'quarter', v_current_quarter,
      'quarter_target', ROUND(COALESCE(v_q_target, 0)),
      'quarter_cumulative', ROUND(COALESCE(v_q_cumulative, 0)),
      'quarter_progress_pct', v_q_progress,
      'quarter_status', v_q_status
    );
  END LOOP;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_kpi_dashboard(p_cycle_start date DEFAULT '2026-01-01'::date, p_cycle_end date DEFAULT '2026-06-30'::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  result jsonb;
  days_elapsed numeric;
  days_total numeric;
  linear_pct numeric;
  v_target RECORD;
BEGIN
  days_elapsed := GREATEST(current_date - p_cycle_start, 0);
  days_total := p_cycle_end - p_cycle_start;
  linear_pct := CASE WHEN days_total > 0 THEN round(days_elapsed / days_total * 100, 1) ELSE 0 END;

  SELECT jsonb_build_object(
    'cycle_pct', linear_pct,
    'kpis', jsonb_build_array(
      jsonb_build_object(
        'name', 'Horas de Impacto',
        'current', COALESCE((
          SELECT round(sum(COALESCE(e.duration_actual, e.duration_minutes, 60)::numeric
            * (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present)) / 60)
          FROM events e WHERE e.date BETWEEN p_cycle_start AND p_cycle_end), 0),
        'target', 1800, 'unit', 'h', 'icon', 'clock'),
      jsonb_build_object(
        'name', 'Certificação CPMAI',
        'current', public.get_cpmai_certified_goal_count(),
        'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'cpmai_certified' AND year = 2026), 5),
        'unit', 'membros', 'icon', 'award'),
      jsonb_build_object(
        'name', 'Pilotos de IA',
        'current', COALESCE((SELECT (value)::int FROM site_config WHERE key = 'kpi_pilot_count_override'), 0),
        'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'pilots_completed' AND year = 2026), 3),
        'unit', '', 'icon', 'rocket'),
      jsonb_build_object(
        'name', 'Artigos Publicados',
        'current', (SELECT count(*) FROM board_items bi JOIN project_boards pb ON pb.id = bi.board_id
          WHERE pb.board_name ILIKE '%publica%' AND bi.status IN ('done','published')),
        'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'publications_submitted' AND year = 2026), 10),
        'unit', '', 'icon', 'file-text'),
      jsonb_build_object(
        'name', 'Webinars Realizados',
        'current', public.get_webinars_count(p_cycle_start, p_cycle_end, 'realized'),
        'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'webinars_realized' AND year = 2026), 6),
        'unit', '', 'icon', 'video'),
      jsonb_build_object(
        'name', 'Capítulos Integrados',
        'current', (SELECT count(DISTINCT chapter) FROM members WHERE is_active AND chapter IS NOT NULL),
        'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'chapters_participating' AND year = 2026), 8),
        'unit', '', 'icon', 'map-pin')
    )
  ) INTO result;
  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_annual_kpis(p_cycle integer DEFAULT 4, p_year integer DEFAULT 2026)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_auto_values jsonb;
  v_kpis jsonb;
  v_cycle_start date := '2025-12-01';
  v_cycle_end date := '2026-06-30';
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  v_auto_values := jsonb_build_object(
    'pilots_active_or_completed', (SELECT count(*) FROM public.pilots WHERE status IN ('active', 'completed')),
    'publications_submitted_count', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_tag_assignments bita ON bita.board_item_id = bi.id JOIN public.tags t ON t.id = bita.tag_id WHERE t.name = 'publicacao' AND bi.status IN ('done', 'review')),
    'articles_academic_count', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_tag_assignments bita ON bita.board_item_id = bi.id JOIN public.tags t ON t.id = bita.tag_id WHERE t.name = 'artigo_academico' AND bi.status IN ('done', 'review')),
    'frameworks_delivered_count', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_tag_assignments bita ON bita.board_item_id = bi.id JOIN public.tags t ON t.id = bita.tag_id WHERE t.name IN ('framework', 'ferramenta') AND bi.status IN ('done', 'review')),
    'webinars_realized_count', public.get_webinars_count(v_cycle_start, LEAST(v_cycle_end, CURRENT_DATE), 'realized'),
    'attendance_general_avg_pct', public.calc_attendance_pct(),
    'retention_pct', (SELECT ROUND(count(*) FILTER (WHERE is_active = true AND current_cycle_active = true)::numeric / NULLIF(count(*), 0) * 100, 1) FROM public.members WHERE operational_role NOT IN ('visitor', 'candidate') AND is_active = true),
    'events_total_count', (SELECT count(*) FROM public.events e WHERE e.date BETWEEN v_cycle_start AND LEAST(v_cycle_end, CURRENT_DATE) AND NOT EXISTS (SELECT 1 FROM public.event_tag_assignments eta JOIN public.tags t ON t.id = eta.tag_id WHERE eta.event_id = e.id AND t.name = 'interview')),
    'trail_completion_pct', public.calc_trail_completion_pct(),
    'cpmai_certified_count', public.get_cpmai_certified_goal_count(),
    'active_members_count', (SELECT count(*) FROM public.members WHERE is_active = true AND current_cycle_active = true),
    'infra_cost_current', (SELECT COALESCE(SUM(ce.amount_brl), 0) FROM public.cost_entries ce JOIN public.cost_categories cc ON cc.id = ce.category_id WHERE cc.name = 'infrastructure' AND ce.date >= date_trunc('month', now())::date AND ce.date < (date_trunc('month', now()) + interval '1 month')::date)
  );

  SELECT jsonb_agg(
    jsonb_build_object(
      'id', k.id, 'kpi_key', k.kpi_key, 'label_pt', k.kpi_label_pt, 'label_en', k.kpi_label_en,
      'category', k.category, 'target', k.target_value, 'baseline', k.baseline_value,
      'current', CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END,
      'unit', k.target_unit, 'icon', k.icon,
      'progress_pct', CASE
        WHEN k.target_value > 0 THEN ROUND(COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) / k.target_value * 100, 1)
        WHEN k.target_value = 0 THEN 100
        ELSE 0
      END,
      'health', CASE
        WHEN k.target_value = 0 AND COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) = 0 THEN 'achieved'
        WHEN k.target_value = 0 THEN 'at_risk'
        WHEN COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) >= k.target_value THEN 'achieved'
        WHEN COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) >= k.target_value * 0.7 THEN 'on_track'
        WHEN COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) >= k.target_value * 0.4 THEN 'at_risk'
        ELSE 'behind'
      END,
      'notes', k.notes,
      'auto_query', k.auto_query
    ) ORDER BY k.display_order
  ) INTO v_kpis
  FROM public.annual_kpi_targets k
  WHERE k.cycle = p_cycle AND k.year = p_year;

  v_result := jsonb_build_object(
    'cycle', p_cycle, 'year', p_year, 'generated_at', now(),
    'kpis', COALESCE(v_kpis, '[]'::jsonb),
    'summary', jsonb_build_object(
      'total', jsonb_array_length(COALESCE(v_kpis, '[]'::jsonb)),
      'achieved', (SELECT count(*) FROM jsonb_array_elements(v_kpis) e WHERE e->>'health' = 'achieved'),
      'on_track', (SELECT count(*) FROM jsonb_array_elements(v_kpis) e WHERE e->>'health' = 'on_track'),
      'at_risk', (SELECT count(*) FROM jsonb_array_elements(v_kpis) e WHERE e->>'health' = 'at_risk'),
      'behind', (SELECT count(*) FROM jsonb_array_elements(v_kpis) e WHERE e->>'health' = 'behind')
    )
  );
  RETURN v_result;
END;
$function$;
