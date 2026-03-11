-- Kanban UX foundation: modal edit/create for board cards with backend ACL.

create or replace function public.upsert_board_item(
  p_item_id uuid default null,
  p_board_id uuid default null,
  p_title text default null,
  p_description text default null,
  p_status text default 'backlog',
  p_assignee_id uuid default null,
  p_due_date date default null,
  p_tags text[] default null,
  p_labels jsonb default '[]'::jsonb,
  p_checklist jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member public.members%rowtype;
  v_board public.project_boards%rowtype;
  v_item_id uuid;
  v_board_id uuid;
  v_allowed boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_member from public.members where auth_id = auth.uid();
  if v_member.id is null then
    raise exception 'Member not found';
  end if;

  if p_item_id is not null then
    select * into v_board
    from public.project_boards pb
    join public.board_items bi on bi.board_id = pb.id
    where bi.id = p_item_id
    limit 1;
    v_board_id := v_board.id;
  else
    select * into v_board from public.project_boards where id = p_board_id limit 1;
    v_board_id := p_board_id;
  end if;

  if v_board.id is null then
    raise exception 'Board not found';
  end if;

  v_allowed := (
    coalesce(v_member.is_superadmin, false)
    or v_member.operational_role in ('manager', 'deputy_manager')
    or (v_member.operational_role = 'tribe_leader' and v_member.tribe_id = v_board.tribe_id)
  );

  if not v_allowed then
    raise exception 'Project management access required';
  end if;

  if p_item_id is null then
    if coalesce(trim(p_title), '') = '' then
      raise exception 'Title is required';
    end if;

    insert into public.board_items (
      board_id,
      title,
      description,
      status,
      assignee_id,
      due_date,
      tags,
      labels,
      checklist,
      position
    )
    values (
      v_board_id,
      trim(p_title),
      nullif(trim(coalesce(p_description, '')), ''),
      coalesce(nullif(trim(coalesce(p_status, '')), ''), 'backlog'),
      p_assignee_id,
      p_due_date,
      p_tags,
      coalesce(p_labels, '[]'::jsonb),
      coalesce(p_checklist, '[]'::jsonb),
      coalesce((
        select max(position) + 1
        from public.board_items
        where board_id = v_board_id
      ), 1)
    )
    returning id into v_item_id;

    return v_item_id;
  end if;

  update public.board_items
  set
    title = coalesce(nullif(trim(coalesce(p_title, '')), ''), title),
    description = case
      when p_description is null then description
      else nullif(trim(p_description), '')
    end,
    status = coalesce(nullif(trim(coalesce(p_status, '')), ''), status),
    assignee_id = p_assignee_id,
    due_date = p_due_date,
    tags = p_tags,
    labels = coalesce(p_labels, labels),
    checklist = coalesce(p_checklist, checklist),
    updated_at = now()
  where id = p_item_id
  returning id into v_item_id;

  if v_item_id is null then
    raise exception 'Board item not found';
  end if;

  return v_item_id;
end;
$$;

grant execute on function public.upsert_board_item(
  uuid, uuid, text, text, text, uuid, date, text[], jsonb, jsonb
) to authenticated;
