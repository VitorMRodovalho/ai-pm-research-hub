-- ═══════════════════════════════════════════════════════════════════════════
-- Alert lifecycle governance for ingestion alerts
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.ingestion_alert_events (
  id bigserial primary key,
  alert_id bigint not null references public.ingestion_alerts(id) on delete cascade,
  from_status text,
  to_status text not null check (to_status in ('open', 'acknowledged', 'closed')),
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  changed_at timestamptz not null default now(),
  changed_by uuid references public.members(id) on delete set null
);

create index if not exists idx_ingestion_alert_events_alert_changed
  on public.ingestion_alert_events(alert_id, changed_at desc);

alter table public.ingestion_alert_events enable row level security;

drop policy if exists ingestion_alert_events_read_mgmt on public.ingestion_alert_events;
create policy ingestion_alert_events_read_mgmt
on public.ingestion_alert_events
for select to authenticated
using (
  exists (
    select 1
    from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
      or coalesce('chapter_liaison' = any(r.designations), false)
      or coalesce('sponsor' = any(r.designations), false)
  )
);

drop policy if exists ingestion_alert_events_write_mgmt on public.ingestion_alert_events;
create policy ingestion_alert_events_write_mgmt
on public.ingestion_alert_events
for all to authenticated
using (
  exists (
    select 1
    from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
  )
)
with check (
  exists (
    select 1
    from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
  )
);

create or replace function public.admin_update_ingestion_alert_status(
  p_alert_id bigint,
  p_next_status text,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_alert record;
  v_from_status text;
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

  if p_next_status not in ('open', 'acknowledged', 'closed') then
    raise exception 'Invalid next status: %', p_next_status;
  end if;

  select * into v_alert
  from public.ingestion_alerts
  where id = p_alert_id;

  if v_alert is null then
    raise exception 'Alert not found: %', p_alert_id;
  end if;

  v_from_status := v_alert.status;
  if v_from_status = p_next_status then
    return jsonb_build_object(
      'success', true,
      'alert_id', p_alert_id,
      'status', p_next_status,
      'changed', false
    );
  end if;

  if v_from_status = 'closed' and p_next_status = 'acknowledged' then
    raise exception 'Invalid transition closed -> acknowledged';
  end if;

  update public.ingestion_alerts
  set
    status = p_next_status,
    resolved_at = case when p_next_status = 'closed' then now() else null end
  where id = p_alert_id;

  insert into public.ingestion_alert_events (
    alert_id,
    from_status,
    to_status,
    reason,
    metadata,
    changed_by
  ) values (
    p_alert_id,
    v_from_status,
    p_next_status,
    nullif(trim(coalesce(p_reason, '')), ''),
    coalesce(p_metadata, '{}'::jsonb),
    v_caller.id
  );

  return jsonb_build_object(
    'success', true,
    'alert_id', p_alert_id,
    'from_status', v_from_status,
    'status', p_next_status,
    'changed', true
  );
end;
$$;

grant execute on function public.admin_update_ingestion_alert_status(bigint, text, text, jsonb) to authenticated;

commit;
