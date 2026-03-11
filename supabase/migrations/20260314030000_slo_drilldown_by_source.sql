-- ═══════════════════════════════════════════════════════════════════════════
-- SLO drill-down by ingestion source contracts
-- Date: 2026-03-14
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.exec_readiness_slo_by_source(
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
  v_sources jsonb := '[]'::jsonb;
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
    ) then
    raise exception 'SLO drill-down access required';
  end if;

  with grouped as (
    select
      f.source_kind,
      count(*)::integer as files_total,
      count(*) filter (where f.status = 'processed')::integer as files_processed,
      count(*) filter (where f.status = 'skipped')::integer as files_skipped
    from public.ingestion_batch_files f
    join public.ingestion_batches b on b.id = f.batch_id
    where b.started_at >= v_window_start
    group by f.source_kind
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'source_kind', source_kind,
        'files_total', files_total,
        'files_processed', files_processed,
        'files_skipped', files_skipped,
        'processed_rate', case when files_total = 0 then 0 else round((files_processed::numeric / files_total) * 100, 2) end
      ) order by source_kind
    ),
    '[]'::jsonb
  )
  into v_sources
  from grouped;

  return jsonb_build_object(
    'window_days', v_days,
    'window_start', v_window_start,
    'sources', v_sources
  );
end;
$$;

grant execute on function public.exec_readiness_slo_by_source(integer) to authenticated;

commit;
