-- ═══════════════════════════════════════════════════════════════════════════
-- Ingestion source SLA and timeout governance
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.ingestion_source_sla (
  source text primary key,
  expected_max_minutes integer not null default 120,
  timeout_minutes integer not null default 240,
  escalation_severity text not null default 'warning' check (escalation_severity in ('info', 'warning', 'critical')),
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.members(id) on delete set null
);

insert into public.ingestion_source_sla(source, expected_max_minutes, timeout_minutes, escalation_severity, enabled)
values
  ('trello', 120, 240, 'warning', true),
  ('miro', 120, 240, 'warning', true),
  ('calendar', 60, 120, 'info', true),
  ('volunteer_csv', 60, 120, 'info', true),
  ('notion', 120, 240, 'warning', true),
  ('whatsapp', 120, 240, 'warning', false),
  ('mixed', 180, 360, 'critical', true)
on conflict (source) do nothing;

alter table public.ingestion_source_sla enable row level security;

drop policy if exists ingestion_source_sla_read_mgmt on public.ingestion_source_sla;
create policy ingestion_source_sla_read_mgmt
on public.ingestion_source_sla
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

drop policy if exists ingestion_source_sla_write_mgmt on public.ingestion_source_sla;
create policy ingestion_source_sla_write_mgmt
on public.ingestion_source_sla
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

create or replace function public.admin_set_ingestion_source_sla(
  p_source text,
  p_expected_max_minutes integer default 120,
  p_timeout_minutes integer default 240,
  p_escalation_severity text default 'warning',
  p_enabled boolean default true
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

  if p_escalation_severity not in ('info', 'warning', 'critical') then
    raise exception 'Invalid escalation severity: %', p_escalation_severity;
  end if;

  insert into public.ingestion_source_sla(
    source, expected_max_minutes, timeout_minutes, escalation_severity, enabled, updated_at, updated_by
  ) values (
    trim(p_source),
    greatest(coalesce(p_expected_max_minutes, 120), 1),
    greatest(coalesce(p_timeout_minutes, 240), 1),
    p_escalation_severity,
    coalesce(p_enabled, true),
    now(),
    v_caller.id
  )
  on conflict (source)
  do update set
    expected_max_minutes = excluded.expected_max_minutes,
    timeout_minutes = excluded.timeout_minutes,
    escalation_severity = excluded.escalation_severity,
    enabled = excluded.enabled,
    updated_at = now(),
    updated_by = v_caller.id;

  return jsonb_build_object(
    'success', true,
    'source', trim(p_source)
  );
end;
$$;

grant execute on function public.admin_set_ingestion_source_sla(text, integer, integer, text, boolean) to authenticated;

create or replace function public.admin_check_ingestion_source_timeout(
  p_source text,
  p_started_at timestamptz
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_sla record;
  v_elapsed_minutes integer;
  v_timed_out boolean := false;
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

  select * into v_sla
  from public.ingestion_source_sla
  where source = trim(p_source)
    and enabled is true
  limit 1;

  if v_sla is null then
    return jsonb_build_object(
      'source', trim(p_source),
      'has_policy', false,
      'timed_out', false
    );
  end if;

  v_elapsed_minutes := greatest(extract(epoch from (now() - p_started_at))::integer / 60, 0);
  v_timed_out := v_elapsed_minutes > v_sla.timeout_minutes;

  return jsonb_build_object(
    'source', trim(p_source),
    'has_policy', true,
    'timed_out', v_timed_out,
    'elapsed_minutes', v_elapsed_minutes,
    'timeout_minutes', v_sla.timeout_minutes,
    'expected_max_minutes', v_sla.expected_max_minutes,
    'escalation_severity', v_sla.escalation_severity
  );
end;
$$;

grant execute on function public.admin_check_ingestion_source_timeout(text, timestamptz) to authenticated;

commit;
