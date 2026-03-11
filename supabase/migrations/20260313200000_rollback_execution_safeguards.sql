-- ═══════════════════════════════════════════════════════════════════════════
-- Rollback execution safeguards and dual-approval checks
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

alter table public.ingestion_rollback_plans
  add column if not exists second_approved_at timestamptz,
  add column if not exists second_approved_by uuid references public.members(id) on delete set null,
  add column if not exists execution_window_start timestamptz,
  add column if not exists execution_window_end timestamptz;

create or replace function public.admin_approve_ingestion_rollback(
  p_plan_id uuid,
  p_execution_window_start timestamptz default null,
  p_execution_window_end timestamptz default null
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
  if v_plan.status in ('executed', 'cancelled') then
    raise exception 'Rollback plan cannot be approved in status: %', v_plan.status;
  end if;

  if v_plan.approved_by is null then
    update public.ingestion_rollback_plans
    set
      status = 'approved',
      approved_by = v_caller.id,
      approved_at = now(),
      execution_window_start = coalesce(p_execution_window_start, execution_window_start),
      execution_window_end = coalesce(p_execution_window_end, execution_window_end)
    where id = p_plan_id;
    return jsonb_build_object('success', true, 'plan_id', p_plan_id, 'approval_stage', 1);
  end if;

  if v_plan.approved_by = v_caller.id then
    raise exception 'Second approval must be from a different approver';
  end if;

  update public.ingestion_rollback_plans
  set
    second_approved_by = v_caller.id,
    second_approved_at = now(),
    execution_window_start = coalesce(p_execution_window_start, execution_window_start),
    execution_window_end = coalesce(p_execution_window_end, execution_window_end)
  where id = p_plan_id;

  return jsonb_build_object('success', true, 'plan_id', p_plan_id, 'approval_stage', 2);
end;
$$;

grant execute on function public.admin_approve_ingestion_rollback(uuid, timestamptz, timestamptz) to authenticated;

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
    perform public.admin_approve_ingestion_rollback(
      p_plan_id,
      coalesce(v_plan.execution_window_start, now() - interval '5 minutes'),
      coalesce(v_plan.execution_window_end, now() + interval '55 minutes')
    );
    select * into v_plan from public.ingestion_rollback_plans where id = p_plan_id;
  end if;

  if v_plan.approved_by is null or v_plan.second_approved_by is null then
    raise exception 'Rollback execution requires dual approval';
  end if;
  if v_plan.execution_window_start is not null and now() < v_plan.execution_window_start then
    raise exception 'Rollback execution is before allowed window';
  end if;
  if v_plan.execution_window_end is not null and now() > v_plan.execution_window_end then
    raise exception 'Rollback execution is after allowed window';
  end if;

  update public.ingestion_rollback_plans
  set
    status = 'executed',
    executed_at = now(),
    executed_by = v_caller.id,
    details = details || jsonb_build_object(
      'execution_mode', case when dry_run then 'dry_run' else 'apply' end,
      'safeguards', jsonb_build_object('dual_approval', true, 'window_checked', true)
    )
  where id = p_plan_id;

  return jsonb_build_object('success', true, 'plan_id', p_plan_id, 'status', 'executed');
end;
$$;

grant execute on function public.admin_execute_ingestion_rollback(uuid, boolean) to authenticated;

commit;
