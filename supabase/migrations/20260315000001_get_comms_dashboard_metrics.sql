-- ============================================================================
-- W85: RPC get_comms_dashboard_metrics
-- Cockpit da Tribo 8 (Comunicação): métricas de boards com domain_key = 'communication'
-- Cruza project_boards + board_items + tags (formato: vídeo, artigo, LinkedIn...)
-- Date: 2026-03-15
-- ============================================================================

create or replace function public.get_comms_dashboard_metrics()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_backlog int;
  v_overdue int;
  v_total int;
  v_by_status jsonb;
  v_by_format jsonb;
  v_board_ids uuid[];
begin
  -- Boards de comunicação (domain_key = 'communication')
  select array_agg(pb.id)
    into v_board_ids
  from public.project_boards pb
  where coalesce(pb.domain_key, '') = 'communication'
    and pb.is_active is true;

  if v_board_ids is null or array_length(v_board_ids, 1) = 0 then
    return jsonb_build_object(
      'backlog_count', 0,
      'overdue_count', 0,
      'total_publications', 0,
      'by_status', '[]'::jsonb,
      'by_format', '[]'::jsonb
    );
  end if;

  select
    count(*) filter (where bi.status in ('backlog','todo') or bi.status is null)::int,
    count(*) filter (where bi.due_date is not null and bi.due_date::date < current_date and coalesce(bi.status, '') not in ('done','review'))::int,
    count(*)::int
  into v_backlog, v_overdue, v_total
  from public.board_items bi
  where bi.board_id = any(v_board_ids);

  select coalesce(
    jsonb_object_agg(s.status, s.cnt),
    '{}'::jsonb
  )
  into v_by_status
  from (
    select coalesce(bi.status, 'unknown') as status, count(*)::int as cnt
    from public.board_items bi
    where bi.board_id = any(v_board_ids)
    group by coalesce(bi.status, 'unknown')
  ) s;

  -- Distribuição por formato: tags são string[] no board_items
  -- Extraímos tags comuns: vídeo, artigo, linkedin, post, etc.
  with items_tags as (
    select unnest(
      case when bi.tags is null or array_length(bi.tags, 1) is null or array_length(bi.tags, 1) = 0
        then array['outros']::text[] else bi.tags
      end
    ) as tag
    from public.board_items bi
    where bi.board_id = any(v_board_ids)
  ),
  normalized as (
    select
      case
        when lower(tag) in ('video','vídeo') then 'vídeo'
        when lower(tag) in ('artigo','article','artigos') then 'artigo'
        when lower(tag) in ('linkedin','linkedin post') then 'LinkedIn'
        when lower(tag) in ('post','posts') then 'post'
        when lower(tag) in ('newsletter') then 'newsletter'
        when lower(tag) in ('podcast') then 'podcast'
        when lower(tag) in ('infográfico','infographic') then 'infográfico'
        else coalesce(nullif(trim(tag), ''), 'outros')
      end as format
    from items_tags
  )
  select coalesce(
    jsonb_object_agg(n.format, n.cnt),
    '{}'::jsonb
  )
  into v_by_format
  from (
    select format, count(*)::int as cnt
    from normalized
    group by format
  ) n;

  -- Se não há tags, default "outros" = total
  if v_by_format is null or v_by_format = '{}'::jsonb then
    v_by_format := jsonb_build_object('outros', v_total);
  end if;

  v_result := jsonb_build_object(
    'backlog_count', coalesce(v_backlog, 0),
    'overdue_count', coalesce(v_overdue, 0),
    'total_publications', coalesce(v_total, 0),
    'by_status', coalesce(v_by_status, '{}'::jsonb),
    'by_format', coalesce(v_by_format, '{}'::jsonb)
  );

  return v_result;
end;
$$;

comment on function public.get_comms_dashboard_metrics() is
  'W85: Métricas do Dashboard de Comms - boards communication, status e formato.';

grant execute on function public.get_comms_dashboard_metrics() to authenticated;
