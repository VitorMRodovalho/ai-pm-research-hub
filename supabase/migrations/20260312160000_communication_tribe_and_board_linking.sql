-- ═══════════════════════════════════════════════════════════════════════════
-- Communication tribe domain and board linking
-- Date: 2026-03-12
-- ═══════════════════════════════════════════════════════════════════════════

begin;

alter table public.project_boards
  add column if not exists domain_key text,
  add column if not exists cycle_scope text;

create index if not exists idx_project_boards_domain_key
  on public.project_boards (domain_key)
  where domain_key is not null;

create or replace function public.admin_ensure_communication_tribe(
  p_name text default 'Tribo Comunicacao',
  p_quadrant integer default 2,
  p_quadrant_name text default 'Quadrante 2',
  p_notes text default 'Tribo transversal para comunicacao e midias'
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_tribe record;
  v_new_id integer;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
    ) then
    raise exception 'Project management access required';
  end if;

  select *
  into v_tribe
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
  limit 1;

  if v_tribe is null then
    select coalesce(max(id), 0) + 1 into v_new_id from public.tribes;

    insert into public.tribes (
      id, name, quadrant, quadrant_name, notes, is_active, updated_at, updated_by
    ) values (
      v_new_id,
      trim(p_name),
      coalesce(p_quadrant, 2),
      trim(coalesce(p_quadrant_name, 'Quadrante 2')),
      nullif(trim(coalesce(p_notes, '')), ''),
      true,
      now(),
      v_caller.id
    )
    returning * into v_tribe;
  else
    update public.tribes
    set is_active = true,
        quadrant = coalesce(p_quadrant, quadrant),
        quadrant_name = coalesce(nullif(trim(p_quadrant_name), ''), quadrant_name),
        updated_at = now(),
        updated_by = v_caller.id
    where id = v_tribe.id
    returning * into v_tribe;
  end if;

  return jsonb_build_object(
    'success', true,
    'tribe_id', v_tribe.id,
    'tribe_name', v_tribe.name
  );
end;
$$;

grant execute on function public.admin_ensure_communication_tribe(text, integer, text, text) to authenticated;

create or replace function public.admin_link_communication_boards(
  p_tribe_id integer default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_target_tribe_id integer;
  v_updated integer := 0;
  v_result jsonb;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
    ) then
    raise exception 'Project management access required';
  end if;

  if p_tribe_id is null then
    select (public.admin_ensure_communication_tribe() ->> 'tribe_id')::integer into v_target_tribe_id;
  else
    v_target_tribe_id := p_tribe_id;
  end if;

  update public.project_boards pb
  set tribe_id = v_target_tribe_id,
      domain_key = 'communication',
      updated_at = now()
  where (
    lower(coalesce(pb.board_name, '')) like '%comunic%'
    or lower(coalesce(pb.board_name, '')) like '%midias%'
    or exists (
      select 1
      from public.board_items bi
      where bi.board_id = pb.id
        and bi.source_board in ('comunicacao_ciclo3', 'midias_sociais', 'social_media', 'comms_c3')
    )
  )
    and (pb.tribe_id is distinct from v_target_tribe_id or coalesce(pb.domain_key, '') <> 'communication');

  get diagnostics v_updated = row_count;

  v_result := jsonb_build_object(
    'success', true,
    'tribe_id', v_target_tribe_id,
    'boards_linked', v_updated
  );

  return v_result;
end;
$$;

grant execute on function public.admin_link_communication_boards(integer) to authenticated;

commit;
