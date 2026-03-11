-- ═══════════════════════════════════════════════════════════════════════════
-- Partner governance trends RPC pack
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.exec_partner_governance_trends(
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
  v_readiness_trend jsonb := '[]'::jsonb;
  v_alert_trend jsonb := '[]'::jsonb;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      auth.role() = 'service_role'
      or v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
      or coalesce('sponsor' = any(v_caller.designations), false)
      or coalesce('chapter_liaison' = any(v_caller.designations), false)
      or coalesce('curator' = any(v_caller.designations), false)
    ) then
    raise exception 'Partner governance access required';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'day', t.day,
        'total', t.total,
        'ready_true', t.ready_true,
        'ready_false', t.ready_false
      ) order by t.day
    ),
    '[]'::jsonb
  )
  into v_readiness_trend
  from (
    select
      date_trunc('day', h.created_at) as day,
      count(*)::integer as total,
      count(*) filter (where h.ready is true)::integer as ready_true,
      count(*) filter (where h.ready is false)::integer as ready_false
    from public.release_readiness_history h
    where h.created_at >= v_window_start
    group by 1
  ) t;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'day', t.day,
        'open_critical', t.open_critical,
        'open_warning', t.open_warning,
        'open_total', t.open_total
      ) order by t.day
    ),
    '[]'::jsonb
  )
  into v_alert_trend
  from (
    select
      date_trunc('day', a.detected_at) as day,
      count(*) filter (where a.status = 'open' and a.severity = 'critical')::integer as open_critical,
      count(*) filter (where a.status = 'open' and a.severity = 'warning')::integer as open_warning,
      count(*) filter (where a.status = 'open')::integer as open_total
    from public.ingestion_alerts a
    where a.detected_at >= v_window_start
    group by 1
  ) t;

  return jsonb_build_object(
    'window_days', v_days,
    'window_start', v_window_start,
    'readiness_trend', v_readiness_trend,
    'alert_trend', v_alert_trend
  );
end;
$$;

grant execute on function public.exec_partner_governance_trends(integer) to authenticated;

commit;
