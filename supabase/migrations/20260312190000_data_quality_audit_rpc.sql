-- ═══════════════════════════════════════════════════════════════════════════
-- Data quality audit RPC for tribes, boards, and legacy continuity
-- Date: 2026-03-12
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.admin_data_quality_audit()
returns jsonb
language plpgsql
security definer
stable
as $$
declare
  v_caller record;
  v_result jsonb;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      auth.role() = 'service_role'
      or
      v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
      or coalesce('chapter_liaison' = any(v_caller.designations), false)
      or coalesce('sponsor' = any(v_caller.designations), false)
    ) then
    raise exception 'Internal audit access required';
  end if;

  with tribe6 as (
    select
      t.id,
      t.name,
      t.is_active,
      (
        select count(*)
        from public.project_boards pb
        where pb.tribe_id = t.id
      )::integer as board_count
    from public.tribes t
    where t.id = 6
    limit 1
  ),
  communication_tribe as (
    select
      t.id,
      t.name,
      t.is_active
    from public.tribes t
    where lower(trim(t.name)) in (
      'tribo comunicacao',
      'tribo comunicação',
      'time de comunicacao',
      'time de comunicação',
      'comunicacao',
      'comunicação'
    )
    order by t.updated_at desc nulls last
    limit 1
  ),
  communication_boards as (
    select
      count(*)::integer as total_communication_boards,
      count(*) filter (
        where pb.tribe_id = (select id from communication_tribe)
      )::integer as linked_to_communication_tribe
    from public.project_boards pb
    where coalesce(pb.domain_key, '') = 'communication'
      or lower(coalesce(pb.board_name, '')) like '%comunic%'
      or lower(coalesce(pb.board_name, '')) like '%midias%'
      or exists (
        select 1
        from public.board_items bi
        where bi.board_id = pb.id
          and bi.source_board in ('comunicacao_ciclo3', 'midias_sociais', 'social_media', 'comms_c3')
      )
  ),
  legacy_summary as (
    select
      count(*)::integer as legacy_tribes_total,
      count(*) filter (where cycle_code in ('cycle_1', 'cycle_2'))::integer as legacy_cycle_1_2_total,
      count(*) filter (where status = 'inactive')::integer as legacy_inactive_total
    from public.legacy_tribes
  ),
  lineage_summary as (
    select
      count(*)::integer as lineage_total,
      count(*) filter (where relation_type in ('renumbered_to', 'continues_as', 'legacy_of'))::integer as continuity_links_total
    from public.tribe_lineage
  ),
  link_quality as (
    select
      count(*)::integer as legacy_board_links_total,
      count(*) filter (
        where ltbl.relation_type = 'renumbered_continuity'
      )::integer as renumbered_links_total
    from public.legacy_tribe_board_links ltbl
  )
  select jsonb_build_object(
    'generated_at', now(),
    'tribe_6', coalesce((select to_jsonb(t6) from tribe6 t6), '{}'::jsonb),
    'communication_tribe', coalesce((select to_jsonb(ct) from communication_tribe ct), '{}'::jsonb),
    'communication_boards', coalesce((select to_jsonb(cb) from communication_boards cb), '{}'::jsonb),
    'legacy_summary', coalesce((select to_jsonb(ls) from legacy_summary ls), '{}'::jsonb),
    'lineage_summary', coalesce((select to_jsonb(lis) from lineage_summary lis), '{}'::jsonb),
    'legacy_link_summary', coalesce((select to_jsonb(lq) from link_quality lq), '{}'::jsonb),
    'flags', jsonb_build_object(
      'tribe_6_missing', coalesce((select id is null from tribe6), true),
      'tribe_6_without_boards', coalesce((select board_count = 0 from tribe6), true),
      'communication_tribe_missing', coalesce((select id is null from communication_tribe), true),
      'legacy_cycle_1_2_empty', coalesce((select legacy_cycle_1_2_total = 0 from legacy_summary), true),
      'lineage_empty', coalesce((select lineage_total = 0 from lineage_summary), true)
    )
  )
  into v_result;

  return v_result;
end;
$$;

grant execute on function public.admin_data_quality_audit() to authenticated;

commit;
