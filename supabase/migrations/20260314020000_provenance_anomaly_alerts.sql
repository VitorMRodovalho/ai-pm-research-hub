-- ═══════════════════════════════════════════════════════════════════════════
-- Provenance anomaly alert contracts
-- Date: 2026-03-14
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.admin_raise_provenance_anomaly_alert(
  p_batch_id uuid
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_verify jsonb;
  v_invalid integer := 0;
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

  v_verify := public.admin_verify_ingestion_provenance_batch(p_batch_id);
  v_invalid := coalesce((v_verify ->> 'invalid_signatures')::integer, 0);

  if v_invalid > 0 then
    insert into public.ingestion_alerts (alert_key, severity, status, summary, details, batch_id, created_by)
    values (
      'provenance_signature_anomaly',
      'critical',
      'open',
      'Provenance signature anomaly detected for ingestion batch.',
      v_verify,
      p_batch_id,
      v_caller.id
    );
  end if;

  return jsonb_build_object(
    'batch_id', p_batch_id,
    'invalid_signatures', v_invalid,
    'alert_emitted', v_invalid > 0
  );
end;
$$;

grant execute on function public.admin_raise_provenance_anomaly_alert(uuid) to authenticated;

commit;
