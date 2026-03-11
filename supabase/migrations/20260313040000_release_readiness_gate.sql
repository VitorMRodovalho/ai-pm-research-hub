-- ═══════════════════════════════════════════════════════════════════════════
-- Release readiness gate across audit snapshots and ingestion alerts
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.admin_release_readiness_gate(
  p_max_open_warnings integer default 5,
  p_require_fresh_snapshot_hours integer default 24
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_snapshot record;
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
    v_is_ready := false;
    v_reasons := array_append(v_reasons, 'missing_audit_snapshot');
  else
    if v_snapshot.issue_count > 0 then
      v_is_ready := false;
      v_reasons := array_append(v_reasons, 'latest_snapshot_has_issues');
    end if;
    if v_snapshot.created_at < now() - make_interval(hours => greatest(coalesce(p_require_fresh_snapshot_hours, 24), 1)) then
      v_is_ready := false;
      v_reasons := array_append(v_reasons, 'snapshot_stale');
    end if;
  end if;

  if v_open_critical > 0 then
    v_is_ready := false;
    v_reasons := array_append(v_reasons, 'open_critical_alerts');
  end if;

  if v_open_warning > greatest(coalesce(p_max_open_warnings, 5), 0) then
    v_is_ready := false;
    v_reasons := array_append(v_reasons, 'open_warning_threshold_exceeded');
  end if;

  return jsonb_build_object(
    'ready', v_is_ready,
    'reasons', v_reasons,
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

grant execute on function public.admin_release_readiness_gate(integer, integer) to authenticated;

commit;
