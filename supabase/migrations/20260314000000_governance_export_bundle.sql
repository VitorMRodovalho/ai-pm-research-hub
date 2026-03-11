-- ═══════════════════════════════════════════════════════════════════════════
-- Governance export bundle contracts
-- Date: 2026-03-14
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.exec_governance_export_bundle(
  p_window_days integer default 30
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_summary jsonb;
  v_trends jsonb;
  v_scorecards jsonb;
  v_slo jsonb;
  v_remediation jsonb;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      auth.role() = 'service_role'
      or v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
      or coalesce('chapter_liaison' = any(v_caller.designations), false)
      or coalesce('sponsor' = any(v_caller.designations), false)
      or coalesce('curator' = any(v_caller.designations), false)
    ) then
    raise exception 'Governance export access required';
  end if;

  v_summary := public.exec_partner_governance_summary(p_window_days);
  v_trends := public.exec_partner_governance_trends(p_window_days);
  v_scorecards := public.exec_partner_governance_scorecards(p_window_days);
  v_slo := public.exec_readiness_slo_dashboard(p_window_days);
  v_remediation := public.exec_remediation_effectiveness(p_window_days);

  return jsonb_build_object(
    'window_days', p_window_days,
    'generated_at', now(),
    'bundle', jsonb_build_object(
      'summary', v_summary,
      'trends', v_trends,
      'scorecards', v_scorecards,
      'slo_dashboard', v_slo,
      'remediation_effectiveness', v_remediation
    )
  );
end;
$$;

grant execute on function public.exec_governance_export_bundle(integer) to authenticated;

commit;
