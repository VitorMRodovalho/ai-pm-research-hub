-- COMMS_METRICS_V3
-- Date: 2026-03-08
-- Purpose: publish workflow and audit trail for manual comms batches.

begin;

alter table public.comms_metrics_daily
  add column if not exists published_at timestamptz,
  add column if not exists published_by uuid,
  add column if not exists publish_batch_id text;

create index if not exists idx_comms_metrics_daily_publish_batch_id
  on public.comms_metrics_daily (publish_batch_id);

create index if not exists idx_comms_metrics_daily_published_at
  on public.comms_metrics_daily (published_at desc nulls last);

create table if not exists public.comms_metrics_publish_log (
  id bigserial primary key,
  batch_id text not null,
  source text not null,
  target_date date not null,
  published_rows integer not null default 0,
  published_by uuid,
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_comms_metrics_publish_log_created_at
  on public.comms_metrics_publish_log (created_at desc);

create unique index if not exists uq_comms_metrics_publish_log_batch_id
  on public.comms_metrics_publish_log (batch_id);

alter table public.comms_metrics_publish_log enable row level security;

drop policy if exists comms_publish_log_admin_read on public.comms_metrics_publish_log;
create policy comms_publish_log_admin_read
on public.comms_metrics_publish_log
for select
to authenticated
using (public.can_manage_comms_metrics());

create or replace function public.publish_comms_metrics_batch(
  p_source text default 'manual_csv',
  p_metric_date date default null
)
returns table (
  batch_id text,
  source text,
  target_date date,
  published_rows integer,
  published_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_source text;
  v_target_date date;
  v_published_rows integer := 0;
  v_batch_id text;
  v_actor_member_id uuid;
  v_now timestamptz;
begin
  if not public.can_manage_comms_metrics() then
    raise exception 'Insufficient privileges to publish comms metrics batch';
  end if;

  v_source := coalesce(nullif(trim(p_source), ''), 'manual_csv');

  select m.id into v_actor_member_id
  from public.members m
  where m.auth_id = auth.uid()
  limit 1;

  if p_metric_date is null then
    select max(c.metric_date) into v_target_date
    from public.comms_metrics_daily c
    where c.source = v_source
      and c.published_at is null;
  else
    v_target_date := p_metric_date;
  end if;

  if v_target_date is null then
    raise exception 'No unpublished rows found for source %', v_source;
  end if;

  v_batch_id := format('comms_pub_%s_%s', v_source, to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'));
  v_now := now();

  update public.comms_metrics_daily
     set published_at = v_now,
         published_by = v_actor_member_id,
         publish_batch_id = v_batch_id,
         payload = coalesce(payload, '{}'::jsonb) || jsonb_build_object(
           'published_via', 'admin_workflow',
           'published_at', v_now,
           'publish_batch_id', v_batch_id,
           'published_by', v_actor_member_id
         )
   where source = v_source
     and metric_date = v_target_date
     and published_at is null;

  get diagnostics v_published_rows = row_count;

  if v_published_rows = 0 then
    raise exception 'No rows were published for source % on %', v_source, v_target_date;
  end if;

  insert into public.comms_metrics_publish_log (
    batch_id, source, target_date, published_rows, published_by, context
  ) values (
    v_batch_id, v_source, v_target_date, v_published_rows, v_actor_member_id,
    jsonb_build_object('published_via', 'rpc_publish_comms_metrics_batch')
  );

  return query
  select v_batch_id, v_source, v_target_date, v_published_rows, v_now;
end;
$$;

revoke all on function public.publish_comms_metrics_batch(text, date) from public;
grant execute on function public.publish_comms_metrics_batch(text, date) to authenticated;

commit;
