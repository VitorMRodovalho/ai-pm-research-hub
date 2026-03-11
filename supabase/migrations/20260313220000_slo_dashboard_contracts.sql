-- ═══════════════════════════════════════════════════════════════════════════
-- SLO dashboard aggregate contracts
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.exec_readiness_slo_dashboard(
  p_window_days integer default 30
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_days integer := greatest(coalesce(p_window_days, 30), 1);
  v_window_start timestamptz := now() - make_interval(days => v_days);
  v_total_decisions integer := 0;
  v_not_ready integer := 0;
  v_slo_breaches integer := 0;
  v_latest_decision_at timestamptz;
  v_mtbd_hours numeric := 0;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      auth.role() = 'service_role'
      or v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
      or coalesce('chapter_liaison' = any(v_caller.designations), false)
      or coalesce('sponsor' = any(v_caller.designations), false)
    ) then
    raise exception 'SLO dashboard access required';
  end if;

  select count(*)::integer, count(*) filter (where ready is false)::integer, max(created_at)
  into v_total_decisions, v_not_ready, v_latest_decision_at
  from public.release_readiness_history
  where created_at >= v_window_start;

  select count(*)::integer
  into v_slo_breaches
  from public.readiness_slo_alerts
  where created_at >= v_window_start;

  if v_slo_breaches > 0 then
    v_mtbd_hours := round((v_days * 24.0) / v_slo_breaches, 2);
  else
    v_mtbd_hours := round(v_days * 24.0, 2);
  end if;

  return jsonb_build_object(
    'window_days', v_days,
    'window_start', v_window_start,
    'totals', jsonb_build_object(
      'decisions', v_total_decisions,
      'not_ready', v_not_ready,
      'slo_breaches', v_slo_breaches
    ),
    'kpis', jsonb_build_object(
      'ready_rate', case when v_total_decisions = 0 then 0 else round(((v_total_decisions - v_not_ready)::numeric / v_total_decisions) * 100, 2) end,
      'mtbd_hours', v_mtbd_hours
    ),
    'latest_decision_at', v_latest_decision_at
  );
end;
$$;

grant execute on function public.exec_readiness_slo_dashboard(integer) to authenticated;

commit;
