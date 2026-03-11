-- W81: archived board governance read/restore support.
create or replace function public.admin_list_archived_board_items(
  p_board_id uuid default null,
  p_limit integer default 200
)
returns table (
  id uuid,
  board_id uuid,
  board_name text,
  board_scope text,
  domain_key text,
  title text,
  assignee_name text,
  due_date date,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_member public.members%rowtype;
begin
  v_actor := auth.uid();
  if v_actor is null then
    raise exception 'Auth required';
  end if;

  select * into v_member
  from public.members
  where auth_user_id = v_actor
    and is_active = true
  limit 1;

  if v_member.id is null then
    raise exception 'Member not found';
  end if;

  if not (
    coalesce(v_member.is_superadmin, false)
    or v_member.operational_role in ('manager', 'deputy_manager')
    or exists (
      select 1 from unnest(coalesce(v_member.designations, array[]::text[])) d
      where d in ('co_gp', 'curator', 'comms_leader')
    )
  ) then
    raise exception 'Board governance access required';
  end if;

  return query
  select
    bi.id,
    bi.board_id,
    pb.board_name,
    pb.board_scope,
    coalesce(pb.domain_key, '') as domain_key,
    bi.title,
    coalesce(m.name, '') as assignee_name,
    bi.due_date,
    bi.updated_at
  from public.board_items bi
  join public.project_boards pb on pb.id = bi.board_id
  left join public.members m on m.id = bi.assignee_id
  where bi.status = 'archived'
    and (p_board_id is null or bi.board_id = p_board_id)
  order by bi.updated_at desc
  limit greatest(1, least(coalesce(p_limit, 200), 1000));
end;
$$;

grant execute on function public.admin_list_archived_board_items(uuid, integer) to authenticated;
