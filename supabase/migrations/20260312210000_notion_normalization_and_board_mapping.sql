-- ═══════════════════════════════════════════════════════════════════════════
-- Notion normalization staging and board mapping contracts
-- Date: 2026-03-12
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.notion_import_staging (
  id bigserial primary key,
  batch_id uuid references public.ingestion_batches(id) on delete set null,
  source_file text not null,
  source_page text,
  external_item_id text,
  title text not null,
  description text,
  status_raw text,
  assignee_name text,
  tags text[] not null default '{}',
  due_date date,
  tribe_hint text,
  chapter_hint text,
  confidence_score numeric(5,2) not null default 0.00,
  normalized jsonb not null default '{}'::jsonb,
  mapped_board_id uuid references public.project_boards(id) on delete set null,
  mapped_item_id uuid references public.board_items(id) on delete set null,
  mapped_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_notion_import_staging_batch
  on public.notion_import_staging(batch_id);
create index if not exists idx_notion_import_staging_board
  on public.notion_import_staging(mapped_board_id);

create unique index if not exists idx_notion_import_staging_external_unique
  on public.notion_import_staging(source_file, coalesce(external_item_id, ''), title);

create or replace function public.notion_import_staging_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_notion_import_staging_set_updated_at on public.notion_import_staging;
create trigger trg_notion_import_staging_set_updated_at
before update on public.notion_import_staging
for each row execute function public.notion_import_staging_set_updated_at();

alter table public.notion_import_staging enable row level security;

drop policy if exists notion_import_staging_read_mgmt on public.notion_import_staging;
create policy notion_import_staging_read_mgmt
on public.notion_import_staging
for select to authenticated
using (
  exists (
    select 1 from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
      or coalesce('chapter_liaison' = any(r.designations), false)
  )
);

drop policy if exists notion_import_staging_write_mgmt on public.notion_import_staging;
create policy notion_import_staging_write_mgmt
on public.notion_import_staging
for all to authenticated
using (
  exists (
    select 1 from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
  )
)
with check (
  exists (
    select 1 from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
  )
);

create or replace function public.admin_map_notion_item_to_board(
  p_staging_id bigint,
  p_board_id uuid,
  p_status text default 'backlog',
  p_position integer default 0,
  p_apply_insert boolean default false
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_stage record;
  v_item_id uuid;
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

  if p_status not in ('backlog', 'todo', 'in_progress', 'review', 'done', 'archived') then
    raise exception 'Invalid board status: %', p_status;
  end if;

  select * into v_stage
  from public.notion_import_staging
  where id = p_staging_id;

  if v_stage is null then
    raise exception 'Notion staging item not found: %', p_staging_id;
  end if;

  if p_apply_insert is true then
    insert into public.board_items (
      board_id,
      title,
      description,
      status,
      tags,
      due_date,
      position,
      source_card_id,
      source_board,
      attachments,
      checklist
    ) values (
      p_board_id,
      v_stage.title,
      v_stage.description,
      p_status,
      v_stage.tags,
      v_stage.due_date,
      coalesce(p_position, 0),
      v_stage.external_item_id,
      'notion',
      '[]'::jsonb,
      '[]'::jsonb
    )
    returning id into v_item_id;
  end if;

  update public.notion_import_staging
  set mapped_board_id = p_board_id,
      mapped_item_id = coalesce(v_item_id, mapped_item_id),
      mapped_at = now()
  where id = p_staging_id;

  return jsonb_build_object(
    'success', true,
    'staging_id', p_staging_id,
    'board_id', p_board_id,
    'mapped_item_id', v_item_id
  );
end;
$$;

grant execute on function public.admin_map_notion_item_to_board(bigint, uuid, text, integer, boolean) to authenticated;

commit;
