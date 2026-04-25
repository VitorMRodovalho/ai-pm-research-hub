-- Track Q-A Batch G — orphan recovery: sustainability finance (8 fns)
--
-- Captures live bodies as-of 2026-04-25 for cost/revenue/KPI surface.
-- Bodies preserved verbatim from `pg_get_functiondef` — no behavior change.
--
-- Notes:
-- - Authority: legacy `is_superadmin OR operational_role='manager'`. V4
--   migration deferred to Phase B drift cleanup.
-- - get_annual_kpis is the largest in-batch surface (~5KB body) — fans out
--   computed values from board_items / events / pilots / members /
--   cost_entries via the v_auto_values jsonb dispatch keyed by
--   annual_kpi_targets.auto_query.
-- - get_sustainability_projections has hardcoded 'YYYY-MM' format and
--   relies on infrastructure cost_categories.name.

CREATE OR REPLACE FUNCTION public.delete_cost_entry(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF NOT EXISTS (
    SELECT 1 FROM public.members WHERE auth_id = v_caller_id
    AND (is_superadmin = true OR operational_role = 'manager')
  ) THEN
    RAISE EXCEPTION 'Only managers/superadmins can delete cost entries';
  END IF;
  DELETE FROM public.cost_entries WHERE id = p_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_revenue_entry(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF NOT EXISTS (
    SELECT 1 FROM public.members WHERE auth_id = v_caller_id
    AND (is_superadmin = true OR operational_role = 'manager')
  ) THEN
    RAISE EXCEPTION 'Only managers/superadmins can delete revenue entries';
  END IF;
  DELETE FROM public.revenue_entries WHERE id = p_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_annual_kpis(p_cycle integer DEFAULT 4, p_year integer DEFAULT 2026)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
  v_auto_values jsonb;
  v_kpis jsonb;
  v_cycle_start date := '2025-12-01';
  v_cycle_end date := '2026-06-30';
BEGIN
  v_auto_values := jsonb_build_object(
    'pilots_active_or_completed', (
      SELECT count(*) FROM public.pilots WHERE status IN ('active', 'completed')
    ),
    'publications_submitted_count', (
      SELECT count(*) FROM public.board_items bi
      JOIN board_item_tag_assignments bita ON bita.board_item_id = bi.id
      JOIN tags t ON t.id = bita.tag_id
      WHERE t.name = 'publicacao' AND bi.status IN ('done', 'review')
    ),
    'articles_academic_count', (
      SELECT count(*) FROM public.board_items bi
      JOIN board_item_tag_assignments bita ON bita.board_item_id = bi.id
      JOIN tags t ON t.id = bita.tag_id
      WHERE t.name = 'artigo_academico' AND bi.status IN ('done', 'review')
    ),
    'frameworks_delivered_count', (
      SELECT count(*) FROM public.board_items bi
      JOIN board_item_tag_assignments bita ON bita.board_item_id = bi.id
      JOIN tags t ON t.id = bita.tag_id
      WHERE t.name IN ('framework', 'ferramenta') AND bi.status IN ('done', 'review')
    ),
    'webinars_realized_count', (
      SELECT count(DISTINCT e.id) FROM public.events e
      JOIN event_tag_assignments eta ON eta.event_id = e.id
      JOIN tags t ON t.id = eta.tag_id
      WHERE t.name = 'webinar' AND e.date BETWEEN v_cycle_start AND LEAST(v_cycle_end, CURRENT_DATE)
    ),
    -- FIXED: attendance now includes geral + tribo + 1on1 + lideranca
    'attendance_general_avg_pct', calc_attendance_pct(),
    'retention_pct', (
      SELECT ROUND(
        count(*) FILTER (WHERE is_active = true AND current_cycle_active = true)::numeric
        / NULLIF(count(*), 0) * 100, 1
      )
      FROM public.members
      WHERE operational_role NOT IN ('visitor', 'candidate')
      AND is_active = true
    ),
    'events_total_count', (
      SELECT count(*) FROM public.events e
      WHERE e.date BETWEEN v_cycle_start AND LEAST(v_cycle_end, CURRENT_DATE)
      AND NOT EXISTS (
        SELECT 1 FROM event_tag_assignments eta
        JOIN tags t ON t.id = eta.tag_id
        WHERE eta.event_id = e.id AND t.name = 'interview'
      )
    ),
    'trail_completion_pct', calc_trail_completion_pct(),
    'cpmai_certified_count', (
      SELECT count(*) FROM public.members WHERE cpmai_certified = true
    ),
    'active_members_count', (
      SELECT count(*) FROM public.members WHERE is_active = true AND current_cycle_active = true
    ),
    'infra_cost_current', (
      SELECT COALESCE(SUM(ce.amount_brl), 0)
      FROM public.cost_entries ce
      JOIN public.cost_categories cc ON cc.id = ce.category_id
      WHERE cc.name = 'infrastructure'
        AND ce.date >= date_trunc('month', now())::date
        AND ce.date < (date_trunc('month', now()) + interval '1 month')::date
    )
  );

  SELECT jsonb_agg(
    jsonb_build_object(
      'id', k.id, 'kpi_key', k.kpi_key,
      'label_pt', k.kpi_label_pt, 'label_en', k.kpi_label_en,
      'category', k.category,
      'target', k.target_value, 'baseline', k.baseline_value,
      'current', CASE
        WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query
        THEN (v_auto_values->>k.auto_query)::numeric
        ELSE k.current_value
      END,
      'unit', k.target_unit, 'icon', k.icon,
      'progress_pct', CASE
        WHEN k.target_value > 0 THEN ROUND(
          COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query
          THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0)
          / k.target_value * 100, 1)
        WHEN k.target_value = 0 THEN 100
        ELSE 0
      END,
      'health', CASE
        WHEN k.target_value = 0 AND COALESCE(
          CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query
          THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) = 0 THEN 'achieved'
        WHEN k.target_value = 0 THEN 'at_risk'
        WHEN COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query
          THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) >= k.target_value THEN 'achieved'
        WHEN COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query
          THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) >= k.target_value * 0.7 THEN 'on_track'
        WHEN COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query
          THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) >= k.target_value * 0.4 THEN 'at_risk'
        ELSE 'behind'
      END,
      'notes', k.notes, 'auto_query', k.auto_query
    ) ORDER BY k.display_order
  )
  INTO v_kpis
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

CREATE OR REPLACE FUNCTION public.get_cost_entries(p_category_name text DEFAULT NULL::text, p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_limit integer DEFAULT 100)
 RETURNS TABLE(id uuid, category_name text, category_description text, description text, amount_brl numeric, date date, paid_by text, event_title text, submission_title text, notes text, created_by_name text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    ce.id,
    cc.name AS category_name,
    cc.description AS category_description,
    ce.description,
    ce.amount_brl,
    ce.date,
    ce.paid_by,
    e.title AS event_title,
    ps.title AS submission_title,
    ce.notes,
    m.name AS created_by_name,
    ce.created_at
  FROM public.cost_entries ce
  JOIN public.cost_categories cc ON cc.id = ce.category_id
  LEFT JOIN public.events e ON e.id = ce.event_id
  LEFT JOIN public.publication_submissions ps ON ps.id = ce.submission_id
  LEFT JOIN public.members m ON m.id = ce.created_by
  WHERE (p_category_name IS NULL OR cc.name = p_category_name)
    AND (p_date_from IS NULL OR ce.date >= p_date_from)
    AND (p_date_to IS NULL OR ce.date <= p_date_to)
  ORDER BY ce.date DESC, ce.created_at DESC
  LIMIT p_limit;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_revenue_entries(p_category_name text DEFAULT NULL::text, p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_limit integer DEFAULT 100)
 RETURNS TABLE(id uuid, category_name text, category_description text, value_type text, description text, amount_brl numeric, date date, notes text, created_by_name text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    re.id,
    rc.name AS category_name,
    rc.description AS category_description,
    re.value_type,
    re.description,
    re.amount_brl,
    re.date,
    re.notes,
    m.name AS created_by_name,
    re.created_at
  FROM public.revenue_entries re
  JOIN public.revenue_categories rc ON rc.id = re.category_id
  LEFT JOIN public.members m ON m.id = re.created_by
  WHERE (p_category_name IS NULL OR rc.name = p_category_name)
    AND (p_date_from IS NULL OR re.date >= p_date_from)
    AND (p_date_to IS NULL OR re.date <= p_date_to)
  ORDER BY re.date DESC, re.created_at DESC
  LIMIT p_limit;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_sustainability_projections(p_months_ahead integer DEFAULT 6)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
  v_monthly_avg numeric;
  v_active_count integer;
  v_total_ytd numeric;
  v_months_elapsed integer;
  v_projections jsonb;
BEGIN
  SELECT count(*) INTO v_active_count FROM public.members WHERE is_active = true;

  SELECT COALESCE(SUM(amount_brl), 0) INTO v_total_ytd
  FROM public.cost_entries
  WHERE date >= date_trunc('year', now())::date;

  v_months_elapsed := GREATEST(EXTRACT(MONTH FROM now())::integer, 1);
  v_monthly_avg := v_total_ytd / v_months_elapsed;

  SELECT jsonb_agg(
    jsonb_build_object(
      'month', to_char(month_date, 'YYYY-MM'),
      'projected_cost', ROUND(v_monthly_avg, 2),
      'projected_cost_per_member', CASE
        WHEN v_active_count > 0 THEN ROUND(v_monthly_avg / v_active_count, 2)
        ELSE 0
      END,
      'cumulative', ROUND(v_monthly_avg * row_num, 2)
    ) ORDER BY month_date
  )
  INTO v_projections
  FROM (
    SELECT
      (date_trunc('month', now()) + (generate_series(1, p_months_ahead) || ' months')::interval)::date AS month_date,
      generate_series(1, p_months_ahead) AS row_num
  ) months;

  v_result := jsonb_build_object(
    'ytd_total', v_total_ytd,
    'monthly_avg', ROUND(v_monthly_avg, 2),
    'cost_per_member_monthly', CASE
      WHEN v_active_count > 0 THEN ROUND(v_monthly_avg / v_active_count, 2)
      ELSE 0
    END,
    'active_members', v_active_count,
    'months_elapsed', v_months_elapsed,
    'zero_cost_achieved', v_total_ytd = 0,
    'projections', COALESCE(v_projections, '[]'::jsonb),
    'infra_breakdown', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'service', ce.description,
        'monthly_cost', ce.amount_brl,
        'paid_by', ce.paid_by
      ))
      FROM (
        SELECT ce2.description, ce2.amount_brl, ce2.paid_by
        FROM public.cost_entries ce2
        JOIN public.cost_categories cc ON cc.id = ce2.category_id
        WHERE cc.name = 'infrastructure'
        ORDER BY ce2.date DESC
        LIMIT 10
      ) ce
    ), '[]'::jsonb)
  );

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_kpi_target(p_kpi_id uuid, p_target_value numeric DEFAULT NULL::numeric, p_current_value numeric DEFAULT NULL::numeric, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role = 'manager')
  ) THEN
    RAISE EXCEPTION 'Only GP/superadmin can update KPI targets';
  END IF;

  UPDATE annual_kpi_targets SET
    target_value = COALESCE(p_target_value, target_value),
    current_value = COALESCE(p_current_value, current_value),
    notes = COALESCE(p_notes, notes),
    updated_at = now()
  WHERE id = p_kpi_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_sustainability_kpi(p_id uuid, p_target_value numeric DEFAULT NULL::numeric, p_current_value numeric DEFAULT NULL::numeric, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF NOT EXISTS (
    SELECT 1 FROM public.members WHERE auth_id = v_caller_id
    AND (is_superadmin = true OR operational_role = 'manager')
  ) THEN
    RAISE EXCEPTION 'Only managers/superadmins can update sustainability KPIs';
  END IF;

  UPDATE public.sustainability_kpi_targets SET
    target_value = COALESCE(p_target_value, target_value),
    current_value = COALESCE(p_current_value, current_value),
    notes = COALESCE(p_notes, notes),
    updated_at = now()
  WHERE id = p_id;
END;
$function$;
