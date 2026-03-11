-- W64: cross-board move policy within same taxonomy lane.
create or replace function public.move_board_item_to_board(
  p_item_id bigint,
  p_target_board_id bigint,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_member public.members%rowtype;
  v_source record;
  v_target record;
begin
  v_actor := auth.uid();
  if v_actor is null then
    raise exception 'Auth required';
  end if;

  select * into v_member
  from public.members m
  where m.auth_user_id = v_actor
    and m.is_active = true
  limit 1;

  if v_member.id is null then
    raise exception 'Member not found';
  end if;

  select bi.id,
         bi.board_id,
         sb.board_scope as source_scope,
         coalesce(sb.domain_key, '') as source_domain,
         sb.tribe_id as source_tribe_id,
         sb.is_active as source_active
    into v_source
  from public.board_items bi
  join public.project_boards sb on sb.id = bi.board_id
  where bi.id = p_item_id;

  if v_source.id is null then
    raise exception 'Board item not found';
  end if;

  select tb.id,
         tb.board_scope as target_scope,
         coalesce(tb.domain_key, '') as target_domain,
         tb.tribe_id as target_tribe_id,
         tb.is_active as target_active
    into v_target
  from public.project_boards tb
  where tb.id = p_target_board_id;

  if v_target.id is null then
    raise exception 'Target board not found';
  end if;

  if v_target.target_active is not true then
    raise exception 'Target board must be active';
  end if;

  if v_source.source_scope is distinct from v_target.target_scope then
    raise exception 'Cross-board move denied: board_scope mismatch';
  end if;

  if coalesce(v_source.source_domain, '') is distinct from coalesce(v_target.target_domain, '') then
    raise exception 'Cross-board move denied: domain_key mismatch';
  end if;

  if v_source.source_scope = 'tribe' and v_source.source_tribe_id is distinct from v_target.target_tribe_id then
    raise exception 'Cross-board move denied: tribe board must keep tribe_id';
  end if;

  if not (
    coalesce(v_member.is_superadmin, false)
    or v_member.operational_role in ('manager', 'deputy_manager', 'tribe_leader', 'communicator')
    or exists (
      select 1
      from unnest(coalesce(v_member.designations, array[]::text[])) d
      where d in ('co_gp', 'curator', 'comms_leader', 'comms_member')
    )
  ) then
    raise exception 'Project management access required';
  end if;

  update public.board_items
     set board_id = p_target_board_id,
         updated_at = now()
   where id = p_item_id;

  return jsonb_build_object(
    'success', true,
    'item_id', p_item_id,
    'from_board_id', v_source.board_id,
    'to_board_id', p_target_board_id,
    'reason', coalesce(p_reason, '')
  );
end;
$$;

grant execute on function public.move_board_item_to_board(bigint, bigint, text) to authenticated;
