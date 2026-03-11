-- ═══════════════════════════════════════════════════════════════════════════
-- Partner governance scorecard contracts
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.exec_partner_governance_scorecards(
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
  v_total_batches integer := 0;
  v_open_critical integer := 0;
  v_open_warning integer := 0;
  v_readiness_ready_rate numeric := 0;
  v_governance_score numeric := 0;
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

  v_summary := public.exec_partner_governance_summary(p_window_days);
  v_trends := public.exec_partner_governance_trends(p_window_days);

  v_total_batches := coalesce((v_summary ->> 'ingestion_batches')::integer, 0);
  v_open_critical := coalesce((v_summary -> 'open_alerts' ->> 'critical')::integer, 0);
  v_open_warning := coalesce((v_summary -> 'open_alerts' ->> 'warning')::integer, 0);

  with agg as (
    select
      sum((x->>'total')::numeric) as total,
      sum((x->>'ready_true')::numeric) as ready_true
    from jsonb_array_elements(coalesce(v_trends -> 'readiness_trend', '[]'::jsonb)) x
  )
  select
    case
      when coalesce(total, 0) = 0 then 0
      else round((ready_true / total) * 100, 2)
    end
  into v_readiness_ready_rate
  from agg;

  v_governance_score := greatest(
    0,
    least(
      100,
      round(
        (coalesce(v_readiness_ready_rate, 0) * 0.7)
        + (least(v_total_batches, 20) * 1.5)
        - (v_open_critical * 15)
        - (v_open_warning * 3),
        2
      )
    )
  );

  return jsonb_build_object(
    'window_days', p_window_days,
    'scorecards', jsonb_build_object(
      'governance_score', v_governance_score,
      'readiness_ready_rate', coalesce(v_readiness_ready_rate, 0),
      'open_critical_alerts', v_open_critical,
      'open_warning_alerts', v_open_warning,
      'ingestion_batches', v_total_batches
    ),
    'summary', v_summary,
    'trends', v_trends
  );
end;
$$;

grant execute on function public.exec_partner_governance_scorecards(integer) to authenticated;

commit;
