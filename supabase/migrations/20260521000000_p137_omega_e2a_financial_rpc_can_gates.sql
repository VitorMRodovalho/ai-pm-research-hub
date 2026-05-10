-- =====================================================================
-- p137 Ω-E.2-a — can() gates on 4 ungated SECDEF financial read RPCs
-- =====================================================================
-- Pre-state: 4 SECDEF financial RPCs lacked authority gates and bypassed
-- Ω-E.1's table-layer RLS, returning aggregated/listed financial data to
-- ANY authenticated caller (including ghost auths). RLS hardening from
-- p136 protected the tables but SECDEF functions ran in elevated context.
--
-- This migration adds the canonical `can_by_member(_, 'manage_finance')`
-- gate at each RPC entry point, mirroring the pattern already used in
-- create_cost_entry / create_revenue_entry / delete_cost_entry /
-- delete_revenue_entry / update_sustainability_kpi.
--
-- Affected RPCs:
--   1. get_sustainability_dashboard(p_cycle int) → jsonb
--   2. get_sustainability_projections(p_months_ahead int) → jsonb
--   3. get_cost_entries(...) → SETOF row
--   4. get_revenue_entries(...) → SETOF row
--
-- Pattern injected at top of body:
--   SELECT m.id INTO v_caller_member_id FROM members m
--     WHERE m.auth_id = auth.uid();
--   IF v_caller_member_id IS NULL THEN
--     RAISE EXCEPTION 'authentication_required'; END IF;
--   IF NOT can_by_member(v_caller_member_id, 'manage_finance') THEN
--     RAISE EXCEPTION 'permission_denied: manage_finance required'; END IF;
--
-- Out of scope (future Ω-E.2-b/c/d):
--   - sync-artia EF mcp_usage_log explicit organization_id
--   - NOT NULL constraint on organization_id (post-monitor 7-14d)
--   - ADR-0077 documenting auth_org() behavioral contract
--
-- Rollback: re-CREATE OR REPLACE without the gate (each function's body
-- pre-fix is preserved in git history at commit 1de9996 and earlier).
-- =====================================================================

-- ── 1. get_sustainability_dashboard ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_sustainability_dashboard(p_cycle integer DEFAULT 4)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_result jsonb;
  v_total_costs numeric;
  v_total_revenue numeric;
  v_active_count integer;
  v_costs_by_category jsonb;
  v_revenue_by_category jsonb;
  v_kpis jsonb;
  v_monthly_costs jsonb;
BEGIN
  SELECT m.id INTO v_caller_member_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required';
  END IF;
  IF NOT public.can_by_member(v_caller_member_id, 'manage_finance') THEN
    RAISE EXCEPTION 'permission_denied: manage_finance required to view sustainability dashboard';
  END IF;

  SELECT COALESCE(SUM(amount_brl), 0) INTO v_total_costs FROM public.cost_entries;
  SELECT COALESCE(SUM(amount_brl), 0) INTO v_total_revenue FROM public.revenue_entries WHERE value_type = 'monetary';
  SELECT count(*) INTO v_active_count FROM public.members WHERE is_active = true AND current_cycle_active = true;

  SELECT jsonb_agg(jsonb_build_object(
    'category', cc.name, 'description', cc.description,
    'total', COALESCE(sub.total, 0), 'count', COALESCE(sub.cnt, 0)
  ) ORDER BY cc.display_order)
  INTO v_costs_by_category
  FROM public.cost_categories cc
  LEFT JOIN (SELECT category_id, SUM(amount_brl) as total, COUNT(*) as cnt FROM public.cost_entries GROUP BY category_id) sub ON sub.category_id = cc.id;

  SELECT jsonb_agg(jsonb_build_object(
    'category', rc.name, 'description', rc.description, 'value_type', rc.value_type,
    'total', COALESCE(sub.total, 0), 'count', COALESCE(sub.cnt, 0)
  ) ORDER BY rc.display_order)
  INTO v_revenue_by_category
  FROM public.revenue_categories rc
  LEFT JOIN (SELECT category_id, SUM(amount_brl) as total, COUNT(*) as cnt FROM public.revenue_entries GROUP BY category_id) sub ON sub.category_id = rc.id;

  SELECT jsonb_agg(jsonb_build_object(
    'name', kpi_name, 'formula', kpi_formula, 'target', target_value,
    'current', current_value, 'unit', target_unit, 'notes', notes
  )) INTO v_kpis FROM public.sustainability_kpi_targets WHERE cycle = p_cycle;

  SELECT jsonb_agg(jsonb_build_object('month', to_char(month, 'YYYY-MM'), 'total', total) ORDER BY month)
  INTO v_monthly_costs
  FROM (SELECT date_trunc('month', date) as month, SUM(amount_brl) as total FROM public.cost_entries WHERE date >= (now() - interval '12 months') GROUP BY date_trunc('month', date)) sub;

  v_result := jsonb_build_object(
    'total_costs', v_total_costs,
    'total_revenue', v_total_revenue,
    'active_members', v_active_count,
    'cost_per_member', CASE WHEN v_active_count > 0 THEN ROUND(v_total_costs / v_active_count, 2) ELSE 0 END,
    'infra_zero_cost_pct', (
      SELECT CASE WHEN COUNT(*) > 0
        THEN ROUND(COUNT(*) FILTER (WHERE paid_by = 'zero_cost')::numeric / COUNT(*) * 100, 1) ELSE 100 END
      FROM public.cost_entries ce JOIN public.cost_categories cc ON cc.id = ce.category_id WHERE cc.name = 'infrastructure'
    ),
    'costs_by_category', COALESCE(v_costs_by_category, '[]'::jsonb),
    'revenue_by_category', COALESCE(v_revenue_by_category, '[]'::jsonb),
    'kpis', COALESCE(v_kpis, '[]'::jsonb),
    'monthly_trend', COALESCE(v_monthly_costs, '[]'::jsonb)
  );
  RETURN v_result;
END;
$function$;

-- ── 2. get_sustainability_projections ────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_sustainability_projections(p_months_ahead integer DEFAULT 6)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_result jsonb;
  v_monthly_avg numeric;
  v_active_count integer;
  v_total_ytd numeric;
  v_months_elapsed integer;
  v_projections jsonb;
BEGIN
  SELECT m.id INTO v_caller_member_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required';
  END IF;
  IF NOT public.can_by_member(v_caller_member_id, 'manage_finance') THEN
    RAISE EXCEPTION 'permission_denied: manage_finance required to view sustainability projections';
  END IF;

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

-- ── 3. get_cost_entries ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_cost_entries(p_category_name text DEFAULT NULL::text, p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_limit integer DEFAULT 100)
RETURNS TABLE(id uuid, category_name text, category_description text, description text, amount_brl numeric, date date, paid_by text, event_title text, submission_title text, notes text, created_by_name text, created_at timestamp with time zone)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_member_id uuid;
BEGIN
  SELECT m.id INTO v_caller_member_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required';
  END IF;
  IF NOT public.can_by_member(v_caller_member_id, 'manage_finance') THEN
    RAISE EXCEPTION 'permission_denied: manage_finance required to list cost entries';
  END IF;

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

-- ── 4. get_revenue_entries ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_revenue_entries(p_category_name text DEFAULT NULL::text, p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_limit integer DEFAULT 100)
RETURNS TABLE(id uuid, category_name text, category_description text, value_type text, description text, amount_brl numeric, date date, notes text, created_by_name text, created_at timestamp with time zone)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_member_id uuid;
BEGIN
  SELECT m.id INTO v_caller_member_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required';
  END IF;
  IF NOT public.can_by_member(v_caller_member_id, 'manage_finance') THEN
    RAISE EXCEPTION 'permission_denied: manage_finance required to list revenue entries';
  END IF;

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

-- Notify PostgREST of body changes (signatures unchanged but defensive)
NOTIFY pgrst, 'reload schema';
