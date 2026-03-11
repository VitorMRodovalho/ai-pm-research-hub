-- ═══════════════════════════════════════════════════════════════════════════
-- Backend suggestion contract for Notion-to-board mapping
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.admin_suggest_notion_board_mappings(
  p_limit integer default 100,
  p_only_unmapped boolean default true
)
returns table(
  notion_item_id bigint,
  suggested_board_id uuid,
  suggested_board_name text,
  confidence_score numeric,
  reason text
)
language sql
security definer
as $$
  with caller as (
    select * from public.get_my_member_record()
  ),
  allowed as (
    select 1
    from caller c
    where
      c.is_superadmin is true
      or c.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(c.designations), false)
      or auth.role() = 'service_role'
  ),
  staged as (
    select
      n.id as notion_item_id,
      n.title,
      coalesce(n.tribe_hint, '') as tribe_hint
    from public.notion_import_staging n
    where (not p_only_unmapped) or n.mapped_board_id is null
  ),
  candidates as (
    select
      s.notion_item_id,
      b.id as suggested_board_id,
      b.board_name as suggested_board_name,
      case
        when s.tribe_hint <> '' and strpos(lower(b.board_name), lower(s.tribe_hint)) > 0 and lower(b.board_name) = lower(s.title) then 0.95
        when s.tribe_hint <> '' and strpos(lower(b.board_name), lower(s.tribe_hint)) > 0 and strpos(lower(s.title), lower(b.board_name)) > 0 then 0.88
        when lower(b.board_name) = lower(s.title) then 0.82
        when strpos(lower(s.title), lower(b.board_name)) > 0 then 0.70
        else 0.50
      end::numeric(5,2) as confidence_score,
      case
        when s.tribe_hint <> '' and strpos(lower(b.board_name), lower(s.tribe_hint)) > 0 and lower(b.board_name) = lower(s.title) then 'exact_title_and_tribe_hint_match'
        when s.tribe_hint <> '' and strpos(lower(b.board_name), lower(s.tribe_hint)) > 0 and strpos(lower(s.title), lower(b.board_name)) > 0 then 'tribe_hint_with_title_overlap'
        when lower(b.board_name) = lower(s.title) then 'exact_title_match'
        when strpos(lower(s.title), lower(b.board_name)) > 0 then 'title_overlap'
        else 'fallback_candidate'
      end as reason,
      row_number() over (
        partition by s.notion_item_id
        order by
          case
            when s.tribe_hint <> '' and strpos(lower(b.board_name), lower(s.tribe_hint)) > 0 and lower(b.board_name) = lower(s.title) then 1
            when s.tribe_hint <> '' and strpos(lower(b.board_name), lower(s.tribe_hint)) > 0 and strpos(lower(s.title), lower(b.board_name)) > 0 then 2
            when lower(b.board_name) = lower(s.title) then 3
            when strpos(lower(s.title), lower(b.board_name)) > 0 then 4
            else 5
          end,
          b.id
      ) as rn
    from staged s
    join public.project_boards b on (
      lower(b.board_name) = lower(s.title)
      or strpos(lower(s.title), lower(b.board_name)) > 0
      or (s.tribe_hint <> '' and strpos(lower(b.board_name), lower(s.tribe_hint)) > 0)
    )
  )
  select
    c.notion_item_id,
    c.suggested_board_id,
    c.suggested_board_name,
    c.confidence_score,
    c.reason
  from candidates c
  where
    exists (select 1 from allowed)
    and c.rn = 1
  order by c.confidence_score desc, c.notion_item_id
  limit greatest(coalesce(p_limit, 100), 1);
$$;

grant execute on function public.admin_suggest_notion_board_mappings(integer, boolean) to authenticated;

commit;
