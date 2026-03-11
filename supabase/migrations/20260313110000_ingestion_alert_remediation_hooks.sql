-- ═══════════════════════════════════════════════════════════════════════════
-- Automated remediation hooks for recurring ingestion alerts
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.ingestion_alert_remediation_rules (
  alert_key text primary key,
  enabled boolean not null default true,
  max_attempts integer not null default 3,
  action_type text not null default 'mark_acknowledged' check (action_type in ('mark_acknowledged', 'mark_closed', 'noop')),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.members(id) on delete set null
);

create table if not exists public.ingestion_alert_remediation_runs (
  id bigserial primary key,
  alert_id bigint not null references public.ingestion_alerts(id) on delete cascade,
  alert_key text not null,
  action_type text not null,
  attempt integer not null,
  status text not null check (status in ('success', 'skipped', 'failed')),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid references public.members(id) on delete set null
);

create index if not exists idx_ingestion_alert_remediation_runs_alert
  on public.ingestion_alert_remediation_runs(alert_id, created_at desc);

alter table public.ingestion_alert_remediation_rules enable row level security;
alter table public.ingestion_alert_remediation_runs enable row level security;

drop policy if exists ingestion_alert_remediation_rules_read_mgmt on public.ingestion_alert_remediation_rules;
create policy ingestion_alert_remediation_rules_read_mgmt
on public.ingestion_alert_remediation_rules
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

drop policy if exists ingestion_alert_remediation_rules_write_mgmt on public.ingestion_alert_remediation_rules;
create policy ingestion_alert_remediation_rules_write_mgmt
on public.ingestion_alert_remediation_rules
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

drop policy if exists ingestion_alert_remediation_runs_read_mgmt on public.ingestion_alert_remediation_runs;
create policy ingestion_alert_remediation_runs_read_mgmt
on public.ingestion_alert_remediation_runs
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

drop policy if exists ingestion_alert_remediation_runs_write_mgmt on public.ingestion_alert_remediation_runs;
create policy ingestion_alert_remediation_runs_write_mgmt
on public.ingestion_alert_remediation_runs
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

create or replace function public.admin_set_ingestion_alert_remediation_rule(
  p_alert_key text,
  p_enabled boolean default true,
  p_max_attempts integer default 3,
  p_action_type text default 'mark_acknowledged'
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
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

  if p_action_type not in ('mark_acknowledged', 'mark_closed', 'noop') then
    raise exception 'Invalid remediation action: %', p_action_type;
  end if;

  insert into public.ingestion_alert_remediation_rules (
    alert_key, enabled, max_attempts, action_type, updated_at, updated_by
  ) values (
    trim(p_alert_key),
    coalesce(p_enabled, true),
    greatest(coalesce(p_max_attempts, 3), 1),
    p_action_type,
    now(),
    v_caller.id
  )
  on conflict (alert_key)
  do update set
    enabled = excluded.enabled,
    max_attempts = excluded.max_attempts,
    action_type = excluded.action_type,
    updated_at = now(),
    updated_by = v_caller.id;

  return jsonb_build_object('success', true, 'alert_key', trim(p_alert_key));
end;
$$;

grant execute on function public.admin_set_ingestion_alert_remediation_rule(text, boolean, integer, text) to authenticated;

create or replace function public.admin_run_ingestion_alert_remediation(
  p_alert_id bigint
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_alert record;
  v_rule record;
  v_attempt integer := 0;
  v_status text := 'skipped';
  v_reason text := null;
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

  select * into v_rule
  from public.ingestion_alert_remediation_rules
  where alert_key = v_alert.alert_key
  limit 1;

  if v_rule is null or v_rule.enabled is not true then
    v_reason := 'no_enabled_rule';
    insert into public.ingestion_alert_remediation_runs(alert_id, alert_key, action_type, attempt, status, details, created_by)
    values (p_alert_id, v_alert.alert_key, coalesce(v_rule.action_type, 'noop'), 0, 'skipped', jsonb_build_object('reason', v_reason), v_caller.id);
    return jsonb_build_object('success', true, 'status', 'skipped', 'reason', v_reason);
  end if;

  select count(*) + 1 into v_attempt
  from public.ingestion_alert_remediation_runs r
  where r.alert_id = p_alert_id;

  if v_attempt > v_rule.max_attempts then
    v_reason := 'max_attempts_exceeded';
    insert into public.ingestion_alert_remediation_runs(alert_id, alert_key, action_type, attempt, status, details, created_by)
    values (p_alert_id, v_alert.alert_key, v_rule.action_type, v_attempt, 'skipped', jsonb_build_object('reason', v_reason), v_caller.id);
    return jsonb_build_object('success', true, 'status', 'skipped', 'reason', v_reason, 'attempt', v_attempt);
  end if;

  if v_rule.action_type = 'mark_acknowledged' then
    perform public.admin_update_ingestion_alert_status(p_alert_id, 'acknowledged', 'auto-remediation', jsonb_build_object('attempt', v_attempt));
    v_status := 'success';
  elsif v_rule.action_type = 'mark_closed' then
    perform public.admin_update_ingestion_alert_status(p_alert_id, 'closed', 'auto-remediation', jsonb_build_object('attempt', v_attempt));
    v_status := 'success';
  else
    v_status := 'skipped';
    v_reason := 'noop_action';
  end if;

  insert into public.ingestion_alert_remediation_runs(alert_id, alert_key, action_type, attempt, status, details, created_by)
  values (
    p_alert_id,
    v_alert.alert_key,
    v_rule.action_type,
    v_attempt,
    v_status,
    jsonb_build_object('reason', coalesce(v_reason, 'applied')),
    v_caller.id
  );

  return jsonb_build_object(
    'success', true,
    'status', v_status,
    'attempt', v_attempt,
    'action_type', v_rule.action_type
  );
end;
$$;

grant execute on function public.admin_run_ingestion_alert_remediation(bigint) to authenticated;

commit;
