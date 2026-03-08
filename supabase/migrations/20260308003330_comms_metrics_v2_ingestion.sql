-- COMMS_METRICS_V2
-- Date: 2026-03-08
-- Purpose: add ingestion observability and channel-level KPI read model.

begin;

create table if not exists public.comms_metrics_ingestion_log (
  id bigserial primary key,
  run_key text not null,
  source text not null,
  triggered_by text not null default 'manual',
  status text not null check (status in ('running', 'success', 'error')),
  fetched_rows integer not null default 0,
  upserted_rows integer not null default 0,
  invalid_rows integer not null default 0,
  error_message text,
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  finished_at timestamptz
);

create unique index if not exists uq_comms_metrics_ingestion_run_key
  on public.comms_metrics_ingestion_log (run_key);

create index if not exists idx_comms_metrics_ingestion_created_at
  on public.comms_metrics_ingestion_log (created_at desc);

create or replace function public.can_manage_comms_metrics()
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if to_regprocedure('public.has_min_tier(integer)') is not null then
    return public.has_min_tier(4);
  end if;

  return exists (
    select 1
    from public.members m
    where m.auth_id = auth.uid()
      and (
        coalesce(m.is_superadmin, false) = true
        or m.operational_role in ('manager', 'deputy_manager')
      )
  );
end;
$$;

revoke all on function public.can_manage_comms_metrics() from public;
grant execute on function public.can_manage_comms_metrics() to authenticated;

alter table public.comms_metrics_ingestion_log enable row level security;

drop policy if exists comms_ingestion_admin_read on public.comms_metrics_ingestion_log;
create policy comms_ingestion_admin_read
on public.comms_metrics_ingestion_log
for select
to authenticated
using (public.can_manage_comms_metrics());

drop policy if exists comms_ingestion_admin_insert on public.comms_metrics_ingestion_log;
create policy comms_ingestion_admin_insert
on public.comms_metrics_ingestion_log
for insert
to authenticated
with check (public.can_manage_comms_metrics());

drop policy if exists comms_ingestion_admin_update on public.comms_metrics_ingestion_log;
create policy comms_ingestion_admin_update
on public.comms_metrics_ingestion_log
for update
to authenticated
using (public.can_manage_comms_metrics())
with check (public.can_manage_comms_metrics());

create or replace function public.comms_metrics_latest_by_channel(p_days integer default 14)
returns table (
  metric_date date,
  channel text,
  audience bigint,
  reach bigint,
  engagement numeric(8,4),
  leads bigint,
  source text,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with latest as (
    select max(metric_date) as d
    from public.comms_metrics_daily
  )
  select
    c.metric_date,
    c.channel,
    c.audience,
    c.reach,
    c.engagement_rate as engagement,
    c.leads,
    c.source,
    c.updated_at
  from public.comms_metrics_daily c
  where c.metric_date >= coalesce((select d from latest) - greatest(p_days, 1) + 1, current_date)
  order by c.metric_date desc, c.reach desc nulls last, c.channel asc;
$$;

revoke all on function public.comms_metrics_latest_by_channel(integer) from public;
grant execute on function public.comms_metrics_latest_by_channel(integer) to authenticated;

commit;
