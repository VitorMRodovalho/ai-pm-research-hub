-- ═══════════════════════════════════════════════════════════════════════════
-- Remediation escalation matrix contracts
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.ingestion_remediation_escalation_matrix (
  severity text not null check (severity in ('info', 'warning', 'critical')),
  recurrence_threshold integer not null,
  action_type text not null check (action_type in ('mark_acknowledged', 'mark_closed', 'noop')),
  priority integer not null default 100,
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.members(id) on delete set null,
  primary key (severity, recurrence_threshold)
);

insert into public.ingestion_remediation_escalation_matrix (
  severity, recurrence_threshold, action_type, priority, enabled
) values
  ('info', 1, 'mark_acknowledged', 30, true),
  ('warning', 2, 'mark_acknowledged', 20, true),
  ('critical', 3, 'noop', 10, true)
on conflict (severity, recurrence_threshold) do nothing;

alter table public.ingestion_remediation_escalation_matrix enable row level security;

drop policy if exists ingestion_remediation_escalation_read_mgmt on public.ingestion_remediation_escalation_matrix;
create policy ingestion_remediation_escalation_read_mgmt
on public.ingestion_remediation_escalation_matrix
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

drop policy if exists ingestion_remediation_escalation_write_mgmt on public.ingestion_remediation_escalation_matrix;
create policy ingestion_remediation_escalation_write_mgmt
on public.ingestion_remediation_escalation_matrix
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

create or replace function public.admin_resolve_remediation_action(
  p_alert_id bigint
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_alert record;
  v_recurrence integer := 0;
  v_matrix record;
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

  select * into v_alert
  from public.ingestion_alerts
  where id = p_alert_id;
  if v_alert is null then
    raise exception 'Alert not found: %', p_alert_id;
  end if;

  select count(*) into v_recurrence
  from public.ingestion_alerts a
  where a.alert_key = v_alert.alert_key
    and a.detected_at >= now() - interval '30 days';

  select * into v_matrix
  from public.ingestion_remediation_escalation_matrix m
  where m.severity = v_alert.severity
    and m.enabled is true
    and m.recurrence_threshold <= greatest(v_recurrence, 1)
  order by m.recurrence_threshold desc, m.priority asc
  limit 1;

  return jsonb_build_object(
    'alert_id', p_alert_id,
    'alert_key', v_alert.alert_key,
    'severity', v_alert.severity,
    'recurrence', v_recurrence,
    'action_type', coalesce(v_matrix.action_type, 'noop')
  );
end;
$$;

grant execute on function public.admin_resolve_remediation_action(bigint) to authenticated;

commit;
