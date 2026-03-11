-- ============================================================================
-- Board lifecycle (archive/restore) + strict tribe/fact integrity
-- Date: 2026-03-14
-- ============================================================================

begin;

-- Canonical source->tribe mapping to prevent keyword-based drift.
create table if not exists public.board_source_tribe_map (
  source_board text primary key,
  tribe_id integer not null references public.tribes(id) on delete restrict,
  is_active boolean not null default true,
  notes text,
  updated_at timestamptz not null default now()
);

create or replace function public.board_source_tribe_map_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  new.source_board = lower(trim(new.source_board));
  return new;
end;
$$;

drop trigger if exists trg_board_source_tribe_map_updated on public.board_source_tribe_map;
create trigger trg_board_source_tribe_map_updated
before update on public.board_source_tribe_map
for each row execute function public.board_source_tribe_map_set_updated_at();

insert into public.board_source_tribe_map (source_board, tribe_id, is_active, notes)
values
  ('tribo3_priorizacao', 6, true, 'Legacy stream remapped to current tribe 6'),
  ('comunicacao_ciclo3', 8, true, 'Comms stream canonical lane'),
  ('midias_sociais', 8, true, 'Comms stream canonical lane'),
  ('social_media', 8, true, 'Comms stream canonical lane'),
  ('comms_c3', 8, true, 'Comms stream canonical lane')
on conflict (source_board)
do update set
  tribe_id = excluded.tribe_id,
  is_active = excluded.is_active,
  notes = excluded.notes,
  updated_at = now();

-- Enforce board tribe linkage for mapped source boards.
create or replace function public.enforce_board_item_source_tribe_integrity()
returns trigger
language plpgsql
as $$
declare
  v_expected_tribe integer;
  v_board_tribe integer;
begin
  if new.source_board is null or trim(new.source_board) = '' then
    return new;
  end if;

  new.source_board := lower(trim(new.source_board));

  select tribe_id
    into v_board_tribe
  from public.project_boards
  where id = new.board_id;

  if v_board_tribe is null then
    raise exception 'Board % must have tribe_id before linking source_board %', new.board_id, new.source_board;
  end if;

  select m.tribe_id
    into v_expected_tribe
  from public.board_source_tribe_map m
  where m.source_board = new.source_board
    and m.is_active is true
  limit 1;

  if v_expected_tribe is not null and v_expected_tribe is distinct from v_board_tribe then
    raise exception 'Source board % expects tribe %, but board % is linked to tribe %',
      new.source_board, v_expected_tribe, new.board_id, v_board_tribe;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_board_item_source_tribe_integrity on public.board_items;
create trigger trg_enforce_board_item_source_tribe_integrity
before insert or update of source_board, board_id
on public.board_items
for each row
execute function public.enforce_board_item_source_tribe_integrity();

-- Hardening: linked-source boards must always carry tribe_id.
update public.project_boards
set tribe_id = 8,
    updated_at = now()
where tribe_id is null
  and source in ('trello', 'notion');

alter table public.project_boards
  drop constraint if exists project_boards_linked_sources_require_tribe_chk;

alter table public.project_boards
  add constraint project_boards_linked_sources_require_tribe_chk
  check (
    source not in ('trello', 'notion') or tribe_id is not null
  );

-- Lifecycle audit trail for board/card recovery operations.
create table if not exists public.board_lifecycle_events (
  id bigserial primary key,
  board_id uuid references public.project_boards(id) on delete cascade,
  item_id uuid references public.board_items(id) on delete cascade,
  action text not null check (action in ('board_archived', 'board_restored', 'item_archived', 'item_restored')),
  previous_status text,
  new_status text,
  reason text,
  actor_member_id uuid references public.members(id) on delete set null,
  created_at timestamptz not null default now(),
  check (board_id is not null or item_id is not null)
);

create index if not exists idx_board_lifecycle_events_board_created
  on public.board_lifecycle_events(board_id, created_at desc);

create index if not exists idx_board_lifecycle_events_item_created
  on public.board_lifecycle_events(item_id, created_at desc);

alter table public.board_lifecycle_events enable row level security;

drop policy if exists board_lifecycle_events_read_mgmt on public.board_lifecycle_events;
create policy board_lifecycle_events_read_mgmt
on public.board_lifecycle_events
for select
to authenticated
using (
  exists (
    select 1
    from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
      or coalesce('tribe_leader' = any(r.designations), false)
  )
);

drop policy if exists board_lifecycle_events_write_mgmt on public.board_lifecycle_events;
create policy board_lifecycle_events_write_mgmt
on public.board_lifecycle_events
for insert
to authenticated
with check (
  exists (
    select 1
    from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
      or coalesce('tribe_leader' = any(r.designations), false)
  )
);

create or replace function public.admin_archive_project_board(
  p_board_id uuid,
  p_reason text default null,
  p_archive_items boolean default true
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_board record;
  v_archived_items integer := 0;
begin
  select * into v_caller from public.get_my_member_record();
  select * into v_board from public.project_boards where id = p_board_id;

  if v_board is null then
    raise exception 'Board not found: %', p_board_id;
  end if;

  if v_caller is null
    or not (
      v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
      or (v_caller.operational_role = 'tribe_leader' and v_caller.tribe_id = v_board.tribe_id)
    ) then
    raise exception 'Insufficient permissions';
  end if;

  update public.project_boards
  set is_active = false,
      updated_at = now()
  where id = p_board_id;

  if p_archive_items then
    update public.board_items
    set status = 'archived',
        updated_at = now()
    where board_id = p_board_id
      and status <> 'archived';
    get diagnostics v_archived_items = row_count;
  end if;

  insert into public.board_lifecycle_events (
    board_id, action, reason, actor_member_id
  ) values (
    p_board_id, 'board_archived', nullif(trim(coalesce(p_reason, '')), ''), v_caller.id
  );

  return jsonb_build_object(
    'success', true,
    'board_id', p_board_id,
    'archived_items', v_archived_items
  );
end;
$$;

grant execute on function public.admin_archive_project_board(uuid, text, boolean) to authenticated;

create or replace function public.admin_restore_project_board(
  p_board_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_board record;
begin
  select * into v_caller from public.get_my_member_record();
  select * into v_board from public.project_boards where id = p_board_id;

  if v_board is null then
    raise exception 'Board not found: %', p_board_id;
  end if;

  if v_caller is null
    or not (
      v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
      or (v_caller.operational_role = 'tribe_leader' and v_caller.tribe_id = v_board.tribe_id)
    ) then
    raise exception 'Insufficient permissions';
  end if;

  update public.project_boards
  set is_active = true,
      updated_at = now()
  where id = p_board_id;

  insert into public.board_lifecycle_events (
    board_id, action, reason, actor_member_id
  ) values (
    p_board_id, 'board_restored', nullif(trim(coalesce(p_reason, '')), ''), v_caller.id
  );

  return jsonb_build_object(
    'success', true,
    'board_id', p_board_id
  );
end;
$$;

grant execute on function public.admin_restore_project_board(uuid, text) to authenticated;

create or replace function public.admin_archive_board_item(
  p_item_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_item record;
  v_prev_status text;
begin
  select * into v_caller from public.get_my_member_record();
  select bi.*, pb.tribe_id as board_tribe_id
    into v_item
  from public.board_items bi
  join public.project_boards pb on pb.id = bi.board_id
  where bi.id = p_item_id;

  if v_item is null then
    raise exception 'Board item not found: %', p_item_id;
  end if;

  if v_caller is null
    or not (
      v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
      or (v_caller.operational_role = 'tribe_leader' and v_caller.tribe_id = v_item.board_tribe_id)
    ) then
    raise exception 'Insufficient permissions';
  end if;

  v_prev_status := v_item.status;

  update public.board_items
  set status = 'archived',
      updated_at = now()
  where id = p_item_id;

  insert into public.board_lifecycle_events (
    board_id, item_id, action, previous_status, new_status, reason, actor_member_id
  ) values (
    v_item.board_id, p_item_id, 'item_archived', v_prev_status, 'archived',
    nullif(trim(coalesce(p_reason, '')), ''), v_caller.id
  );

  return jsonb_build_object(
    'success', true,
    'item_id', p_item_id,
    'previous_status', v_prev_status,
    'new_status', 'archived'
  );
end;
$$;

grant execute on function public.admin_archive_board_item(uuid, text) to authenticated;

create or replace function public.admin_restore_board_item(
  p_item_id uuid,
  p_restore_status text default 'backlog',
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_item record;
  v_prev_status text;
begin
  if p_restore_status not in ('backlog', 'todo', 'in_progress', 'review', 'done') then
    raise exception 'Invalid restore status: %', p_restore_status;
  end if;

  select * into v_caller from public.get_my_member_record();
  select bi.*, pb.tribe_id as board_tribe_id
    into v_item
  from public.board_items bi
  join public.project_boards pb on pb.id = bi.board_id
  where bi.id = p_item_id;

  if v_item is null then
    raise exception 'Board item not found: %', p_item_id;
  end if;

  if v_caller is null
    or not (
      v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
      or (v_caller.operational_role = 'tribe_leader' and v_caller.tribe_id = v_item.board_tribe_id)
    ) then
    raise exception 'Insufficient permissions';
  end if;

  v_prev_status := v_item.status;

  update public.board_items
  set status = p_restore_status,
      updated_at = now()
  where id = p_item_id;

  insert into public.board_lifecycle_events (
    board_id, item_id, action, previous_status, new_status, reason, actor_member_id
  ) values (
    v_item.board_id, p_item_id, 'item_restored', v_prev_status, p_restore_status,
    nullif(trim(coalesce(p_reason, '')), ''), v_caller.id
  );

  return jsonb_build_object(
    'success', true,
    'item_id', p_item_id,
    'previous_status', v_prev_status,
    'new_status', p_restore_status
  );
end;
$$;

grant execute on function public.admin_restore_board_item(uuid, text, text) to authenticated;

commit;
