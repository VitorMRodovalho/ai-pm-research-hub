-- ═══════════════════════════════════════════════════════════════════════════
-- Partner-safe governance summary contracts (read-only)
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.exec_partner_governance_summary(
  p_window_days integer default 30
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_days integer := greatest(coalesce(p_window_days, 30), 1);
  v_window_start timestamptz := now() - make_interval(days => v_days);
  v_total_batches integer := 0;
  v_total_snapshots integer := 0;
  v_snapshot_issue_sum integer := 0;
  v_open_critical integer := 0;
  v_open_warning integer := 0;
  v_latest_gate jsonb := '{}'::jsonb;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      auth.role() = 'service_role'
      or v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
      or coalesce('sponsor' = any(v_caller.designations), false)
      or coalesce('chapter_liaison' = any(v_caller.designations), false)
      or coalesce('curator' = any(v_caller.designations), false)
    ) then
    raise exception 'Partner governance access required';
  end if;

  select count(*) into v_total_batches
  from public.ingestion_batches b
  where b.started_at >= v_window_start;

  select
    count(*)::integer,
    coalesce(sum(s.issue_count), 0)::integer
  into
    v_total_snapshots,
    v_snapshot_issue_sum
  from public.data_quality_audit_snapshots s
  where s.created_at >= v_window_start;

  select count(*) into v_open_critical
  from public.ingestion_alerts a
  where a.status = 'open'
    and a.severity = 'critical';

  select count(*) into v_open_warning
  from public.ingestion_alerts a
  where a.status = 'open'
    and a.severity = 'warning';

  v_latest_gate := public.admin_release_readiness_gate(null, null, 'advisory');

  return jsonb_build_object(
    'window_days', v_days,
    'window_start', v_window_start,
    'ingestion_batches', v_total_batches,
    'audit_snapshots', v_total_snapshots,
    'snapshot_issue_sum', v_snapshot_issue_sum,
    'open_alerts', jsonb_build_object(
      'critical', v_open_critical,
      'warning', v_open_warning
    ),
    'readiness', jsonb_build_object(
      'mode', coalesce(v_latest_gate ->> 'mode', 'advisory'),
      'ready', coalesce((v_latest_gate ->> 'ready')::boolean, true),
      'reasons', coalesce(v_latest_gate -> 'reasons', '[]'::jsonb)
    )
  );
end;
$$;

grant execute on function public.exec_partner_governance_summary(integer) to authenticated;

commit;
