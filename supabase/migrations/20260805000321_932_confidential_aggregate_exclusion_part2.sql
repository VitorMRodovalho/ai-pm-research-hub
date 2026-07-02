-- #932 (follow-up to #785 Tier 2): universal confidential exclusion from shared aggregate readers — PART 2.
--
-- Part 1 (mig 320) covered the CONTENT leaks + public + canonical impact-hours. Part 2 covers the
-- remaining COUNT-ONLY aggregates over board/event tables. Policy (unchanged, PM 2026-07-02): a
-- confidential initiative's board_items / events / the initiative row NEVER count in shared aggregates,
-- for EVERYONE incl GP. UNIVERSAL exclusion via the session-BLIND helpers from mig 320
-- (is_confidential_initiative / is_confidential_board), NOT rls_can_see_initiative (which GP passes).
--
-- Predicate idiom (helpers, NULL-safe — org-level events/boards with NULL initiative stay counted):
--   board_items aggregates -> AND NOT public.is_confidential_board(<board_id>)
--   events aggregates      -> AND NOT public.is_confidential_initiative(<initiative_id>)
--   initiatives direct      -> AND visibility <> 'confidential'
--
-- Live grounding 2026-07-02 (1 confidential initiative, 1 board / 24 items / 0 is_portfolio_item,
-- 10 events / 3 present attendance). antes->depois of the touched aggregates:
--   exec_portfolio_health.meeting_hours  281 -> 271   (-10h confidential events)
--   get_kpi_dashboard 'Horas de Impacto' 851 -> 848   (-3 present-weighted)
--   get_admin_dashboard deliverables     31/276 -> 29/252  (done/total, -2/-24 confidential items)
--   get_cycle_evolution events_c3/items/att  375/276/1481 -> 365/252/1478
--   get_annual_kpis events_total_count   160 -> 150
--   get_pilot_metrics active_boards/events/attendance  +1/+10/+3 removed
--   exec_portfolio_board_summary: confidential cross_functional lane (24 cards) drops out
--   _artia_safe_monthly_metrics: events-in-month + initiatives_active (-1) + publicacao count
--   get_tags: per-tag event_count drops confidential event-tag assignments
-- The tag-keyed board counts (get_annual_kpis publications/articles/frameworks, get_tags board side)
-- and get_pilot_metrics artifacts_with_baseline are latent today (confidential board has 0 tagged /
-- 0 portfolio items) but hardened for the invariant. get_portfolio_dashboard / get_portfolio_timeline
-- remain allowlisted (they already filter is_portfolio_item=true; 0 confidential portfolio items).
--
-- NOTE: applied to prod via a machine transform (pg_get_functiondef + anchored replace + md5 assert)
-- so the untouched 95% of each body is preserved from live; these CREATE OR REPLACE blocks are the
-- byte-equivalent capture (verified: live md5(normalized) == this file's bodies via Phase C drift gate).

CREATE OR REPLACE FUNCTION public._artia_safe_monthly_metrics(p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_start DATE := make_date(p_year, p_month, 1);
  v_end DATE := (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date;
  v_event_count INT;
  v_duration_h NUMERIC;
  v_active_volunteers INT;
  v_initiatives_count INT;
  v_publications INT;
  v_pilots_active INT;
BEGIN
  SELECT COUNT(*), COALESCE(ROUND(SUM(duration_minutes)::numeric / 60, 1), 0)
  INTO v_event_count, v_duration_h
  FROM public.events
  WHERE date BETWEEN v_start AND v_end AND NOT public.is_confidential_initiative(initiative_id);

  SELECT COUNT(DISTINCT m.id) INTO v_active_volunteers
  FROM public.members m
  WHERE m.is_active = true;

  SELECT COUNT(*) INTO v_initiatives_count
  FROM public.initiatives
  WHERE status = 'active' AND visibility <> 'confidential';

  SELECT COUNT(*) INTO v_publications
  FROM public.board_items
  WHERE status = 'done' AND tags && ARRAY['publicacao']
    AND updated_at BETWEEN v_start AND v_end::timestamp AND NOT public.is_confidential_board(board_id);

  SELECT COUNT(*) INTO v_pilots_active
  FROM public.pilots
  WHERE status IN ('active','completed');

  RETURN jsonb_build_object(
    'period', jsonb_build_object('year', p_year, 'month', p_month, 'start', v_start, 'end', v_end),
    'events_in_month', v_event_count,
    'duration_hours_in_month', v_duration_h,
    'active_volunteers_total', v_active_volunteers,
    'initiatives_active_total', v_initiatives_count,
    'publications_done_in_month', v_publications,
    'pilots_active_total', v_pilots_active
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.exec_portfolio_board_summary(p_include_inactive boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH boards AS (
    SELECT
      pb.id AS board_id, pb.board_name, pb.board_scope,
      COALESCE(pb.domain_key, 'tribe_general') AS domain_key,
      i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name
    FROM public.project_boards pb
    LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
    WHERE (p_include_inactive OR pb.is_active = true) AND NOT public.is_confidential_board(pb.id)
  ),
  items AS (
    SELECT
      b.board_scope, b.domain_key,
      count(bi.id) AS total_cards,
      count(*) FILTER (WHERE bi.status = 'backlog') AS backlog,
      count(*) FILTER (WHERE bi.status = 'todo') AS todo,
      count(*) FILTER (WHERE bi.status = 'in_progress') AS in_progress,
      count(*) FILTER (WHERE bi.status = 'review') AS review,
      count(*) FILTER (WHERE bi.status = 'done') AS done,
      count(*) FILTER (WHERE bi.status = 'archived') AS archived,
      count(*) FILTER (WHERE bi.assignee_id IS NULL AND bi.status <> 'archived') AS orphan_cards,
      count(*) FILTER (WHERE bi.due_date::date < current_date AND bi.status NOT IN ('done', 'archived')) AS overdue_cards
    FROM boards b
    LEFT JOIN public.board_items bi ON bi.board_id = b.board_id
    GROUP BY b.board_scope, b.domain_key
  )
  SELECT jsonb_build_object(
    'generated_at', now(),
    'by_lane', COALESCE(jsonb_agg(jsonb_build_object(
      'board_scope', i.board_scope, 'domain_key', i.domain_key,
      'total_cards', i.total_cards, 'backlog', i.backlog, 'todo', i.todo,
      'in_progress', i.in_progress, 'review', i.review, 'done', i.done,
      'archived', i.archived, 'orphan_cards', i.orphan_cards, 'overdue_cards', i.overdue_cards
    ) ORDER BY i.board_scope, i.domain_key), '[]'::jsonb)
  )
  FROM items i;
$function$;

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
        v_current := (public.get_chapter_metrics()->>'signed')::numeric;

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
          AND bi.created_at >= v_year_start::timestamptz AND NOT public.is_confidential_board(bi.board_id);

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
        WHERE e.date >= v_year_start AND e.date <= current_date AND NOT public.is_confidential_initiative(e.initiative_id);

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

CREATE OR REPLACE FUNCTION public.get_admin_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb; v_cycle_start date; v_current_cycle int;
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

  SELECT cycle_start,
    CASE WHEN cycle_code ~ '^\w+_\d+$' THEN substring(cycle_code from '\d+')::int ELSE sort_order END
  INTO v_cycle_start, v_current_cycle
  FROM public.cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-01-01'; END IF;
  IF v_current_cycle IS NULL THEN v_current_cycle := 3; END IF;

  SELECT jsonb_build_object(
    'generated_at', now(),
    'kpis', jsonb_build_object(
      -- #625: exclui a coorte pré-onboarding (helper C0) do numerador.
      'active_members', (SELECT count(*) FROM public.members WHERE is_active AND current_cycle_active AND NOT public.member_is_pre_onboarding(person_id, member_status)),
      -- #625: mesmo predicado no denominador da % para numerador e base ficarem consistentes.
      'adoption_7d', (SELECT ROUND(count(*) FILTER (WHERE last_seen_at > now() - interval '7 days')::numeric / NULLIF(count(*), 0) * 100, 1) FROM public.members WHERE is_active AND current_cycle_active AND NOT public.member_is_pre_onboarding(person_id, member_status)),
      'deliverables_completed', (SELECT count(*) FROM public.board_items WHERE status = 'done' AND NOT public.is_confidential_board(board_id)),
      'deliverables_total', (SELECT count(*) FROM public.board_items WHERE status != 'archived' AND NOT public.is_confidential_board(board_id)),
      'impact_hours', (SELECT COALESCE(public.get_impact_hours_excluding_excused(), 0)),
      'cpmai_current', (SELECT count(DISTINCT member_id) FROM public.gamification_points WHERE category = 'cert_cpmai' AND created_at >= v_cycle_start),
      'cpmai_target', (SELECT target_value FROM public.annual_kpi_targets WHERE kpi_key = 'cpmai_certified' AND cycle = v_current_cycle LIMIT 1),
      'chapters_current', (public.get_chapter_metrics()->>'signed')::int,
      'chapters_in_negotiation', (public.get_chapter_metrics()->>'in_negotiation')::int,
      'chapters_engaged', (public.get_chapter_metrics()->>'engaged')::int,
      'chapters_target', (SELECT target_value FROM public.annual_kpi_targets WHERE kpi_key = 'chapters_participating' AND cycle = v_current_cycle LIMIT 1)
    ),
    'alerts', (SELECT COALESCE(jsonb_agg(alert), '[]'::jsonb) FROM (
      SELECT jsonb_build_object(
        'severity', 'high',
        'message', count(*) || ' pesquisadores sem tribo',
        'action_label', 'Ir para Tribos',
        'action_href', '/admin/tribes'
      ) AS alert
      FROM public.members m
      WHERE m.is_active = true
        AND public.get_member_tribe(m.id) IS NULL
        AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'manager', 'deputy_manager', 'observer')
      HAVING count(*) > 0

      UNION ALL

      SELECT jsonb_build_object(
        'severity', 'medium',
        'message', count(*) || ' stakeholders sem conta',
        'action_label', 'Ver Membros',
        'action_href', '/admin/members'
      )
      FROM public.members
      WHERE is_active = true AND auth_id IS NULL AND operational_role IN ('sponsor', 'chapter_liaison')
      HAVING count(*) > 0

      UNION ALL

      SELECT jsonb_build_object(
        'severity', 'medium',
        'message', count(*) || ' membros em risco de dropout',
        'action_label', 'Ver lista',
        'action_href', '/admin/members'
      )
      FROM public.members m
      WHERE m.is_active = true AND m.current_cycle_active
        AND public.get_member_tribe(m.id) IS NOT NULL
        AND m.id NOT IN (
          SELECT a.member_id FROM public.attendance a
          JOIN public.events e ON e.id = a.event_id
          WHERE e.date > now() - interval '60 days'
            AND a.present IS TRUE
        )
      HAVING count(*) > 0

      UNION ALL

      SELECT jsonb_build_object(
        'severity', 'high',
        'message', t.name || ' sem reuniao ha ' || (current_date - max(e.date)) || ' dias',
        'action_label', 'Ver Tribo',
        'action_href', '/tribe/' || t.id
      )
      FROM public.tribes t
      LEFT JOIN public.initiatives i ON i.legacy_tribe_id = t.id
      LEFT JOIN public.events e ON e.initiative_id = i.id AND e.type = 'tribo' AND e.date <= current_date
      WHERE t.is_active = true
      GROUP BY t.id, t.name
      HAVING max(e.date) IS NOT NULL AND current_date - max(e.date) > 14

      UNION ALL

      SELECT jsonb_build_object(
        'severity', 'medium',
        'message', count(*) || ' membros detractors (3+ faltas consecutivas)',
        'action_label', 'Quadro de Presenca',
        'action_href', '/attendance?tab=grid'
      )
      FROM public.members m
      WHERE m.is_active AND m.current_cycle_active
        AND public.get_member_tribe(m.id) IS NOT NULL
        AND m.id IN (
          SELECT cand.id
          FROM public.members cand
          WHERE cand.is_active AND cand.current_cycle_active
            AND (
              SELECT count(*) FILTER (WHERE NOT ranked.was_present)
              FROM (
                SELECT (att.present IS TRUE) AS was_present,
                       ROW_NUMBER() OVER (ORDER BY el.event_date DESC, el.event_id DESC) AS rn
                FROM public._attendance_eligible_events(cand.id, NULL) el
                LEFT JOIN public.attendance att ON att.event_id = el.event_id AND att.member_id = cand.id
                WHERE att.excused IS NOT TRUE
              ) ranked
              WHERE ranked.rn <= 3
            ) >= 3
        )
      HAVING count(*) > 0
    ) sub),
    'recent_activity', (SELECT COALESCE(jsonb_agg(r.activity ORDER BY r.ts DESC), '[]'::jsonb) FROM (
      SELECT * FROM (SELECT jsonb_build_object('type', 'audit', 'message', actor.name || ' ' || al.action || ' em ' || COALESCE(target.name, '?'), 'details', al.changes, 'timestamp', al.created_at) as activity, al.created_at as ts FROM public.admin_audit_log al LEFT JOIN public.members actor ON actor.id = al.actor_id LEFT JOIN public.members target ON target.id = al.target_id WHERE al.created_at > now() - interval '7 days' ORDER BY al.created_at DESC LIMIT 10) a1
      UNION ALL SELECT * FROM (SELECT jsonb_build_object('type', 'campaign', 'message', 'Campanha "' || ct.name || '" enviada', 'timestamp', cs.created_at), cs.created_at FROM public.campaign_sends cs JOIN public.campaign_templates ct ON ct.id = cs.template_id WHERE cs.created_at > now() - interval '7 days' ORDER BY cs.created_at DESC LIMIT 5) a2
      UNION ALL SELECT * FROM (SELECT jsonb_build_object('type', 'publication', 'message', m.name || ' submeteu "' || ps.title || '"', 'timestamp', ps.submission_date), ps.submission_date FROM public.publication_submissions ps JOIN public.publication_submission_authors psa ON psa.submission_id = ps.id JOIN public.members m ON m.id = psa.member_id WHERE ps.submission_date > now() - interval '30 days' ORDER BY ps.submission_date DESC LIMIT 5) a3
    ) r LIMIT 15)
  ) INTO v_result;
  RETURN v_result;
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
  IF v_caller_id IS NULL OR NOT (public.can_by_member(v_caller_id, 'view_internal_analytics') OR public.can_by_member(v_caller_id, 'view_aggregate_analytics')) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  v_auto_values := jsonb_build_object(
    'pilots_active_or_completed', (SELECT count(*) FROM public.pilots WHERE status IN ('active', 'completed')),
    'publications_submitted_count', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_tag_assignments bita ON bita.board_item_id = bi.id JOIN public.tags t ON t.id = bita.tag_id WHERE t.name = 'publicacao' AND bi.status IN ('done', 'review') AND NOT public.is_confidential_board(bi.board_id)),
    'articles_academic_count', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_tag_assignments bita ON bita.board_item_id = bi.id JOIN public.tags t ON t.id = bita.tag_id WHERE t.name = 'artigo_academico' AND bi.status IN ('done', 'review') AND NOT public.is_confidential_board(bi.board_id)),
    'frameworks_delivered_count', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_tag_assignments bita ON bita.board_item_id = bi.id JOIN public.tags t ON t.id = bita.tag_id WHERE t.name IN ('framework', 'ferramenta') AND bi.status IN ('done', 'review') AND NOT public.is_confidential_board(bi.board_id)),
    'webinars_realized_count', public.get_webinars_count(v_cycle_start, LEAST(v_cycle_end, CURRENT_DATE), 'realized'),
    'attendance_general_avg_pct', public.calc_attendance_pct(),
    -- #692: members_retained now reads the canonical cohort-survival headline (was a degenerate
    -- is_active∧current/is_active ratio that read ~98.7).
    'retention_pct', (public.get_member_retention_canonical() -> 'headline' ->> 'survival_pct')::numeric,
    'events_total_count', (SELECT count(*) FROM public.events e WHERE e.date BETWEEN v_cycle_start AND LEAST(v_cycle_end, CURRENT_DATE) AND NOT EXISTS (SELECT 1 FROM public.event_tag_assignments eta JOIN public.tags t ON t.id = eta.tag_id WHERE eta.event_id = e.id AND t.name = 'interview') AND NOT public.is_confidential_initiative(e.initiative_id)),
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

CREATE OR REPLACE FUNCTION public.get_cycle_evolution()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE result jsonb; v_c2_members int; v_c3_members int;
BEGIN
  SELECT count(DISTINCT member_id) INTO v_c2_members FROM member_cycle_history WHERE cycle_code = 'cycle_2';
  SELECT count(DISTINCT member_id) INTO v_c3_members FROM member_cycle_history WHERE cycle_code = 'cycle_3';

  SELECT jsonb_build_object(
    'cycles', jsonb_build_array(
      jsonb_build_object('cycle_code', 'pilot', 'cycle_label', 'Piloto 2024', 'members', 8,
        'chapters', 1, 'tribes', 0, 'events',
        (SELECT count(*) FROM events WHERE date BETWEEN '2024-06-01' AND '2024-12-31' AND title ILIKE '%Núcleo%'),
        'growth', null),
      jsonb_build_object('cycle_code', 'cycle_1', 'cycle_label', 'Ciclo 1 (2025/1)',
        'members', (SELECT count(DISTINCT member_id) FROM member_cycle_history WHERE cycle_code = 'cycle_1'),
        'chapters', 2, 'tribes', 5,
        'events', (SELECT count(*) FROM events WHERE date BETWEEN '2025-01-01' AND '2025-06-30'),
        'growth', ROUND(((SELECT count(DISTINCT member_id) FROM member_cycle_history WHERE cycle_code = 'cycle_1') - 8.0) / 8 * 100)),
      jsonb_build_object('cycle_code', 'cycle_2', 'cycle_label', 'Ciclo 2 (2025/2)',
        'members', v_c2_members, 'chapters', 2, 'tribes', 5,
        'events', (SELECT count(*) FROM events WHERE date BETWEEN '2025-07-01' AND '2025-12-31'),
        'growth', ROUND(((v_c2_members - (SELECT count(DISTINCT member_id) FROM member_cycle_history WHERE cycle_code = 'cycle_1')::numeric) / GREATEST((SELECT count(DISTINCT member_id) FROM member_cycle_history WHERE cycle_code = 'cycle_1'), 1)) * 100)),
      jsonb_build_object('cycle_code', 'cycle_3', 'cycle_label', 'Ciclo 3 (2026/1)',
        'members', v_c3_members, 'chapters', 5, 'tribes', 7,
        'events', (SELECT count(*) FROM events WHERE date >= '2026-01-01' AND NOT public.is_confidential_initiative(initiative_id)),
        'growth', CASE WHEN v_c2_members > 0 THEN ROUND(((v_c3_members - v_c2_members)::numeric / v_c2_members) * 100) ELSE 0 END)
    ),
    'highlights', jsonb_build_object(
      'new_chapters', 3, 'chapter_names', 'PMI-DF, PMI-MG, PMI-RS',
      'platform_version', 'v2.0.0', 'governance_digital', true, 'mcp_server', true,
      'total_articles', (SELECT count(*) FROM publication_submissions),
      'total_events_c3', (SELECT count(*) FROM events WHERE date >= '2026-01-01' AND NOT public.is_confidential_initiative(initiative_id)),
      'total_attendance', (SELECT count(*) FROM attendance a JOIN events e ON e.id = a.event_id WHERE a.present = true AND NOT public.is_confidential_initiative(e.initiative_id)),
      'active_members', (SELECT count(*) FROM members WHERE is_active AND current_cycle_active),
      'blog_posts', (SELECT count(*) FROM blog_posts),
      'change_requests', (SELECT count(*) FROM change_requests WHERE status != 'withdrawn'),
      'board_items', (SELECT count(*) FROM board_items WHERE status != 'archived' AND NOT public.is_confidential_board(board_id)),
      'gamification_points', (SELECT count(*) FROM gamification_points),
      'growth_c2_c3', CASE WHEN v_c2_members > 0 THEN ROUND(((v_c3_members - v_c2_members)::numeric / v_c2_members) * 100) ELSE 0 END
    )
  ) INTO result;
  RETURN result;
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
          FROM events e WHERE e.date BETWEEN p_cycle_start AND p_cycle_end AND NOT public.is_confidential_initiative(e.initiative_id)), 0),
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
          WHERE pb.board_name ILIKE '%publica%' AND bi.status IN ('done','published') AND NOT public.is_confidential_board(bi.board_id)),
        'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'publications_submitted' AND year = 2026), 10),
        'unit', '', 'icon', 'file-text'),
      jsonb_build_object(
        'name', 'Webinars Realizados',
        'current', public.get_webinars_count(p_cycle_start, p_cycle_end, 'realized'),
        'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'webinars_realized' AND year = 2026), 6),
        'unit', '', 'icon', 'video'),
      jsonb_build_object(
        'name', 'Capítulos Integrados',
        'current', (public.get_chapter_metrics()->>'signed')::int,
        'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'chapters_participating' AND year = 2026), 8),
        'unit', '', 'icon', 'map-pin')
    )
  ) INTO result;
  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_pilot_metrics(p_pilot_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_pilot record;
  v_metrics jsonb;
  v_auto_values jsonb := '{}';
BEGIN
  SELECT * INTO v_pilot FROM public.pilots WHERE id = p_pilot_id;
  IF v_pilot IS NULL THEN RETURN NULL; END IF;

  v_auto_values := jsonb_build_object(
    'active_members_count', (SELECT count(*) FROM public.v_active_members),  -- #419: canonical
    'adoption_pct', (
      SELECT ROUND(
        count(*) FILTER (WHERE auth_id IS NOT NULL AND onboarding_dismissed_at IS NOT NULL)::numeric
        / NULLIF(count(*) FILTER (WHERE is_active = true AND current_cycle_active = true), 0) * 100, 1
      )
      FROM public.members
    ),
    'artifacts_with_baseline', (
      SELECT count(*) FROM public.board_items bi
      WHERE bi.baseline_date IS NOT NULL AND bi.status != 'archived' AND NOT public.is_confidential_board(bi.board_id)
      AND EXISTS (
        SELECT 1 FROM board_item_tag_assignments bita
        JOIN tags t ON t.id = bita.tag_id
        WHERE bita.board_item_id = bi.id AND t.name = 'entregavel_lider'
      )
    ),
    'release_count', (SELECT count(*) FROM public.releases),
    'active_boards', (SELECT count(*) FROM public.project_boards WHERE is_active = true AND NOT public.is_confidential_board(id)),
    'total_events', (SELECT count(*) FROM public.events e WHERE NOT public.is_confidential_initiative(e.initiative_id)),
    'total_attendance', (SELECT count(*) FROM public.attendance a JOIN public.events e ON e.id = a.event_id WHERE NOT public.is_confidential_initiative(e.initiative_id)),
    'gamification_entries', (SELECT count(*) FROM public.gamification_points)
  );

  SELECT jsonb_agg(
    CASE
      WHEN m->>'auto_query' IS NOT NULL AND v_auto_values ? (m->>'auto_query')
      THEN m || jsonb_build_object('current', v_auto_values->(m->>'auto_query'))
      ELSE m
    END
  )
  INTO v_metrics
  FROM jsonb_array_elements(v_pilot.success_metrics) m;

  RETURN jsonb_build_object(
    'pilot', row_to_json(v_pilot),
    'metrics', COALESCE(v_metrics, '[]'::jsonb),
    'auto_values', v_auto_values,
    'days_active', CURRENT_DATE - v_pilot.started_at
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_tags(p_domain text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, name text, label_pt text, color text, tier tag_tier, domain tag_domain, description text, display_order integer, event_count bigint, board_item_count bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  SELECT t.id, t.name, t.label_pt, t.color, t.tier, t.domain, t.description, t.display_order,
    (SELECT count(*) FROM public.event_tag_assignments eta JOIN public.events e ON e.id = eta.event_id WHERE eta.tag_id = t.id AND NOT public.is_confidential_initiative(e.initiative_id)),
    (SELECT count(*) FROM public.board_item_tag_assignments bita JOIN public.board_items bi ON bi.id = bita.board_item_id WHERE bita.tag_id = t.id AND NOT public.is_confidential_board(bi.board_id))
  FROM public.tags t
  WHERE (p_domain IS NULL OR t.domain = p_domain::tag_domain OR t.domain = 'all')
  ORDER BY t.display_order;
END; $function$;

NOTIFY pgrst, 'reload schema';
