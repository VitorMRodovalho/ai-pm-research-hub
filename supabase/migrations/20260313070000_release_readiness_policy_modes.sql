-- ═══════════════════════════════════════════════════════════════════════════
-- Readiness gate policy modes (strict/advisory)
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.release_readiness_policies (
  policy_key text primary key,
  mode text not null check (mode in ('strict', 'advisory')),
  max_open_warnings integer not null default 5,
  require_fresh_snapshot_hours integer not null default 24,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.members(id) on delete set null
);

insert into public.release_readiness_policies (
  policy_key, mode, max_open_warnings, require_fresh_snapshot_hours
) values (
  'default', 'strict', 5, 24
)
on conflict (policy_key) do nothing;

alter table public.release_readiness_policies enable row level security;

drop policy if exists release_readiness_policies_read_mgmt on public.release_readiness_policies;
create policy release_readiness_policies_read_mgmt
on public.release_readiness_policies
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

drop policy if exists release_readiness_policies_write_mgmt on public.release_readiness_policies;
create policy release_readiness_policies_write_mgmt
on public.release_readiness_policies
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

create or replace function public.admin_set_release_readiness_policy(
  p_policy_key text default 'default',
  p_mode text default 'strict',
  p_max_open_warnings integer default 5,
  p_require_fresh_snapshot_hours integer default 24
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

  if p_mode not in ('strict', 'advisory') then
    raise exception 'Invalid readiness mode: %', p_mode;
  end if;

  insert into public.release_readiness_policies (
    policy_key, mode, max_open_warnings, require_fresh_snapshot_hours, updated_at, updated_by
  ) values (
    coalesce(nullif(trim(p_policy_key), ''), 'default'),
    p_mode,
    greatest(coalesce(p_max_open_warnings, 5), 0),
    greatest(coalesce(p_require_fresh_snapshot_hours, 24), 1),
    now(),
    v_caller.id
  )
  on conflict (policy_key)
  do update set
    mode = excluded.mode,
    max_open_warnings = excluded.max_open_warnings,
    require_fresh_snapshot_hours = excluded.require_fresh_snapshot_hours,
    updated_at = now(),
    updated_by = v_caller.id;

  return jsonb_build_object(
    'success', true,
    'policy_key', coalesce(nullif(trim(p_policy_key), ''), 'default'),
    'mode', p_mode
  );
end;
$$;

grant execute on function public.admin_set_release_readiness_policy(text, text, integer, integer) to authenticated;

drop function if exists public.admin_release_readiness_gate(integer, integer);
create or replace function public.admin_release_readiness_gate(
  p_max_open_warnings integer default null,
  p_require_fresh_snapshot_hours integer default null,
  p_policy_mode text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_snapshot record;
  v_policy record;
  v_mode text := 'strict';
  v_allowed_warnings integer := 5;
  v_snapshot_hours integer := 24;
  v_open_critical integer := 0;
  v_open_warning integer := 0;
  v_is_ready boolean := true;
  v_reasons text[] := '{}';
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

  select * into v_policy
  from public.release_readiness_policies
  where policy_key = 'default'
  limit 1;

  if v_policy is not null then
    v_mode := v_policy.mode;
    v_allowed_warnings := v_policy.max_open_warnings;
    v_snapshot_hours := v_policy.require_fresh_snapshot_hours;
  end if;

  v_mode := coalesce(nullif(trim(coalesce(p_policy_mode, '')), ''), v_mode);
  if v_mode not in ('strict', 'advisory') then
    raise exception 'Invalid readiness mode: %', v_mode;
  end if;

  if p_max_open_warnings is not null then
    v_allowed_warnings := greatest(p_max_open_warnings, 0);
  end if;
  if p_require_fresh_snapshot_hours is not null then
    v_snapshot_hours := greatest(p_require_fresh_snapshot_hours, 1);
  end if;

  select id, created_at, issue_count, flag_count, run_context, run_label
  into v_snapshot
  from public.data_quality_audit_snapshots
  order by created_at desc
  limit 1;

  select count(*) into v_open_critical
  from public.ingestion_alerts
  where status = 'open'
    and severity = 'critical';

  select count(*) into v_open_warning
  from public.ingestion_alerts
  where status = 'open'
    and severity = 'warning';

  if v_snapshot is null then
    v_reasons := array_append(v_reasons, 'missing_audit_snapshot');
  else
    if v_snapshot.issue_count > 0 then
      v_reasons := array_append(v_reasons, 'latest_snapshot_has_issues');
    end if;
    if v_snapshot.created_at < now() - make_interval(hours => v_snapshot_hours) then
      v_reasons := array_append(v_reasons, 'snapshot_stale');
    end if;
  end if;

  if v_open_critical > 0 then
    v_reasons := array_append(v_reasons, 'open_critical_alerts');
  end if;
  if v_open_warning > v_allowed_warnings then
    v_reasons := array_append(v_reasons, 'open_warning_threshold_exceeded');
  end if;

  if v_mode = 'strict' then
    v_is_ready := coalesce(array_length(v_reasons, 1), 0) = 0;
  else
    -- advisory mode does not block release but still returns full reasons.
    v_is_ready := true;
  end if;

  return jsonb_build_object(
    'ready', v_is_ready,
    'mode', v_mode,
    'reasons', v_reasons,
    'thresholds', jsonb_build_object(
      'max_open_warnings', v_allowed_warnings,
      'require_fresh_snapshot_hours', v_snapshot_hours
    ),
    'open_alerts', jsonb_build_object(
      'critical', v_open_critical,
      'warning', v_open_warning
    ),
    'snapshot', case
      when v_snapshot is null then null
      else jsonb_build_object(
        'id', v_snapshot.id,
        'created_at', v_snapshot.created_at,
        'issue_count', v_snapshot.issue_count,
        'flag_count', v_snapshot.flag_count,
        'run_context', v_snapshot.run_context,
        'run_label', v_snapshot.run_label
      )
    end
  );
end;
$$;

grant execute on function public.admin_release_readiness_gate(integer, integer, text) to authenticated;

commit;
