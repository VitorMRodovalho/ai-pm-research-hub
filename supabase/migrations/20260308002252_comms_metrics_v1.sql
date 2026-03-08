-- COMMS_METRICS_V1
-- Date: 2026-03-08
-- Purpose: establish DB-backed communications KPI storage and retrieval.

begin;

create table if not exists public.comms_metrics_daily (
  id bigserial primary key,
  metric_date date not null,
  channel text not null,
  audience bigint,
  reach bigint,
  engagement_rate numeric(8,4),
  leads bigint,
  source text not null default 'manual',
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid
);

create unique index if not exists uq_comms_metrics_daily_key
  on public.comms_metrics_daily (metric_date, channel, source);

create index if not exists idx_comms_metrics_daily_metric_date
  on public.comms_metrics_daily (metric_date desc);

create index if not exists idx_comms_metrics_daily_channel
  on public.comms_metrics_daily (channel);

create or replace function public.set_comms_metrics_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_comms_metrics_updated_at on public.comms_metrics_daily;
create trigger trg_comms_metrics_updated_at
before update on public.comms_metrics_daily
for each row execute function public.set_comms_metrics_updated_at();

alter table public.comms_metrics_daily enable row level security;

-- Admin+ governance for read/write (service_role bypasses RLS naturally)
drop policy if exists comms_metrics_admin_read on public.comms_metrics_daily;
create policy comms_metrics_admin_read
on public.comms_metrics_daily
for select
to authenticated
using (public.has_min_tier(4));

drop policy if exists comms_metrics_admin_insert on public.comms_metrics_daily;
create policy comms_metrics_admin_insert
on public.comms_metrics_daily
for insert
to authenticated
with check (public.has_min_tier(4));

drop policy if exists comms_metrics_admin_update on public.comms_metrics_daily;
create policy comms_metrics_admin_update
on public.comms_metrics_daily
for update
to authenticated
using (public.has_min_tier(4))
with check (public.has_min_tier(4));

drop policy if exists comms_metrics_admin_delete on public.comms_metrics_daily;
create policy comms_metrics_admin_delete
on public.comms_metrics_daily
for delete
to authenticated
using (public.has_min_tier(4));

-- Returns normalized payload used by /admin/comms KPI band
create or replace function public.comms_metrics_latest()
returns table (
  metric_date date,
  audience bigint,
  reach bigint,
  engagement numeric(8,4),
  leads bigint,
  rows_count int,
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
  ), base as (
    select *
    from public.comms_metrics_daily c
    where c.metric_date = (select d from latest)
  )
  select
    (select d from latest) as metric_date,
    coalesce(sum(base.audience), 0)::bigint as audience,
    coalesce(sum(base.reach), 0)::bigint as reach,
    coalesce(avg(base.engagement_rate), 0)::numeric(8,4) as engagement,
    coalesce(sum(base.leads), 0)::bigint as leads,
    count(*)::int as rows_count,
    max(base.updated_at) as updated_at
  from base;
$$;

revoke all on function public.comms_metrics_latest() from public;
grant execute on function public.comms_metrics_latest() to authenticated;

commit;
