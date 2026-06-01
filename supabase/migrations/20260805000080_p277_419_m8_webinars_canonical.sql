-- #419 metric 8 (webinars) — ADR-0100 canonical webinars count off the `webinars` TABLE
-- (architectural source of truth, CLAUDE.md Key Architecture Decision #4), retiring the
-- events.type='webinar' / event-tag-join forks on the COUNT surfaces.
--
-- Antes → depois (live-grounded 2026-05-31, cycle_3 from cycles.is_current):
--   exec_portfolio_health.webinars_completed (YTD-2026 window)      0 → 7
--   get_kpi_dashboard "Webinars Realizados"                          0 → 7
--   exec_cycle_report production.webinars_completed / _planned     4/0 → 7/0
--   get_annual_kpis.webinars_realized_count (tag-join)               0 → 7
--   get_public_impact_data.webinars (all-time)                       4 → 7
--   (webinars table live = 7: 4 planned + 3 confirmed, all past-dated 2026-04-15..05-28)
--
-- NOT touched (by design — not count metrics):
--   * event-type CLASSIFIERS that legitimately use events.type='webinar':
--     create_event, auto_tag_event_by_type, update_event, suggest_tags,
--     notify_webinar_status_change, update_future_events_in_group
--   * get_weekly_member_digest — an UPCOMING-events filter (type IN (...)), not a count
--   * list_radar_global — a public LISTING (json_agg + limit), a separate column-mapping concern
--   * already-correct readers of public.webinars: list_webinars_v2, get_comms_pipeline,
--     webinars_pending_comms
--
-- "Completed/realized" predicate (D-M8-COMPLETED, recommend-and-proceed): the webinars table has
-- NO 'done'/'completed' status (statuses live = planned/confirmed), so realized = scheduled_at < now()
-- — robust to the missing enum value (all 7 rows are past-dated today, so realized = all = 7).
--
-- Each surface keeps ITS OWN existing window literal (the cross-metric cycle-source convergence,
-- ADR-0100 §2.1 / audit D11, is a separate concern and intentionally out of this PR's scope).

-- ── Canonical primitive ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_webinars_count(
  p_start date DEFAULT NULL,
  p_end   date DEFAULT NULL,
  p_mode  text DEFAULT 'realized'
) RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COUNT(*)::int
  FROM public.webinars w
  WHERE (p_start IS NULL OR w.scheduled_at::date >= p_start)
    AND (p_end   IS NULL OR w.scheduled_at::date <= p_end)
    AND CASE lower(p_mode)
          WHEN 'realized' THEN w.scheduled_at < now()
          WHEN 'planned'  THEN w.scheduled_at >= now()
          ELSE true                 -- 'all'
        END;
$function$;

COMMENT ON FUNCTION public.get_webinars_count(date, date, text) IS
  '#419 metric 8 canonical webinars count. Source = public.webinars table (architectural source of truth, CLAUDE.md #4), NOT events.type=''webinar''. p_mode: realized (scheduled_at<now), planned (>=now), all. p_start/p_end optional date window on scheduled_at::date.';

REVOKE ALL ON FUNCTION public.get_webinars_count(date, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_webinars_count(date, date, text) TO authenticated, service_role, anon;

-- ── Surface repoints (same-signature CREATE OR REPLACE; only the webinar line changed) ───────────
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
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.members m
        WHERE m.cpmai_certified = true
          AND m.current_cycle_active = true AND m.is_active = true
          AND m.cpmai_certified_at >= v_year_start;

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
        'current', (SELECT count(*) FROM members WHERE is_active AND cpmai_certified = true),
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

CREATE OR REPLACE FUNCTION public.exec_cycle_report(p_cycle_code text DEFAULT 'cycle3-2026'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb; v_kpis jsonb; v_members jsonb; v_tribes jsonb;
  v_production jsonb; v_engagement jsonb; v_curation jsonb; v_cycle jsonb; v_attendance jsonb; v_att_by_tribe jsonb;
  v_total_members int; v_active_members int;
  v_start date := '2026-01-01';
  v_end date := '2026-06-30';
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  -- ADR-0042: V4 catalog (manage_platform writes; view_chapter_dashboards reads)
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
  END IF;

  SELECT jsonb_build_object(
    'code', COALESCE(c.cycle_code, p_cycle_code),
    'name', COALESCE(c.cycle_label, 'Ciclo 3 — 2026/1'),
    'start_date', c.cycle_start, 'end_date', c.cycle_end
  ) INTO v_cycle FROM public.cycles c WHERE c.cycle_code = p_cycle_code OR c.is_current = true LIMIT 1;
  IF v_cycle IS NULL THEN v_cycle := jsonb_build_object('code', p_cycle_code, 'name', 'Ciclo 3', 'start_date', v_start, 'end_date', v_end); END IF;

  v_kpis := public.get_kpi_dashboard(v_start, v_end);

  SELECT COUNT(*) INTO v_total_members FROM public.members;
  SELECT COUNT(*) INTO v_active_members FROM public.members WHERE current_cycle_active = true;

  SELECT jsonb_build_object(
    'total', v_total_members, 'active', v_active_members,
    'by_chapter', COALESCE((SELECT jsonb_agg(jsonb_build_object('chapter', chapter, 'count', cnt) ORDER BY cnt DESC) FROM (SELECT chapter, count(*) AS cnt FROM public.members WHERE current_cycle_active = true AND chapter IS NOT NULL GROUP BY chapter) sub), '[]'::jsonb),
    'by_role', COALESCE((SELECT jsonb_agg(jsonb_build_object('role', operational_role, 'count', cnt) ORDER BY cnt DESC) FROM (SELECT COALESCE(operational_role, 'none') AS operational_role, count(*) AS cnt FROM public.members WHERE current_cycle_active = true GROUP BY operational_role) sub), '[]'::jsonb),
    'retention_rate', ROUND(COALESCE((SELECT COUNT(*) FILTER (WHERE COALESCE(array_length(cycles, 1), 0) > 1)::numeric * 100 / NULLIF(COUNT(*), 0) FROM public.members WHERE current_cycle_active = true AND cycles IS NOT NULL), 0)),
    'new_this_cycle', (SELECT COUNT(*) FROM public.members WHERE current_cycle_active = true AND (cycles IS NULL OR COALESCE(array_length(cycles, 1), 0) <= 1))
  ) INTO v_members;

  SELECT COALESCE(jsonb_agg(tribe_data ORDER BY tribe_data->>'name'), '[]'::jsonb) INTO v_tribes
  FROM (SELECT jsonb_build_object('id', t.id, 'name', t.name,
    'leader', COALESCE((SELECT m.name FROM public.members m WHERE m.tribe_id = t.id AND m.operational_role = 'tribe_leader' LIMIT 1), '—'),
    'member_count', (SELECT COUNT(*) FROM public.members m WHERE m.tribe_id = t.id AND m.current_cycle_active = true),
    'board_items_total', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived'), 0),
    'board_items_completed', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status = 'done'), 0),
    'completion_pct', COALESCE((SELECT ROUND(COUNT(*) FILTER (WHERE bi.status = 'done')::numeric * 100 / NULLIF(COUNT(*), 0)) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived'), 0),
    'articles_produced', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status IN ('done', 'published') AND (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')), 0)
  ) AS tribe_data FROM public.tribes t WHERE t.is_active = true) sub;

  SELECT jsonb_build_object(
    'articles_submitted', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')), 0),
    'articles_published', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%') AND bi.status IN ('done', 'published')), 0),
    'articles_in_review', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%') AND bi.status IN ('review', 'in_progress')), 0),
    'webinars_completed', public.get_webinars_count(NULL, NULL, 'realized'),
    'webinars_planned', public.get_webinars_count(NULL, NULL, 'planned')
  ) INTO v_production;

  SELECT jsonb_build_object(
    'total_events', (SELECT COUNT(*) FROM public.events WHERE date BETWEEN v_start AND v_end),
    'total_attendance_hours', COALESCE((SELECT round(sum(COALESCE(e.duration_actual, e.duration_minutes, 60)::numeric * (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present)) / 60) FROM events e WHERE e.date BETWEEN v_start AND v_end), 0),
    'avg_attendance_per_event', COALESCE((SELECT ROUND(AVG(ac)) FROM (SELECT COUNT(*) AS ac FROM public.attendance a JOIN events e ON e.id = a.event_id WHERE a.present = true AND e.date BETWEEN v_start AND v_end GROUP BY a.event_id) sub), 0),
    'total_attendance_records', (SELECT COUNT(*) FROM public.attendance WHERE present = true),
    'certification_completion_rate', ROUND(COALESCE((SELECT COUNT(*) FILTER (WHERE cpmai_certified = true)::numeric * 100 / NULLIF(COUNT(*), 0) FROM public.members WHERE current_cycle_active = true), 0))
  ) INTO v_engagement;

  SELECT jsonb_build_object(
    'items_submitted', COALESCE((SELECT COUNT(*) FROM public.curation_review_log), 0),
    'items_approved', COALESCE((SELECT COUNT(*) FROM public.curation_review_log WHERE decision = 'approved'), 0),
    'items_in_review', COALESCE((SELECT COUNT(*) FROM public.board_items WHERE status = 'review'), 0),
    'avg_review_days', COALESCE((SELECT ROUND(AVG(EXTRACT(EPOCH FROM (completed_at - created_at)) / 86400)::numeric, 1) FROM public.curation_review_log), 0),
    'sla_compliance_rate', COALESCE((SELECT ROUND(COUNT(*) FILTER (WHERE completed_at <= due_date)::numeric * 100 / NULLIF(COUNT(*) FILTER (WHERE due_date IS NOT NULL), 0)) FROM public.curation_review_log), 0)
  ) INTO v_curation;

  -- p277 #419 m3 PR5a: attendance DECOUPLED from get_attendance_summary (D9 — drop the hidden 0.4/0.6
  -- combined_pct weighting). Per-tribe headline = ENGAGEMENT (present/eligible, cycles.is_current window);
  -- the RELIABILITY diagnostic ships alongside WITH raw present/absent/excused counts. at_risk_count now
  -- counts engagement < 0.50 (genuine no-show), not the old combined_pct band.
  SELECT COALESCE(jsonb_agg(att_row ORDER BY att_row->>'tribe_name'), '[]'::jsonb) INTO v_att_by_tribe
  FROM (SELECT jsonb_build_object('tribe_id', t.id, 'tribe_name', t.name,
    'members_count', (SELECT count(*) FROM members m WHERE m.tribe_id = t.id AND m.is_active AND m.operational_role NOT IN ('sponsor','chapter_liaison','guest','none')),
    'engagement_pct', ROUND(COALESCE((eng.j ->> 'avg_rate')::numeric, 0) * 100, 1),
    'reliability_pct', ROUND(COALESCE((rel.j ->> 'avg_rate')::numeric, 0) * 100, 1),
    'present_total', COALESCE((rel.j ->> 'present_total')::int, 0),
    'absent_total', COALESCE((rel.j ->> 'absent_total')::int, 0),
    'excused_total', COALESCE((rel.j ->> 'excused_total')::int, 0),
    'at_risk_count', COALESCE((eng.j ->> 'at_risk_count')::int, 0)
  ) AS att_row
  FROM tribes t
  CROSS JOIN LATERAL (SELECT public.get_attendance_engagement_summary('tribe', t.id) AS j) eng
  CROSS JOIN LATERAL (SELECT public.get_attendance_reliability_summary('tribe', t.id) AS j) rel
  WHERE t.is_active = true) sub;

  v_attendance := jsonb_build_object(
    'engagement', public.get_attendance_engagement_summary('global'),
    'reliability', public.get_attendance_reliability_summary('global'),
    'by_tribe', v_att_by_tribe
  );

  v_result := jsonb_build_object('cycle', v_cycle, 'kpis', v_kpis, 'members', v_members, 'tribes', v_tribes, 'production', v_production, 'engagement', v_engagement, 'curation', v_curation, 'attendance', v_attendance);
  RETURN v_result;
END; $function$;

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
    'cpmai_certified_count', (SELECT count(*) FROM public.members WHERE cpmai_certified = true),
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

CREATE OR REPLACE FUNCTION public.get_public_impact_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'chapters', (SELECT COUNT(DISTINCT chapter) FROM members WHERE is_active = true AND chapter IS NOT NULL),
    'active_members', (SELECT COUNT(*) FROM members WHERE is_active = true AND current_cycle_active = true),
    'tribes', (SELECT COUNT(*) FROM tribes),
    'articles_published', (SELECT COUNT(*) FROM public_publications WHERE is_published = true),
    'articles_approved', (
      SELECT COUNT(*) FROM board_lifecycle_events WHERE action = 'curation_review' AND new_status = 'approved'
    ),
    'total_events', (SELECT COUNT(*) FROM events WHERE date >= '2026-03-01'),
    'total_attendance_hours', (
      SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
      FROM attendance a JOIN events e ON e.id = a.event_id
      WHERE e.date >= '2026-03-01'
    ),
    'impact_hours', (
      SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
      FROM attendance a JOIN events e ON e.id = a.event_id
    ),
    'webinars', public.get_webinars_count(NULL, NULL, 'all'),
    'ia_pilots', (SELECT COUNT(*) FROM ia_pilots WHERE status IN ('active','completed')),
    'partner_count', (SELECT COUNT(*) FROM partner_entities WHERE status = 'active'),
    'courses_count', (SELECT COUNT(*) FROM courses),
    'recent_publications', COALESCE((
      SELECT jsonb_agg(sub ORDER BY sub.publication_date DESC NULLS LAST)
      FROM (SELECT title, authors, external_platform AS platform, publication_date, external_url
            FROM public_publications WHERE is_published = true
            ORDER BY publication_date DESC NULLS LAST LIMIT 5) sub
    ), '[]'::jsonb),
    'tribes_summary', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'quadrant_name', t.quadrant_name,
        'member_count', (SELECT COUNT(*) FROM members m WHERE m.tribe_id = t.id AND m.is_active),
        'leader_name', (SELECT name FROM members WHERE id = t.leader_member_id)
      ) ORDER BY t.id)
      FROM tribes t
    ), '[]'::jsonb),
    'chapters_summary', COALESCE((
      SELECT jsonb_agg(row_to_json(ch)::jsonb)
      FROM (
        SELECT m.chapter,
               COUNT(*) as member_count,
               (SELECT ms.name FROM members ms WHERE ms.chapter = m.chapter AND 'sponsor' = ANY(ms.designations) AND ms.is_active LIMIT 1) as sponsor
        FROM members m WHERE m.is_active AND m.chapter IS NOT NULL
        GROUP BY m.chapter
      ) ch
    ), '[]'::jsonb),
    'partners', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('name', name, 'type', entity_type, 'status', status))
      FROM partner_entities WHERE status = 'active'
    ), '[]'::jsonb),
    'recognitions', jsonb_build_array(
      jsonb_build_object(
        'title', 'Finalista — Prêmio "Carlos Novello" Voluntário do Ano',
        'organization', 'PMI LATAM Excellence Awards 2025',
        'recipient', 'Vitor Maia Rodovalho (GP)',
        'date', '2026-02-26',
        'category', 'Volunteer of the Year — LATAM Brasil',
        'description', 'Nomeado pelo PMI Goiás pelo trabalho à frente do Núcleo de IA & GP'
      )
    ),
    'timeline', jsonb_build_array(
      jsonb_build_object('year', '2024', 'title', 'Fase Piloto', 'description', 'Concepção pelo PMI-GO. Patrocínio Ivan Lourenço. Experimentação e lições aprendidas.'),
      jsonb_build_object('year', '2025.1', 'title', 'Oficialização', 'description', 'Parceria PMI-GO + PMI-CE. 7 artigos submetidos ao ProjectManagement.com. 1º Webinar.'),
      jsonb_build_object('year', '2025.2', 'title', 'Amadurecimento', 'description', 'Manual de Governança R2. 13 pesquisadores selecionados. Expansão para PMI-DF, PMI-MG, PMI-RS.'),
      jsonb_build_object('year', '2026', 'title', 'Escala', 'description', '44+ colaboradores, 8 tribos, 5 capítulos PMI. Plataforma digital própria. Processo seletivo estruturado.')
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;
