-- ═══════════════════════════════════════════════════════════════════════════
-- Rollback simulation harness contracts
-- Date: 2026-03-14
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.admin_simulate_ingestion_rollback(
  p_plan_id uuid
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_plan record;
  v_batch_file_count integer := 0;
  v_risk_score integer := 0;
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

  if v_plan.batch_id is not null then
    select count(*)::integer into v_batch_file_count
    from public.ingestion_batch_files f
    where f.batch_id = v_plan.batch_id;
  end if;

  v_risk_score := least(100, greatest(0,
    (case when v_plan.dry_run then 15 else 45 end)
    + (case when v_batch_file_count > 100 then 25 when v_batch_file_count > 20 then 15 else 5 end)
    + (case when v_plan.second_approved_by is null then 20 else 0 end)
  ));

  return jsonb_build_object(
    'plan_id', p_plan_id,
    'batch_id', v_plan.batch_id,
    'status', v_plan.status,
    'dry_run', v_plan.dry_run,
    'batch_file_count', v_batch_file_count,
    'risk_score', v_risk_score,
    'recommended', case when v_risk_score <= 40 then 'proceed' when v_risk_score <= 70 then 'review' else 'hold' end
  );
end;
$$;

grant execute on function public.admin_simulate_ingestion_rollback(uuid) to authenticated;

commit;
