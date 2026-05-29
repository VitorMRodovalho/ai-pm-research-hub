-- p277 / #419 (ADR-0100) — metric 2: v_active_members canonical view + converge the REAL drifts.
--
-- WHAT: Canonical "active member" (ADR-0100 §2.2) = is_active AND current_cycle_active (live=52).
--   A discovery sweep found ~10 org-level active-member computations; 4 truly DIVERGE today
--   (is_active-only → 53, a +1 drift). This ships the canonical view and converges the 3 smallest
--   real-drift RPCs onto it (53→52):
--     - get_platform_usage (counts.members)
--     - get_sustainability_projections (active_members projection base)
--     - get_pilot_metrics (active_members_count + adoption_pct denominator)
--
--   NAME-COLLISION GUARD: a legacy view public.active_members (is_active-ONLY, 53 rows) already
--   exists and is consumed by BoardEngine/AttendanceForm + generated FK metadata — this migration
--   uses the v_ prefix (v_active_members) and does NOT touch the legacy view.
--
-- WHY: ADR-0100 §2.3 single canonical "active member" set; first consumers of the view.
--
-- DEFERRED (documented in #419, NOT in this migration): the larger / latent-only sites
--   (get_cycle_report L16/19, get_adoption_dashboard secondary tiles, get_org_chart, exec_cycle_report,
--   get_executive_kpis COALESCE base, 2 frontend inline counts), the legacy active_members view
--   reconciliation, and the chapter-dashboard member_status PM decision. tribe/initiative member_count
--   is a SEPARATE metric (#419 step 4).
--
-- ROLLBACK: DROP VIEW v_active_members; re-CREATE the 3 RPCs with `is_active` (only) member counts.

-- ── canonical view ──────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_active_members AS
  SELECT id, organization_id, chapter, tribe_id, person_id
  FROM public.members
  WHERE is_active = true AND current_cycle_active = true;

COMMENT ON VIEW public.v_active_members IS
  'ADR-0100 #419: the single canonical "active member" set = is_active AND current_cycle_active. Consume this (count(*) FROM v_active_members) instead of re-implementing the predicate inline. NOTE: distinct from the legacy public.active_members view (is_active-only) — do not conflate.';

-- internal/SECDEF consumption only; do not expose the active-member list to anon
REVOKE ALL ON public.v_active_members FROM PUBLIC, anon;
GRANT SELECT ON public.v_active_members TO authenticated, service_role;

-- ── converge: get_platform_usage (was is_active-only → 53) ───────────────────
CREATE OR REPLACE FUNCTION public.get_platform_usage()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_db_size bigint;
  v_storage_size bigint;
  v_member_count int;
  v_event_count int;
  v_notification_count int;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_platform permission');
  END IF;
  SELECT pg_database_size(current_database()) INTO v_db_size;
  SELECT COALESCE(sum((metadata->>'size')::bigint), 0) INTO v_storage_size FROM storage.objects;
  SELECT count(*) INTO v_member_count FROM public.v_active_members;  -- #419: canonical active members
  SELECT count(*) INTO v_event_count FROM events;
  SELECT count(*) INTO v_notification_count FROM notifications;
  RETURN jsonb_build_object(
    'database', jsonb_build_object('used_bytes', v_db_size, 'used_mb', round(v_db_size / 1048576.0, 1), 'limit_mb', 500,
      'pct', round(100.0 * v_db_size / (500 * 1048576.0), 1),
      'status', CASE WHEN v_db_size > 400*1048576 THEN 'critical' WHEN v_db_size > 300*1048576 THEN 'warning' ELSE 'healthy' END),
    'storage', jsonb_build_object('used_bytes', v_storage_size, 'used_mb', round(v_storage_size / 1048576.0, 1), 'limit_mb', 1024,
      'pct', round(100.0 * v_storage_size / (1024 * 1048576.0), 1),
      'status', CASE WHEN v_storage_size > 800*1048576 THEN 'critical' WHEN v_storage_size > 600*1048576 THEN 'warning' ELSE 'healthy' END),
    'counts', jsonb_build_object('members', v_member_count, 'events', v_event_count, 'notifications', v_notification_count),
    'thresholds', jsonb_build_object('tier2_trigger', 'Any service > 80% of free limit', 'db_alert_mb', 400, 'storage_alert_mb', 800),
    'checked_at', now()
  );
END;
$function$;

-- ── converge: get_sustainability_projections (was is_active-only → 53) ───────
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

-- ── converge: get_pilot_metrics (was is_active-only → 53; count + adoption denominator) ──
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
      WHERE bi.baseline_date IS NOT NULL AND bi.status != 'archived'
      AND EXISTS (
        SELECT 1 FROM board_item_tag_assignments bita
        JOIN tags t ON t.id = bita.tag_id
        WHERE bita.board_item_id = bi.id AND t.name = 'entregavel_lider'
      )
    ),
    'release_count', (SELECT count(*) FROM public.releases),
    'active_boards', (SELECT count(*) FROM public.project_boards WHERE is_active = true),
    'total_events', (SELECT count(*) FROM public.events),
    'total_attendance', (SELECT count(*) FROM public.attendance),
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

NOTIFY pgrst, 'reload schema';
