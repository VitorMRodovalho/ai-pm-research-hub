-- Migration: 20260805000291_onda2_fu1_sponsor_read_only_split
-- Onda 2 — FU-1 (#952): Sponsor read-only de fato via read/write split.
--
-- WHY: the sponsor x sponsor seed granted WRITE actions manage_finance + manage_partner
-- (org scope). PM decision (Onda 2 plan F1): sponsor is read-only. But those same two
-- actions ALSO gate ~12 READ RPCs, so a naive seed DELETE would also strip sponsors'
-- partner/finance/portfolio/attendance READS — contradicting "keep read, lose write".
--
-- HOW (PM-approved "Split read/write"): introduce dedicated READ actions view_finance +
-- view_partner, seeded to EXACTLY today's manage_* holders (so no current reader loses
-- access); repoint the 12 READ-gate RPCs manage_X -> view_X; then revoke the sponsor
-- WRITE seeds. Net: sponsor keeps every read, loses every write. Write RPCs keep manage_X.
--
-- Supersedes the sponsor-write portion of ADR-0025 (Q1) and the sponsor manage_partner
-- seed from 20260413400000 (reused by ADR-0033). The ADR-0043 notify_sponsor_finance_entry
-- trigger is retained as historical record (it simply no longer fires — sponsors can no
-- longer pass the manage_finance write gate). See docs/adr/ADR-0110-sponsor-read-only-split.md.
--
-- Read audiences are UNCHANGED (view_X granted to the same set that held manage_X).
-- Only net change: sponsor x sponsor loses manage_finance + manage_partner (WRITE).

-- ============================================================================
-- Part 1 — new READ actions, seeded to current manage_* holders (idempotent)
-- ============================================================================
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description)
SELECT v.kind, v.role, v.action, 'organization', v.descr
FROM (VALUES
  ('volunteer','manager',       'view_finance', 'Read finance/sustainability dashboards (read half of manage_finance; FU-1 split)'),
  ('volunteer','deputy_manager','view_finance', 'Read finance/sustainability dashboards (read half of manage_finance; FU-1 split)'),
  ('volunteer','co_gp',         'view_finance', 'Read finance/sustainability dashboards (read half of manage_finance; FU-1 split)'),
  ('sponsor',  'sponsor',       'view_finance', 'Read finance/sustainability dashboards (sponsor read-only; FU-1 split)'),
  ('volunteer','manager',       'view_partner', 'Read partner pipeline / portfolio / attendance grids (read half of manage_partner; FU-1 split)'),
  ('volunteer','deputy_manager','view_partner', 'Read partner pipeline / portfolio / attendance grids (read half of manage_partner; FU-1 split)'),
  ('volunteer','co_gp',         'view_partner', 'Read partner pipeline / portfolio / attendance grids (read half of manage_partner; FU-1 split)'),
  ('sponsor',  'sponsor',       'view_partner', 'Read partner pipeline / portfolio / attendance grids (sponsor read-only; FU-1 split)'),
  ('chapter_board','liaison',   'view_partner', 'Read partner pipeline / portfolio / attendance grids (read half of manage_partner; FU-1 split)')
) AS v(kind, role, action, descr)
WHERE NOT EXISTS (
  SELECT 1 FROM public.engagement_kind_permissions e
  WHERE e.kind = v.kind AND e.role = v.role AND e.action = v.action AND e.scope = 'organization'
);

-- ============================================================================
-- Part 2 — revoke sponsor WRITE seeds (the FU-1 decision)
-- ============================================================================
DELETE FROM public.engagement_kind_permissions
WHERE kind = 'sponsor' AND role = 'sponsor'
  AND action IN ('manage_finance','manage_partner')
  AND scope = 'organization';

-- ============================================================================
-- Part 3 — repoint the 12 READ RPC gates manage_X -> view_X
--   (bodies fetched live via pg_get_functiondef; ONLY the can_by_member gate
--    action token changed, proven len_after = len_before - 2 per function)
-- ============================================================================
-- ────────────────────────────────────────────────────────────
-- repoint read gate -> view_finance: get_cost_entries
-- ────────────────────────────────────────────────────────────
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
  IF NOT public.can_by_member(v_caller_member_id, 'view_finance') THEN
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

-- ────────────────────────────────────────────────────────────
-- repoint read gate -> view_finance: get_revenue_entries
-- ────────────────────────────────────────────────────────────
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
  IF NOT public.can_by_member(v_caller_member_id, 'view_finance') THEN
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

-- ────────────────────────────────────────────────────────────
-- repoint read gate -> view_finance: get_sustainability_dashboard
-- ────────────────────────────────────────────────────────────
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
  IF NOT public.can_by_member(v_caller_member_id, 'view_finance') THEN
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

-- ────────────────────────────────────────────────────────────
-- repoint read gate -> view_finance: get_sustainability_projections
-- ────────────────────────────────────────────────────────────
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
  IF NOT public.can_by_member(v_caller_member_id, 'view_finance') THEN
    RAISE EXCEPTION 'permission_denied: manage_finance required to view sustainability projections';
  END IF;

  SELECT count(*) INTO v_active_count FROM public.v_active_members;  -- #419: canonical active members

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

-- ────────────────────────────────────────────────────────────
-- repoint read gate -> view_partner: get_partner_pipeline
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_partner_pipeline()
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
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'view_partner') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT jsonb_build_object(
    'pipeline', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', pe.id,
        'name', pe.name,
        'entity_type', pe.entity_type,
        'status', pe.status,
        'contact_name', pe.contact_name,
        'contact_email', pe.contact_email,
        'chapter', pe.chapter,
        'partnership_date', pe.partnership_date,
        'notes', pe.notes,
        'next_action', pe.next_action,
        'follow_up_date', pe.follow_up_date,
        'last_interaction_at', pe.last_interaction_at,
        'days_in_stage', EXTRACT(DAY FROM now() - COALESCE(pe.updated_at, pe.created_at))::int,
        'updated_at', COALESCE(pe.updated_at, pe.created_at)
      ) ORDER BY CASE pe.status
        WHEN 'negotiation' THEN 1
        WHEN 'contact' THEN 2
        WHEN 'prospect' THEN 3
        WHEN 'active' THEN 4
        WHEN 'inactive' THEN 5
        WHEN 'churned' THEN 6
      END, pe.updated_at DESC)
      FROM public.partner_entities pe
    ), '[]'::jsonb),
    'by_status', COALESCE((
      SELECT jsonb_object_agg(status, cnt)
      FROM (SELECT status, COUNT(*)::int as cnt FROM public.partner_entities GROUP BY status) sub
    ), '{}'::jsonb),
    'by_type', COALESCE((
      SELECT jsonb_object_agg(entity_type, cnt)
      FROM (SELECT entity_type, COUNT(*)::int as cnt FROM public.partner_entities GROUP BY entity_type) sub
    ), '{}'::jsonb),
    'total', (SELECT COUNT(*)::int FROM public.partner_entities),
    'active', (SELECT COUNT(*)::int FROM public.partner_entities WHERE status = 'active'),
    'stale', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', pe.id,
        'name', pe.name,
        'status', pe.status,
        'days_stale', EXTRACT(DAY FROM now() - COALESCE(pe.updated_at, pe.created_at))::int
      ))
      FROM public.partner_entities pe
      WHERE pe.status IN ('prospect','contact','negotiation')
        AND COALESCE(pe.updated_at, pe.created_at) < now() - interval '30 days'
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- ────────────────────────────────────────────────────────────
-- repoint read gate -> view_partner: get_partner_entity_attachments
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_partner_entity_attachments(p_entity_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  -- V4 gate (Path D — drop V3 chapter_match, drift signals #5 #6 closed)
  IF NOT public.can_by_member(v_caller_id, 'view_partner') THEN
    RETURN '[]'::jsonb;
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', pa.id,
      'file_name', pa.file_name,
      'file_url', pa.file_url,
      'file_size', pa.file_size,
      'file_type', pa.file_type,
      'description', pa.description,
      'uploaded_by_name', m.name,
      'created_at', pa.created_at
    ) ORDER BY pa.created_at DESC)
    FROM public.partner_attachments pa
    JOIN public.members m ON m.id = pa.uploaded_by
    WHERE pa.partner_entity_id = p_entity_id
  ), '[]'::jsonb);
END;
$function$;

-- ────────────────────────────────────────────────────────────
-- repoint read gate -> view_partner: get_partner_interaction_attachments
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_partner_interaction_attachments(p_interaction_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  -- V4 gate (Path D — drop V3 chapter_match, drift signals #5 #6 closed)
  IF NOT public.can_by_member(v_caller_id, 'view_partner') THEN
    RETURN '[]'::jsonb;
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', pa.id,
      'file_name', pa.file_name,
      'file_url', pa.file_url,
      'file_size', pa.file_size,
      'file_type', pa.file_type,
      'description', pa.description,
      'uploaded_by_name', m.name,
      'created_at', pa.created_at
    ) ORDER BY pa.created_at DESC)
    FROM public.partner_attachments pa
    JOIN public.members m ON m.id = pa.uploaded_by
    WHERE pa.partner_interaction_id = p_interaction_id
  ), '[]'::jsonb);
END;
$function$;

-- ────────────────────────────────────────────────────────────
-- repoint read gate -> view_partner: get_portfolio_timeline
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_portfolio_timeline()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_tribe_id integer;
  v_chapter text;
  v_is_admin boolean;
  v_result jsonb;
BEGIN
  SELECT id, tribe_id, chapter INTO v_member_id, v_tribe_id, v_chapter
    FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RETURN '[]'::jsonb; END IF;

  v_is_admin := public.can_by_member(v_member_id, 'manage_member');

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', bi.id, 'title', bi.title, 'status', bi.status,
    'tribe_id', i.legacy_tribe_id, 'tribe_name', i.title,
    'baseline_date', bi.baseline_date, 'forecast_date', bi.forecast_date,
    'actual_completion_date', bi.actual_completion_date,
    'is_portfolio_item', true, 'assignee_name', m.name,
    'deviation_days', CASE
      WHEN bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
      THEN bi.forecast_date - bi.baseline_date ELSE 0 END
  ) ORDER BY i.legacy_tribe_id, COALESCE(bi.baseline_date, bi.forecast_date, '2099-12-31'::date)), '[]'::jsonb)
  INTO v_result
  FROM board_items bi
  JOIN project_boards pb ON pb.id = bi.board_id AND pb.is_active = true
  LEFT JOIN initiatives i ON i.id = pb.initiative_id
  LEFT JOIN members m ON m.id = bi.assignee_id
  WHERE bi.status <> 'archived'
    AND bi.is_portfolio_item = true
    AND (pb.initiative_id IS NULL OR EXISTS (
      SELECT 1 FROM tribes tr WHERE tr.id = i.legacy_tribe_id AND tr.is_active = true
    ));

  IF NOT v_is_admin AND v_tribe_id IS NOT NULL THEN
    SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb) INTO v_result
    FROM jsonb_array_elements(v_result) elem
    WHERE (elem->>'tribe_id')::integer = v_tribe_id;
  END IF;

  IF NOT v_is_admin AND public.can_by_member(v_member_id, 'view_partner') AND v_chapter IS NOT NULL THEN
    SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb) INTO v_result
    FROM jsonb_array_elements(v_result) elem
    WHERE (elem->>'tribe_id')::integer IN (
      SELECT i2.legacy_tribe_id
      FROM project_boards pb2
      JOIN initiatives i2 ON i2.id = pb2.initiative_id
      JOIN tribes t2 ON t2.id = i2.legacy_tribe_id
      WHERE EXISTS (SELECT 1 FROM members m2 WHERE m2.tribe_id = t2.id AND m2.chapter = v_chapter)
    );
  END IF;

  RETURN v_result;
END;
$function$;

-- ────────────────────────────────────────────────────────────
-- repoint read gate -> view_partner: get_attendance_grid
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_attendance_grid(p_tribe_id integer DEFAULT NULL::integer, p_event_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_caller_tribe_id integer;
  v_is_admin boolean;
  v_is_stakeholder boolean;
  v_cycle_start date;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  v_caller_tribe_id := public.get_member_tribe(v_member_id);

  v_is_admin := public.can_by_member(v_member_id, 'manage_member');
  v_is_stakeholder := public.can_by_member(v_member_id, 'view_partner');

  IF NOT v_is_admin AND NOT v_is_stakeholder THEN
    IF v_caller_tribe_id IS NOT NULL THEN
      p_tribe_id := v_caller_tribe_id;
    ELSE
      RETURN jsonb_build_object('error', 'No tribe assigned');
    END IF;
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM public.cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  WITH
  grid_events AS (
    SELECT e.id, e.date, e.title, e.type, e.nature, e.status,
           i.legacy_tribe_id AS tribe_id,
           i.title AS tribe_name,
           COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes,
           EXTRACT(WEEK FROM e.date) AS week_number
    FROM public.events e
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_cycle_start
      AND e.type IN ('geral', 'tribo', 'lideranca', 'kickoff', 'comms', 'evento_externo')
      AND (p_event_type IS NULL OR e.type = p_event_type)
      AND (e.initiative_id IS NULL OR e.type = 'tribo')
    ORDER BY e.date
  ),
  active_members AS MATERIALIZED (
    SELECT m.id, m.name,
           public.get_member_tribe(m.id) AS tribe_id,
           m.chapter, m.operational_role, m.designations,
           m.member_status, m.offboarded_at
    FROM public.members m
    WHERE m.is_active = true
      AND m.operational_role NOT IN ('guest', 'none')
  ),
  active_members_scoped AS (
    SELECT * FROM active_members
    WHERE p_tribe_id IS NULL OR tribe_id = p_tribe_id
  ),
  historical_members AS (
    SELECT DISTINCT m.id, m.name,
           p_tribe_id AS tribe_id,
           m.chapter, m.operational_role, m.designations,
           m.member_status, m.offboarded_at
    FROM public.members m
    JOIN public.attendance a ON a.member_id = m.id
    JOIN grid_events ge ON ge.id = a.event_id
    WHERE p_tribe_id IS NOT NULL
      AND m.member_status IN ('observer', 'alumni', 'inactive')
      AND ge.tribe_id = p_tribe_id
  ),
  cohort_members AS (
    SELECT * FROM active_members_scoped
    UNION
    SELECT * FROM historical_members
  ),
  eligibility AS (
    SELECT m.id AS member_id, ge.id AS event_id,
      CASE
        WHEN ge.type IN ('geral', 'kickoff') THEN true
        WHEN ge.type = 'tribo' AND (m.tribe_id = ge.tribe_id OR m.operational_role IN ('manager', 'deputy_manager') OR (p_tribe_id IS NOT NULL AND ge.tribe_id = p_tribe_id)) THEN true
        WHEN ge.type = 'lideranca' AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader') THEN true
        WHEN ge.type = 'comms' AND m.designations && ARRAY['comms_team', 'comms_leader', 'comms_member'] THEN true
        ELSE false
      END AS is_eligible
    FROM cohort_members m CROSS JOIN grid_events ge
  ),
  cell_status AS (
    SELECT el.member_id, el.event_id, el.is_eligible,
      CASE
        WHEN ge.status = 'cancelled' THEN 'na'
        WHEN NOT el.is_eligible THEN 'na'
        WHEN ge.date > CURRENT_DATE THEN CASE WHEN cm.member_status != 'active' THEN 'na' ELSE 'scheduled' END
        WHEN a.id IS NOT NULL AND a.excused = true THEN 'excused'
        WHEN a.id IS NOT NULL AND a.present = true THEN 'present'
        WHEN a.id IS NOT NULL THEN 'absent'
        ELSE CASE
          WHEN cm.member_status != 'active' AND (cm.offboarded_at IS NULL OR cm.offboarded_at::date > ge.date) THEN 'absent'
          WHEN cm.member_status != 'active' AND cm.offboarded_at IS NOT NULL AND cm.offboarded_at::date <= ge.date THEN 'na'
          ELSE 'absent' END
      END AS status
    FROM eligibility el JOIN grid_events ge ON ge.id = el.event_id
    JOIN cohort_members cm ON cm.id = el.member_id
    LEFT JOIN public.attendance a ON a.member_id = el.member_id AND a.event_id = el.event_id
  ),
  member_stats AS (
    SELECT cs.member_id,
      COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'excused')) AS eligible_count,
      COUNT(*) FILTER (WHERE cs.status = 'present') AS present_count,
      ROUND(COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent')), 0), 2) AS rate,
      ROUND(SUM(CASE WHEN cs.status = 'present' THEN ge.duration_minutes ELSE 0 END)::numeric / 60, 1) AS hours
    FROM cell_status cs JOIN grid_events ge ON ge.id = cs.event_id
    GROUP BY cs.member_id
  ),
  detractor_calc AS (
    SELECT cs.member_id,
      (SELECT COUNT(*) FROM (
        SELECT cs2.status, ROW_NUMBER() OVER (ORDER BY ge2.date DESC) AS rn
        FROM cell_status cs2 JOIN grid_events ge2 ON ge2.id = cs2.event_id
        WHERE cs2.member_id = cs.member_id AND cs2.status IN ('present', 'absent')
        ORDER BY ge2.date DESC
      ) sub WHERE sub.status = 'absent' AND sub.rn <= (
        SELECT MIN(rn2) FROM (
          SELECT cs3.status, ROW_NUMBER() OVER (ORDER BY ge3.date DESC) AS rn2
          FROM cell_status cs3 JOIN grid_events ge3 ON ge3.id = cs3.event_id
          WHERE cs3.member_id = cs.member_id AND cs3.status IN ('present', 'absent')
          ORDER BY ge3.date DESC
        ) sub2 WHERE sub2.status = 'present'
      )) AS consecutive_absences
    FROM cell_status cs GROUP BY cs.member_id
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT COUNT(DISTINCT id) FROM active_members_scoped),
      'overall_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms JOIN active_members_scoped am ON am.id = ms.member_id), 0),
      'total_hours', COALESCE((SELECT ROUND(SUM(ms.hours), 1) FROM member_stats ms JOIN active_members_scoped am ON am.id = ms.member_id), 0),
      'detractors_count', (SELECT COUNT(*) FROM detractor_calc dc JOIN active_members_scoped am ON am.id = dc.member_id WHERE dc.consecutive_absences >= 3),
      'at_risk_count', (SELECT COUNT(*) FROM detractor_calc dc JOIN active_members_scoped am ON am.id = dc.member_id WHERE dc.consecutive_absences = 2)
    ),
    'events', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ge.id, 'date', ge.date, 'title', ge.title, 'type', ge.type, 'nature', ge.nature,
      'status', ge.status,
      'tribe_id', ge.tribe_id, 'tribe_name', ge.tribe_name,
      'duration_minutes', ge.duration_minutes, 'week_number', ge.week_number,
      'is_future', (ge.date > CURRENT_DATE),
      'is_cancelled', (ge.status = 'cancelled')
    ) ORDER BY ge.date), '[]'::jsonb) FROM grid_events ge),
    'tribes', (SELECT COALESCE(jsonb_agg(tribe_row ORDER BY tribe_row->>'tribe_name'), '[]'::jsonb) FROM (
      SELECT jsonb_build_object(
        'tribe_id', t.id, 'tribe_name', t.name,
        'leader_name', COALESCE((
          SELECT m2.name FROM public.members m2
          WHERE m2.operational_role = 'tribe_leader'
            AND public.get_member_tribe(m2.id) = t.id
          LIMIT 1
        ), '—'),
        'avg_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms JOIN active_members_scoped am ON am.id = ms.member_id WHERE am.tribe_id = t.id), 0),
        'member_count', (SELECT COUNT(*) FROM active_members_scoped am WHERE am.tribe_id = t.id),
        'members', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id', am.id, 'name', am.name, 'chapter', am.chapter,
          'member_status', am.member_status,
          'rate', COALESCE(ms.rate, 0), 'hours', COALESCE(ms.hours, 0),
          'eligible_count', COALESCE(ms.eligible_count, 0), 'present_count', COALESCE(ms.present_count, 0),
          'detractor_status', CASE
            WHEN am.member_status != 'active' THEN 'inactive'
            WHEN COALESCE(dc.consecutive_absences, 0) >= 3 THEN 'detractor'
            WHEN COALESCE(dc.consecutive_absences, 0) = 2 THEN 'at_risk'
            ELSE 'regular' END,
          'consecutive_absences', COALESCE(dc.consecutive_absences, 0),
          'attendance', (SELECT COALESCE(jsonb_object_agg(cs.event_id::text, cs.status), '{}'::jsonb)
            FROM cell_status cs WHERE cs.member_id = am.id)
        ) ORDER BY CASE WHEN am.member_status = 'active' THEN 0 ELSE 1 END, COALESCE(ms.rate, 0) ASC), '[]'::jsonb)
          FROM cohort_members am
          LEFT JOIN member_stats ms ON ms.member_id = am.id
          LEFT JOIN detractor_calc dc ON dc.member_id = am.id
          WHERE am.tribe_id = t.id)
      ) AS tribe_row
      FROM public.tribes t WHERE t.is_active = true AND (p_tribe_id IS NULL OR t.id = p_tribe_id)
    ) sub)
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- ────────────────────────────────────────────────────────────
-- repoint read gate -> view_partner: get_initiative_attendance_grid
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_initiative_attendance_grid(p_initiative_id uuid, p_event_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_tribe_id int;
  v_cycle_start date;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  v_tribe_id := public.resolve_tribe_id(p_initiative_id);

  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_attendance_grid(v_tribe_id, p_event_type);
  END IF;

  -- D3: native (non-tribe) path had no scope check — any authenticated member could read any
  -- initiative's grid. Mirror get_tribe_attendance_grid: admin (manage_member) OR stakeholder
  -- (manage_partner) OR active engagement on the initiative.
  IF NOT public.can_by_member(v_caller.id, 'manage_member')
     AND NOT public.can_by_member(v_caller.id, 'view_partner')
     AND NOT EXISTS (
       SELECT 1 FROM engagements e
       WHERE e.person_id = v_caller.person_id
         AND e.initiative_id = p_initiative_id
         AND e.status = 'active'
     ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  WITH
  grid_events AS (
    SELECT e.id, e.date, e.title, e.type, e.status,
           COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes,
           EXTRACT(WEEK FROM e.date)::int AS week_number
    FROM events e
    WHERE e.initiative_id = p_initiative_id
      AND e.date >= v_cycle_start
      AND (p_event_type IS NULL OR e.type = p_event_type)
    ORDER BY e.date
  ),
  grid_members AS (
    SELECT DISTINCT m.id, m.name, m.chapter, m.operational_role, m.designations, m.member_status
    FROM engagements eng
    JOIN members m ON m.person_id = eng.person_id
    WHERE eng.initiative_id = p_initiative_id AND eng.status = 'active'
    UNION
    SELECT DISTINCT m.id, m.name, m.chapter, m.operational_role, m.designations, m.member_status
    FROM members m
    JOIN attendance a ON a.member_id = m.id
    JOIN grid_events ge ON ge.id = a.event_id
  ),
  cell_status AS (
    SELECT
      gm.id AS member_id, ge.id AS event_id,
      CASE
        WHEN ge.status = 'cancelled' THEN 'na'
        WHEN ge.date > CURRENT_DATE THEN
          CASE WHEN gm.member_status != 'active' THEN 'na' ELSE 'scheduled' END
        WHEN a.id IS NOT NULL AND a.excused = true THEN 'excused'
        WHEN a.id IS NOT NULL AND a.present = true THEN 'present'
        WHEN a.id IS NOT NULL THEN 'absent'
        ELSE 'absent'
      END AS status
    FROM grid_members gm
    CROSS JOIN grid_events ge
    LEFT JOIN attendance a ON a.member_id = gm.id AND a.event_id = ge.id
  ),
  member_stats AS (
    SELECT
      cs.member_id,
      COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'excused')) AS eligible_count,
      COUNT(*) FILTER (WHERE cs.status = 'present') AS present_count,
      ROUND(
        COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent')), 0), 2
      ) AS rate,
      ROUND(
        SUM(CASE WHEN cs.status = 'present' THEN ge.duration_minutes ELSE 0 END)::numeric / 60, 1
      ) AS hours
    FROM cell_status cs
    JOIN grid_events ge ON ge.id = cs.event_id
    GROUP BY cs.member_id
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT COUNT(DISTINCT id) FROM grid_members WHERE member_status = 'active'),
      'overall_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active'), 0),
      'total_events', (SELECT COUNT(*) FROM grid_events),
      'past_events', (SELECT COUNT(*) FROM grid_events WHERE date <= CURRENT_DATE),
      'cancelled_events', (SELECT COUNT(*) FROM grid_events WHERE status = 'cancelled'),
      'total_hours', COALESCE((SELECT ROUND(SUM(ms.hours), 1) FROM member_stats ms), 0)
    ),
    'events', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ge.id, 'date', ge.date, 'title', ge.title, 'type', ge.type,
      'status', ge.status,
      'duration_minutes', ge.duration_minutes, 'week_number', ge.week_number,
      'is_tribe_event', false,
      'is_future', (ge.date > CURRENT_DATE),
      'is_cancelled', (ge.status = 'cancelled')
    ) ORDER BY ge.date), '[]'::jsonb) FROM grid_events ge),
    'members', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', gm.id, 'name', gm.name, 'chapter', gm.chapter,
        'member_status', gm.member_status,
        'rate', COALESCE(ms.rate, 0),
        'hours', COALESCE(ms.hours, 0),
        'eligible_count', COALESCE(ms.eligible_count, 0),
        'present_count', COALESCE(ms.present_count, 0),
        'detractor_status', 'regular',
        'consecutive_absences', 0,
        'attendance', (
          SELECT COALESCE(jsonb_object_agg(cs.event_id::text, cs.status), '{}'::jsonb)
          FROM cell_status cs WHERE cs.member_id = gm.id
        )
      ) ORDER BY COALESCE(ms.rate, 0) ASC), '[]'::jsonb)
      FROM grid_members gm
      LEFT JOIN member_stats ms ON ms.member_id = gm.id
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- ────────────────────────────────────────────────────────────
-- repoint read gate -> view_partner: get_tribe_attendance_grid
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_tribe_attendance_grid(p_tribe_id integer, p_event_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member_id uuid;
  v_caller_tribe_id integer;
  v_is_admin boolean;
  v_is_stakeholder boolean;
  v_cycle_start date;
  v_tribe_initiative_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  v_caller_tribe_id := public.get_member_tribe(v_member_id);

  v_is_admin := public.can_by_member(v_member_id, 'manage_member');
  v_is_stakeholder := public.can_by_member(v_member_id, 'view_partner');

  IF NOT v_is_admin AND NOT v_is_stakeholder
     AND COALESCE(v_caller_tribe_id, -1) <> p_tribe_id THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM public.cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  SELECT id INTO v_tribe_initiative_id
  FROM public.initiatives
  WHERE legacy_tribe_id = p_tribe_id AND kind = 'research_tribe'
  LIMIT 1;

  WITH
  raw_events AS (
    SELECT e.id, e.date, e.title, e.title_i18n, e.type, e.status, i.legacy_tribe_id AS tribe_id,
           i.title AS tribe_name,
           COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes,
           EXTRACT(WEEK FROM e.date)::int AS week_number,
           EXTRACT(ISOYEAR FROM e.date)::int AS iso_year,
           EXTRACT(WEEK FROM e.date)::int AS iso_week
    FROM public.events e LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_cycle_start
      AND (i.legacy_tribe_id = p_tribe_id OR e.type IN ('geral', 'kickoff') OR e.type = 'lideranca')
      AND (p_event_type IS NULL OR e.type = p_event_type)
      AND (e.initiative_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
  ),
  cancelled_with_replan AS (
    SELECT re_cancelled.id AS cancelled_event_id
    FROM raw_events re_cancelled
    WHERE re_cancelled.status = 'cancelled'
      AND re_cancelled.tribe_id = p_tribe_id
      AND EXISTS (
        SELECT 1 FROM raw_events re_sibling
        WHERE re_sibling.id <> re_cancelled.id
          AND re_sibling.tribe_id = p_tribe_id
          AND re_sibling.status = 'scheduled'
          AND re_sibling.iso_year = re_cancelled.iso_year
          AND re_sibling.iso_week = re_cancelled.iso_week
      )
  ),
  grid_events AS (
    SELECT re.id, re.date, re.title, re.title_i18n, re.type, re.status, re.tribe_id,
           re.tribe_name, re.duration_minutes, re.week_number
    FROM raw_events re
    LEFT JOIN cancelled_with_replan cr ON cr.cancelled_event_id = re.id
    WHERE cr.cancelled_event_id IS NULL
    ORDER BY re.date
  ),
  event_row_counts AS (
    SELECT a.event_id, COUNT(*) AS row_count
    FROM public.attendance a
    WHERE a.event_id IN (SELECT id FROM grid_events)
    GROUP BY a.event_id
  ),
  grid_members AS (
    SELECT m.id, m.name,
           public.get_member_tribe(m.id) AS tribe_id,
           m.chapter, m.operational_role, m.designations, m.member_status
    FROM public.members m
    WHERE m.member_status = 'active'
      AND (
        EXISTS (
          SELECT 1 FROM public.engagements e
          WHERE e.person_id = m.person_id
            AND e.kind = 'volunteer' AND e.status = 'active'
            AND e.initiative_id = v_tribe_initiative_id
        )
        OR m.initiative_id = v_tribe_initiative_id
      )
      AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'guest', 'none')
    UNION
    SELECT DISTINCT m.id, m.name,
           public.get_member_tribe(m.id) AS tribe_id,
           m.chapter, m.operational_role, m.designations, m.member_status
    FROM public.members m
    JOIN public.attendance a ON a.member_id = m.id
    JOIN grid_events ge ON ge.id = a.event_id
    WHERE m.member_status IN ('observer', 'alumni', 'inactive')
      AND ge.tribe_id = p_tribe_id
  ),
  eligibility AS (
    SELECT m.id AS member_id, ge.id AS event_id,
      CASE
        WHEN ge.type IN ('geral', 'kickoff') THEN true
        WHEN ge.type = 'tribo' AND ge.tribe_id = p_tribe_id THEN true
        WHEN ge.type = 'lideranca' AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader') THEN true
        ELSE false
      END AS is_eligible
    FROM grid_members m CROSS JOIN grid_events ge
  ),
  cell_status AS (
    SELECT el.member_id, el.event_id, el.is_eligible,
      CASE
        WHEN ge.status = 'cancelled' THEN 'na'
        WHEN NOT el.is_eligible THEN 'na'
        WHEN ge.date > CURRENT_DATE THEN CASE WHEN gm.member_status != 'active' THEN 'na' ELSE 'scheduled' END
        WHEN a.id IS NOT NULL AND a.excused = true THEN 'excused'
        WHEN a.id IS NOT NULL AND a.present = true THEN 'present'
        WHEN a.id IS NOT NULL AND a.present = false THEN 'absent'
        ELSE CASE
          WHEN gm.member_status != 'active' AND (gm.offboarded_at IS NULL OR gm.offboarded_at::date > ge.date) THEN 'absent'
          WHEN gm.member_status != 'active' AND gm.offboarded_at IS NOT NULL AND gm.offboarded_at::date <= ge.date THEN 'na'
          ELSE 'absent' END
      END AS status
    FROM eligibility el JOIN grid_events ge ON ge.id = el.event_id
    JOIN (SELECT id, member_status, offboarded_at FROM public.members) gm ON gm.id = el.member_id
    LEFT JOIN public.attendance a ON a.member_id = el.member_id AND a.event_id = el.event_id
    LEFT JOIN event_row_counts erc ON erc.event_id = ge.id
  ),
  member_stats AS (
    SELECT cs.member_id,
      COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'excused')) AS eligible_count,
      COUNT(*) FILTER (WHERE cs.status = 'present') AS present_count,
      ROUND(COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent')), 0), 2) AS rate,
      ROUND(SUM(CASE WHEN cs.status = 'present' THEN ge.duration_minutes ELSE 0 END)::numeric / 60, 1) AS hours
    FROM cell_status cs JOIN grid_events ge ON ge.id = cs.event_id GROUP BY cs.member_id
  ),
  detractor_calc AS (
    SELECT cs.member_id,
      (SELECT COUNT(*) FROM (
        SELECT cs2.status AS cell_status, ROW_NUMBER() OVER (ORDER BY ge2.date DESC) AS rn
        FROM cell_status cs2 JOIN grid_events ge2 ON ge2.id = cs2.event_id
        WHERE cs2.member_id = cs.member_id AND cs2.status IN ('present', 'absent')
        ORDER BY ge2.date DESC
      ) sub WHERE sub.cell_status = 'absent' AND sub.rn <= COALESCE((
        SELECT MIN(rn2) FROM (
          SELECT cs3.status AS cell_status, ROW_NUMBER() OVER (ORDER BY ge3.date DESC) AS rn2
          FROM cell_status cs3 JOIN grid_events ge3 ON ge3.id = cs3.event_id
          WHERE cs3.member_id = cs.member_id AND cs3.status IN ('present', 'absent')
          ORDER BY ge3.date DESC
        ) sub2 WHERE sub2.cell_status = 'present'), 999)) AS consecutive_absences
    FROM cell_status cs GROUP BY cs.member_id
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT COUNT(DISTINCT id) FROM grid_members WHERE member_status = 'active'),
      'overall_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active'), 0),
      'perfect_attendance', (SELECT COUNT(*) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active' AND ms.rate >= 1.0),
      'below_50', (SELECT COUNT(*) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active' AND ms.rate < 0.5 AND ms.rate > 0),
      'total_events', (SELECT COUNT(*) FROM grid_events),
      'past_events', (SELECT COUNT(*) FROM grid_events WHERE date <= CURRENT_DATE),
      'cancelled_events', (SELECT COUNT(*) FROM grid_events ge_c WHERE ge_c.status = 'cancelled'),
      'total_hours', COALESCE((SELECT ROUND(SUM(ms.hours), 1) FROM member_stats ms), 0),
      'detractors_count', (SELECT COUNT(*) FROM detractor_calc dc JOIN grid_members gm ON gm.id = dc.member_id WHERE gm.member_status = 'active' AND dc.consecutive_absences >= 3),
      'at_risk_count', (SELECT COUNT(*) FROM detractor_calc dc JOIN grid_members gm ON gm.id = dc.member_id WHERE gm.member_status = 'active' AND dc.consecutive_absences = 2)
    ),
    'events', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ge.id, 'date', ge.date, 'title', ge.title, 'title_i18n', ge.title_i18n, 'type', ge.type,
      'status', ge.status,
      'tribe_id', ge.tribe_id, 'tribe_name', ge.tribe_name,
      'duration_minutes', ge.duration_minutes, 'week_number', ge.week_number,
      'is_tribe_event', (ge.tribe_id = p_tribe_id), 'is_future', (ge.date > CURRENT_DATE),
      'is_cancelled', (ge.status = 'cancelled')
    ) ORDER BY ge.date), '[]'::jsonb) FROM grid_events ge),
    'members', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', am.id, 'name', am.name, 'chapter', am.chapter, 'member_status', am.member_status,
      'rate', COALESCE(ms.rate, 0), 'hours', COALESCE(ms.hours, 0),
      'eligible_count', COALESCE(ms.eligible_count, 0), 'present_count', COALESCE(ms.present_count, 0),
      'detractor_status', CASE
        WHEN am.member_status != 'active' THEN 'inactive'
        WHEN COALESCE(dc.consecutive_absences, 0) >= 3 THEN 'detractor'
        WHEN COALESCE(dc.consecutive_absences, 0) = 2 THEN 'at_risk'
        ELSE 'regular' END,
      'consecutive_absences', COALESCE(dc.consecutive_absences, 0),
      'attendance', (SELECT COALESCE(jsonb_object_agg(cs.event_id::text, cs.status), '{}'::jsonb)
        FROM cell_status cs WHERE cs.member_id = am.id)
    ) ORDER BY CASE WHEN am.member_status = 'active' THEN 0 ELSE 1 END, COALESCE(ms.rate, 0) ASC), '[]'::jsonb)
      FROM grid_members am
      LEFT JOIN member_stats ms ON ms.member_id = am.id
      LEFT JOIN detractor_calc dc ON dc.member_id = am.id)
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- ────────────────────────────────────────────────────────────
-- repoint read gate -> view_partner: list_initiative_events
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.list_initiative_events(p_tribe_id integer DEFAULT NULL::integer, p_initiative_id uuid DEFAULT NULL::uuid, p_types text[] DEFAULT NULL::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_has_minutes boolean DEFAULT NULL::boolean, p_has_recording boolean DEFAULT NULL::boolean, p_has_attendance boolean DEFAULT NULL::boolean, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_is_admin boolean;
  v_is_stakeholder boolean;
  v_clamped_limit int;
  v_resolved_from date;
  v_resolved_to date;
  v_total int;
  v_result jsonb;
  v_target_tribe int;
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  v_is_admin := public.can_by_member(v_caller_id, 'manage_member');
  v_is_stakeholder := public.can_by_member(v_caller_id, 'view_partner');

  -- Resolve target tribe (may be NULL = no filter)
  IF p_initiative_id IS NOT NULL THEN
    SELECT legacy_tribe_id INTO v_target_tribe
    FROM public.initiatives WHERE id = p_initiative_id;
  ELSE
    v_target_tribe := p_tribe_id;
  END IF;

  -- Authorization tiering (spec)
  IF v_is_admin THEN
    NULL;  -- admin sees all
  ELSIF v_is_stakeholder AND v_target_tribe IS NULL THEN
    NULL;  -- sponsor/liaison sees general events only (filter applied below)
  ELSIF v_caller_role = 'tribe_leader' AND (v_target_tribe IS NULL OR v_target_tribe = v_caller_tribe) THEN
    NULL;  -- TL of target tribe
  ELSIF v_caller_role IN ('researcher', 'chapter_board') AND v_target_tribe = v_caller_tribe THEN
    NULL;  -- researcher in target tribe
  ELSE
    RETURN jsonb_build_object('error', 'Unauthorized: insufficient access to requested events');
  END IF;

  -- Clamp + defaults
  v_clamped_limit := greatest(1, least(200, coalesce(p_limit, 50)));
  v_resolved_from := coalesce(p_date_from, current_date - interval '90 days');
  v_resolved_to := coalesce(p_date_to, current_date);

  WITH base AS (
    SELECT
      e.id, e.date, e.time_start, e.type, e.title,
      e.duration_minutes, e.duration_actual, e.meeting_link,
      e.minutes_text IS NOT NULL AND length(trim(e.minutes_text)) > 0 AS has_minutes,
      e.minutes_posted_at,
      e.youtube_url, e.recording_url, e.is_recorded, e.recording_type,
      e.nature, e.created_at,
      i.legacy_tribe_id AS tribe_id,
      i.id AS initiative_id,
      i.title AS initiative_title,
      (SELECT count(*) FROM public.attendance a WHERE a.event_id = e.id) AS attendance_count,
      (SELECT count(*) FROM public.attendance a WHERE a.event_id = e.id AND a.present = true) AS attendance_present_count,
      (SELECT count(*) FROM public.event_showcases s WHERE s.event_id = e.id) AS showcase_count,
      (SELECT count(*) FROM public.meeting_action_items m WHERE m.event_id = e.id AND m.status NOT IN ('done', 'cancelled')) AS action_items_open
    FROM public.events e
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_resolved_from
      AND e.date <= v_resolved_to
      AND public.rls_can_see_initiative(i.id)  -- #785 PR-3: confidential gate
      AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
      AND (p_initiative_id IS NULL OR i.id = p_initiative_id)
      AND (p_types IS NULL OR e.type = ANY(p_types))
      -- Stakeholder restriction: sees only general events when no target tribe
      AND (NOT (v_is_stakeholder AND NOT v_is_admin) OR e.type IN ('geral', 'kickoff', 'lideranca'))
  ),
  filtered AS (
    SELECT * FROM base
    WHERE
      (p_has_minutes IS NULL OR base.has_minutes = p_has_minutes)
      AND (p_has_recording IS NULL OR (base.youtube_url IS NOT NULL OR base.recording_url IS NOT NULL) = p_has_recording)
      AND (p_has_attendance IS NULL OR (base.attendance_count > 0) = p_has_attendance)
  )
  SELECT
    count(*)::int,
    coalesce(jsonb_agg(jsonb_build_object(
      'id', f.id,
      'date', f.date,
      'time_start', f.time_start,
      'type', f.type,
      'title', f.title,
      'duration_minutes', f.duration_minutes,
      'duration_actual', f.duration_actual,
      'meeting_link', f.meeting_link,
      'minutes_text_present', f.has_minutes,
      'minutes_posted_at', f.minutes_posted_at,
      'youtube_url', f.youtube_url,
      'recording_url', f.recording_url,
      'is_recorded', f.is_recorded,
      'recording_type', f.recording_type,
      'tribe_id', f.tribe_id,
      'initiative_id', f.initiative_id,
      'initiative_title', f.initiative_title,
      'attendance_count', f.attendance_count,
      'attendance_present_count', f.attendance_present_count,
      'showcase_count', f.showcase_count,
      'action_items_open', f.action_items_open,
      'nature', f.nature
    ) ORDER BY f.date DESC, f.time_start DESC NULLS LAST), '[]'::jsonb)
  INTO v_total, v_result
  FROM (
    SELECT * FROM filtered
    ORDER BY date DESC, time_start DESC NULLS LAST
    OFFSET p_offset
    LIMIT v_clamped_limit
  ) f;

  RETURN jsonb_build_object(
    'total_count', v_total,
    'limit', v_clamped_limit,
    'offset', p_offset,
    'date_from', v_resolved_from,
    'date_to', v_resolved_to,
    'events', v_result
  );
END;
$function$;

-- ============================================================================
-- Part 4 — in-tx post-conditions (fail-closed)
-- ============================================================================
DO $verify$
DECLARE v_manage int; v_view int; v_drift int;
BEGIN
  SELECT count(*) INTO v_manage FROM public.engagement_kind_permissions
   WHERE kind='sponsor' AND role='sponsor' AND action IN ('manage_finance','manage_partner');
  IF v_manage <> 0 THEN RAISE EXCEPTION 'FU-1: sponsor still holds % write seed(s)', v_manage; END IF;

  SELECT count(*) INTO v_view FROM public.engagement_kind_permissions
   WHERE kind='sponsor' AND role='sponsor' AND action IN ('view_finance','view_partner') AND scope='organization';
  IF v_view <> 2 THEN RAISE EXCEPTION 'FU-1: sponsor view seeds = % (expected 2)', v_view; END IF;

  SELECT count(*) INTO v_drift FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname='public'
   WHERE p.proname = ANY(ARRAY[
     'get_cost_entries','get_revenue_entries','get_sustainability_dashboard','get_sustainability_projections',
     'get_partner_pipeline','get_partner_entity_attachments','get_partner_interaction_attachments',
     'get_portfolio_timeline','get_attendance_grid','get_initiative_attendance_grid',
     'get_tribe_attendance_grid','list_initiative_events'])
     AND p.prosrc ~ 'can_by_member\([^,]+,\s*''manage_(finance|partner)''\)';
  IF v_drift <> 0 THEN RAISE EXCEPTION 'FU-1: % read fn(s) still gate on manage_X', v_drift; END IF;
END $verify$;

NOTIFY pgrst, 'reload schema';
