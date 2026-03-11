-- W86: portfolio data sanity v2 run ledger.
create table if not exists public.portfolio_data_sanity_runs (
  id bigint generated always as identity primary key,
  run_by uuid not null references public.members(id),
  summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.admin_run_portfolio_data_sanity()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_member public.members%rowtype;
  v_summary jsonb;
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

  if not (coalesce(v_member.is_superadmin, false) or v_member.operational_role in ('manager', 'deputy_manager')) then
    raise exception 'Admin project management access required';
  end if;

  v_summary := jsonb_build_object(
    'orphan_items', (
      select count(*)
      from public.board_items bi
      left join public.project_boards pb on pb.id = bi.board_id
      where pb.id is null
    ),
    'items_in_inactive_board', (
      select count(*)
      from public.board_items bi
      join public.project_boards pb on pb.id = bi.board_id
      where pb.is_active = false
        and bi.status <> 'archived'
    ),
    'global_with_tribe_id', (
      select count(*)
      from public.project_boards
      where board_scope = 'global'
        and tribe_id is not null
    ),
    'tribe_without_tribe_id', (
      select count(*)
      from public.project_boards
      where board_scope = 'tribe'
        and tribe_id is null
    )
  );

  insert into public.portfolio_data_sanity_runs(run_by, summary)
  values (v_member.id, v_summary);

  return jsonb_build_object('success', true, 'summary', v_summary);
end;
$$;

grant execute on function public.admin_run_portfolio_data_sanity() to authenticated;
