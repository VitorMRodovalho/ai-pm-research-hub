-- ═══════════════════════════════════════════════════════════════════════════
-- End-to-end dry-run rehearsal orchestrator
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.admin_run_dry_rehearsal_chain(
  p_context_label text default 'dry_rehearsal',
  p_gate_mode text default 'advisory'
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_audit jsonb;
  v_gate jsonb;
  v_timeout_probe jsonb;
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

  -- Read-only checks for rehearsal. This chain intentionally avoids
  -- mutating ingestion batches and alert states.
  v_audit := public.admin_data_quality_audit();
  v_gate := public.admin_release_readiness_gate(null, null, p_gate_mode);
  v_timeout_probe := public.admin_check_ingestion_source_timeout('mixed', now() - interval '10 minutes');

  return jsonb_build_object(
    'success', true,
    'context_label', coalesce(nullif(trim(coalesce(p_context_label, '')), ''), 'dry_rehearsal'),
    'mode', 'dry_run',
    'audit', v_audit,
    'gate', v_gate,
    'timeout_probe', v_timeout_probe
  );
end;
$$;

grant execute on function public.admin_run_dry_rehearsal_chain(text, text) to authenticated;

commit;
