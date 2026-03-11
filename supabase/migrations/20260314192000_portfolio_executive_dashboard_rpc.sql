-- W69: executive dashboard RPC for board portfolio.
create or replace function public.exec_portfolio_board_summary(
  p_include_inactive boolean default false
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  with boards as (
    select
      pb.id as board_id,
      pb.board_name,
      pb.board_scope,
      coalesce(pb.domain_key, 'tribe_general') as domain_key,
      pb.tribe_id,
      t.name as tribe_name
    from public.project_boards pb
    left join public.tribes t on t.id = pb.tribe_id
    where (p_include_inactive or pb.is_active = true)
  ),
  items as (
    select
      b.board_scope,
      b.domain_key,
      count(bi.id) as total_cards,
      count(*) filter (where bi.status = 'backlog') as backlog,
      count(*) filter (where bi.status = 'todo') as todo,
      count(*) filter (where bi.status = 'in_progress') as in_progress,
      count(*) filter (where bi.status = 'review') as review,
      count(*) filter (where bi.status = 'done') as done,
      count(*) filter (where bi.status = 'archived') as archived,
      count(*) filter (where bi.assignee_id is null and bi.status <> 'archived') as orphan_cards,
      count(*) filter (where bi.due_date::date < current_date and bi.status not in ('done', 'archived')) as overdue_cards
    from boards b
    left join public.board_items bi on bi.board_id = b.board_id
    group by b.board_scope, b.domain_key
  )
  select jsonb_build_object(
    'generated_at', now(),
    'by_lane', coalesce(jsonb_agg(jsonb_build_object(
      'board_scope', i.board_scope,
      'domain_key', i.domain_key,
      'total_cards', i.total_cards,
      'backlog', i.backlog,
      'todo', i.todo,
      'in_progress', i.in_progress,
      'review', i.review,
      'done', i.done,
      'archived', i.archived,
      'orphan_cards', i.orphan_cards,
      'overdue_cards', i.overdue_cards
    ) order by i.board_scope, i.domain_key), '[]'::jsonb)
  )
  from items i;
$$;

grant execute on function public.exec_portfolio_board_summary(boolean) to authenticated;
