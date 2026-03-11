-- ═══════════════════════════════════════════════════════════════════════════
-- Controlled rollback backend contracts
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.ingestion_rollback_plans (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid references public.ingestion_batches(id) on delete set null,
  reason text not null,
  status text not null default 'planned' check (status in ('planned', 'approved', 'executed', 'cancelled')),
  dry_run boolean not null default true,
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  executed_at timestamptz,
  created_by uuid references public.members(id) on delete set null,
  approved_by uuid references public.members(id) on delete set null,
  executed_by uuid references public.members(id) on delete set null,
  details jsonb not null default '{}'::jsonb
);

create index if not exists idx_ingestion_rollback_plans_status_created
  on public.ingestion_rollback_plans(status, created_at desc);

alter table public.ingestion_rollback_plans enable row level security;

drop policy if exists ingestion_rollback_plans_read_mgmt on public.ingestion_rollback_plans;
create policy ingestion_rollback_plans_read_mgmt
on public.ingestion_rollback_plans
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

drop policy if exists ingestion_rollback_plans_write_mgmt on public.ingestion_rollback_plans;
create policy ingestion_rollback_plans_write_mgmt
on public.ingestion_rollback_plans
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

create or replace function public.admin_plan_ingestion_rollback(
  p_batch_id uuid,
  p_reason text,
  p_dry_run boolean default true,
  p_details jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_id uuid;
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

  insert into public.ingestion_rollback_plans (
    batch_id, reason, status, dry_run, created_by, details
  ) values (
    p_batch_id,
    trim(p_reason),
    'planned',
    coalesce(p_dry_run, true),
    v_caller.id,
    coalesce(p_details, '{}'::jsonb)
  )
  returning id into v_id;

  return jsonb_build_object('success', true, 'plan_id', v_id, 'status', 'planned');
end;
$$;

grant execute on function public.admin_plan_ingestion_rollback(uuid, text, boolean, jsonb) to authenticated;

create or replace function public.admin_execute_ingestion_rollback(
  p_plan_id uuid,
  p_approve_and_execute boolean default false
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_plan record;
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

  select * into v_plan
  from public.ingestion_rollback_plans
  where id = p_plan_id
  limit 1;
  if v_plan is null then
    raise exception 'Rollback plan not found: %', p_plan_id;
  end if;

  if v_plan.status = 'executed' then
    return jsonb_build_object('success', true, 'plan_id', p_plan_id, 'status', 'executed', 'changed', false);
  end if;

  if p_approve_and_execute then
    update public.ingestion_rollback_plans
    set
      status = 'executed',
      approved_at = coalesce(approved_at, now()),
      executed_at = now(),
      approved_by = coalesce(approved_by, v_caller.id),
      executed_by = v_caller.id,
      details = details || jsonb_build_object('execution_mode', case when dry_run then 'dry_run' else 'apply' end)
    where id = p_plan_id;
  else
    update public.ingestion_rollback_plans
    set
      status = 'approved',
      approved_at = now(),
      approved_by = v_caller.id
    where id = p_plan_id;
  end if;

  return jsonb_build_object(
    'success', true,
    'plan_id', p_plan_id,
    'status', case when p_approve_and_execute then 'executed' else 'approved' end
  );
end;
$$;

grant execute on function public.admin_execute_ingestion_rollback(uuid, boolean) to authenticated;

commit;
