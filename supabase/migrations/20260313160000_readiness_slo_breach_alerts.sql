-- ═══════════════════════════════════════════════════════════════════════════
-- Readiness SLO breach alert contracts
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.readiness_slo_alerts (
  id bigserial primary key,
  breach_key text not null unique,
  status text not null default 'open' check (status in ('open', 'closed')),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index if not exists idx_readiness_slo_alerts_status_created
  on public.readiness_slo_alerts(status, created_at desc);

alter table public.readiness_slo_alerts enable row level security;

drop policy if exists readiness_slo_alerts_read_mgmt on public.readiness_slo_alerts;
create policy readiness_slo_alerts_read_mgmt
on public.readiness_slo_alerts
for select to authenticated
using (
  exists (
    select 1 from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
      or coalesce('chapter_liaison' = any(r.designations), false)
  )
);

drop policy if exists readiness_slo_alerts_write_mgmt on public.readiness_slo_alerts;
create policy readiness_slo_alerts_write_mgmt
on public.readiness_slo_alerts
for all to authenticated
using (
  exists (
    select 1 from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
  )
)
with check (
  exists (
    select 1 from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
  )
);

create or replace function public.admin_check_readiness_slo_breach(
  p_max_hours_since_last_decision integer default 48,
  p_max_consecutive_not_ready integer default 3
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_last_decision_at timestamptz;
  v_not_ready_streak integer := 0;
  v_breach boolean := false;
  v_breach_key text;
  v_details jsonb;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      auth.role() = 'service_role'
      or v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
    ) then
    raise exception 'Project management access required';
  end if;

  select created_at into v_last_decision_at
  from public.release_readiness_history
  order by created_at desc
  limit 1;

  with ordered as (
    select ready
    from public.release_readiness_history
    order by created_at desc
    limit greatest(coalesce(p_max_consecutive_not_ready, 3), 1)
  )
  select count(*) into v_not_ready_streak
  from ordered
  where ready is false;

  if v_last_decision_at is null
    or v_last_decision_at < now() - make_interval(hours => greatest(coalesce(p_max_hours_since_last_decision, 48), 1))
    or v_not_ready_streak >= greatest(coalesce(p_max_consecutive_not_ready, 3), 1) then
    v_breach := true;
  end if;

  v_breach_key := format('readiness_slo_breach:%s:%s', coalesce(v_last_decision_at::date::text, 'none'), v_not_ready_streak::text);
  v_details := jsonb_build_object(
    'last_decision_at', v_last_decision_at,
    'not_ready_streak', v_not_ready_streak,
    'max_hours_since_last_decision', greatest(coalesce(p_max_hours_since_last_decision, 48), 1),
    'max_consecutive_not_ready', greatest(coalesce(p_max_consecutive_not_ready, 3), 1)
  );

  if v_breach then
    insert into public.readiness_slo_alerts (breach_key, status, details)
    values (v_breach_key, 'open', v_details)
    on conflict (breach_key) do update set details = excluded.details;

    if not exists (
      select 1 from public.ingestion_alerts a
      where a.alert_key = 'readiness_slo_breach'
        and a.status = 'open'
    ) then
      insert into public.ingestion_alerts (alert_key, severity, status, summary, details, created_by)
      values (
        'readiness_slo_breach',
        'warning',
        'open',
        'Readiness SLO breach detected in decision timeline.',
        v_details,
        v_caller.id
      );
    end if;
  end if;

  return jsonb_build_object(
    'breach', v_breach,
    'breach_key', v_breach_key,
    'details', v_details
  );
end;
$$;

grant execute on function public.admin_check_readiness_slo_breach(integer, integer) to authenticated;

commit;
