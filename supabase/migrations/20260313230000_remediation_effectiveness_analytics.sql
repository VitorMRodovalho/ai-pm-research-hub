-- ═══════════════════════════════════════════════════════════════════════════
-- Remediation effectiveness analytics contracts
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.exec_remediation_effectiveness(
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
  v_overall jsonb := '{}'::jsonb;
  v_by_action jsonb := '[]'::jsonb;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      auth.role() = 'service_role'
      or v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
      or coalesce('chapter_liaison' = any(v_caller.designations), false)
    ) then
    raise exception 'Remediation analytics access required';
  end if;

  with base as (
    select *
    from public.ingestion_alert_remediation_runs r
    where r.created_at >= v_window_start
  )
  select jsonb_build_object(
    'total_runs', count(*)::integer,
    'success_runs', count(*) filter (where status = 'success')::integer,
    'failed_runs', count(*) filter (where status = 'failed')::integer,
    'skipped_runs', count(*) filter (where status = 'skipped')::integer,
    'success_rate', case when count(*) = 0 then 0 else round((count(*) filter (where status = 'success'))::numeric / count(*) * 100, 2) end
  )
  into v_overall
  from base;

  with grouped as (
    select
      action_type,
      count(*)::integer as total,
      count(*) filter (where status = 'success')::integer as success,
      count(*) filter (where status = 'failed')::integer as failed
    from public.ingestion_alert_remediation_runs
    where created_at >= v_window_start
    group by action_type
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'action_type', action_type,
        'total', total,
        'success', success,
        'failed', failed,
        'success_rate', case when total = 0 then 0 else round((success::numeric / total) * 100, 2) end
      ) order by action_type
    ),
    '[]'::jsonb
  )
  into v_by_action
  from grouped;

  return jsonb_build_object(
    'window_days', v_days,
    'window_start', v_window_start,
    'overall', v_overall,
    'by_action', v_by_action
  );
end;
$$;

grant execute on function public.exec_remediation_effectiveness(integer) to authenticated;

commit;
