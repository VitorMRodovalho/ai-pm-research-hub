-- ═══════════════════════════════════════════════════════════════════════════
-- Automated post-ingestion chain orchestrator
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.admin_run_post_ingestion_chain(
  p_batch_id uuid default null,
  p_capture_snapshot boolean default true,
  p_gate_mode text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_healthcheck jsonb;
  v_snapshot jsonb := null;
  v_gate jsonb;
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

  v_healthcheck := public.admin_run_post_ingestion_healthcheck(p_batch_id);

  if coalesce(p_capture_snapshot, true) then
    v_snapshot := public.admin_capture_data_quality_snapshot(
      'post_ingestion_chain',
      'automated_chain',
      p_batch_id
    );
  end if;

  v_gate := public.admin_release_readiness_gate(
    null,
    null,
    p_gate_mode
  );

  return jsonb_build_object(
    'success', true,
    'batch_id', p_batch_id,
    'healthcheck', v_healthcheck,
    'snapshot', v_snapshot,
    'gate', v_gate
  );
end;
$$;

grant execute on function public.admin_run_post_ingestion_chain(uuid, boolean, text) to authenticated;

commit;
