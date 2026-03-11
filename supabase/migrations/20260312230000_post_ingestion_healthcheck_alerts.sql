-- ═══════════════════════════════════════════════════════════════════════════
-- Post-ingestion healthcheck and alerts
-- Date: 2026-03-12
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.ingestion_alerts (
  id bigserial primary key,
  alert_key text not null,
  severity text not null check (severity in ('info', 'warning', 'critical')),
  status text not null default 'open' check (status in ('open', 'acknowledged', 'closed')),
  summary text not null,
  details jsonb not null default '{}'::jsonb,
  detected_at timestamptz not null default now(),
  resolved_at timestamptz,
  batch_id uuid references public.ingestion_batches(id) on delete set null,
  created_by uuid references public.members(id) on delete set null
);

create index if not exists idx_ingestion_alerts_status
  on public.ingestion_alerts(status, severity, detected_at desc);

alter table public.ingestion_alerts enable row level security;

drop policy if exists ingestion_alerts_read_mgmt on public.ingestion_alerts;
create policy ingestion_alerts_read_mgmt
on public.ingestion_alerts
for select to authenticated
using (
  exists (
    select 1 from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
      or coalesce('chapter_liaison' = any(r.designations), false)
      or coalesce('sponsor' = any(r.designations), false)
  )
);

drop policy if exists ingestion_alerts_write_mgmt on public.ingestion_alerts;
create policy ingestion_alerts_write_mgmt
on public.ingestion_alerts
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

create or replace function public.admin_run_post_ingestion_healthcheck(
  p_batch_id uuid default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_flags jsonb;
  v_audit jsonb;
  v_open_count integer := 0;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      auth.role() = 'service_role'
      or v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
    ) then
    raise exception 'Internal healthcheck access required';
  end if;

  v_audit := public.admin_data_quality_audit();
  v_flags := coalesce(v_audit -> 'flags', '{}'::jsonb);

  if coalesce((v_flags ->> 'tribe_6_missing')::boolean, false) then
    insert into public.ingestion_alerts (alert_key, severity, summary, details, batch_id, created_by)
    values (
      'tribe_6_missing',
      'critical',
      'Tribe 6 is missing from current catalog.',
      jsonb_build_object('flags', v_flags, 'audit', v_audit),
      p_batch_id,
      v_caller.id
    );
  end if;

  if coalesce((v_flags ->> 'communication_tribe_missing')::boolean, false) then
    insert into public.ingestion_alerts (alert_key, severity, summary, details, batch_id, created_by)
    values (
      'communication_tribe_missing',
      'critical',
      'Communication tribe is not present in current catalog.',
      jsonb_build_object('flags', v_flags, 'audit', v_audit),
      p_batch_id,
      v_caller.id
    );
  end if;

  if coalesce((v_flags ->> 'legacy_cycle_1_2_empty')::boolean, false) then
    insert into public.ingestion_alerts (alert_key, severity, summary, details, batch_id, created_by)
    values (
      'legacy_cycle_1_2_empty',
      'warning',
      'Legacy cycle 1/2 entities are still empty.',
      jsonb_build_object('flags', v_flags, 'audit', v_audit),
      p_batch_id,
      v_caller.id
    );
  end if;

  if coalesce((v_flags ->> 'lineage_empty')::boolean, false) then
    insert into public.ingestion_alerts (alert_key, severity, summary, details, batch_id, created_by)
    values (
      'lineage_empty',
      'warning',
      'No tribe lineage mappings found.',
      jsonb_build_object('flags', v_flags, 'audit', v_audit),
      p_batch_id,
      v_caller.id
    );
  end if;

  select count(*) into v_open_count
  from public.ingestion_alerts
  where status = 'open';

  return jsonb_build_object(
    'success', true,
    'open_alerts', v_open_count,
    'flags', v_flags
  );
end;
$$;

grant execute on function public.admin_run_post_ingestion_healthcheck(uuid) to authenticated;

commit;
