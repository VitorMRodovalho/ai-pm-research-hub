-- ═══════════════════════════════════════════════════════════════════════════
-- Legacy tribe materialization (cycles 1 and 2)
-- Date: 2026-03-12
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.legacy_tribes (
  id bigserial primary key,
  legacy_key text not null unique,
  tribe_id integer references public.tribes(id) on delete set null,
  cycle_code text not null,
  cycle_label text,
  display_name text not null,
  quadrant integer,
  chapter text,
  status text not null default 'inactive' check (status in ('active', 'inactive', 'archived')),
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.members(id) on delete set null,
  updated_by uuid references public.members(id) on delete set null
);

create table if not exists public.legacy_tribe_board_links (
  id bigserial primary key,
  legacy_tribe_id bigint not null references public.legacy_tribes(id) on delete cascade,
  board_id uuid not null references public.project_boards(id) on delete cascade,
  relation_type text not null default 'legacy_snapshot' check (relation_type in (
    'legacy_snapshot',
    'continued_in_current',
    'renumbered_continuity'
  )),
  confidence_score numeric(5,2) not null default 1.00,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_legacy_board_link_unique
  on public.legacy_tribe_board_links(legacy_tribe_id, board_id, relation_type);

create index if not exists idx_legacy_tribes_cycle
  on public.legacy_tribes(cycle_code);

create or replace function public.legacy_tribes_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_legacy_tribes_set_updated_at on public.legacy_tribes;
create trigger trg_legacy_tribes_set_updated_at
before update on public.legacy_tribes
for each row execute function public.legacy_tribes_set_updated_at();

create or replace function public.legacy_tribe_board_links_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_legacy_tribe_board_links_set_updated_at on public.legacy_tribe_board_links;
create trigger trg_legacy_tribe_board_links_set_updated_at
before update on public.legacy_tribe_board_links
for each row execute function public.legacy_tribe_board_links_set_updated_at();

alter table public.legacy_tribes enable row level security;
alter table public.legacy_tribe_board_links enable row level security;

drop policy if exists legacy_tribes_read_auth on public.legacy_tribes;
create policy legacy_tribes_read_auth on public.legacy_tribes
for select to authenticated
using (true);

drop policy if exists legacy_tribes_write_mgmt on public.legacy_tribes;
create policy legacy_tribes_write_mgmt on public.legacy_tribes
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

drop policy if exists legacy_links_read_auth on public.legacy_tribe_board_links;
create policy legacy_links_read_auth on public.legacy_tribe_board_links
for select to authenticated
using (true);

drop policy if exists legacy_links_write_mgmt on public.legacy_tribe_board_links;
create policy legacy_links_write_mgmt on public.legacy_tribe_board_links
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

create or replace function public.admin_upsert_legacy_tribe(
  p_id bigint default null,
  p_legacy_key text default null,
  p_tribe_id integer default null,
  p_cycle_code text default null,
  p_cycle_label text default null,
  p_display_name text default null,
  p_quadrant integer default null,
  p_chapter text default null,
  p_status text default 'inactive',
  p_notes text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_id bigint;
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

  if coalesce(trim(p_legacy_key), '') = '' then
    raise exception 'legacy_key is required';
  end if;
  if coalesce(trim(p_cycle_code), '') = '' then
    raise exception 'cycle_code is required';
  end if;
  if coalesce(trim(p_display_name), '') = '' then
    raise exception 'display_name is required';
  end if;

  if p_status not in ('active', 'inactive', 'archived') then
    raise exception 'Invalid status: %', p_status;
  end if;

  if p_id is null then
    insert into public.legacy_tribes (
      legacy_key, tribe_id, cycle_code, cycle_label, display_name, quadrant, chapter,
      status, notes, metadata, created_by, updated_by
    ) values (
      trim(p_legacy_key), p_tribe_id, trim(p_cycle_code), nullif(trim(coalesce(p_cycle_label, '')), ''),
      trim(p_display_name), p_quadrant, nullif(trim(coalesce(p_chapter, '')), ''),
      p_status, nullif(trim(coalesce(p_notes, '')), ''), coalesce(p_metadata, '{}'::jsonb),
      v_caller.id, v_caller.id
    )
    on conflict (legacy_key)
    do update set
      tribe_id = excluded.tribe_id,
      cycle_code = excluded.cycle_code,
      cycle_label = excluded.cycle_label,
      display_name = excluded.display_name,
      quadrant = excluded.quadrant,
      chapter = excluded.chapter,
      status = excluded.status,
      notes = excluded.notes,
      metadata = excluded.metadata,
      updated_by = v_caller.id
    returning id into v_id;
  else
    update public.legacy_tribes
    set legacy_key = trim(p_legacy_key),
        tribe_id = p_tribe_id,
        cycle_code = trim(p_cycle_code),
        cycle_label = nullif(trim(coalesce(p_cycle_label, '')), ''),
        display_name = trim(p_display_name),
        quadrant = p_quadrant,
        chapter = nullif(trim(coalesce(p_chapter, '')), ''),
        status = p_status,
        notes = nullif(trim(coalesce(p_notes, '')), ''),
        metadata = coalesce(p_metadata, '{}'::jsonb),
        updated_by = v_caller.id
    where id = p_id
    returning id into v_id;
  end if;

  if v_id is null then
    raise exception 'Legacy tribe upsert failed';
  end if;

  return jsonb_build_object(
    'success', true,
    'legacy_tribe_id', v_id,
    'legacy_key', trim(p_legacy_key)
  );
end;
$$;

grant execute on function public.admin_upsert_legacy_tribe(
  bigint, text, integer, text, text, text, integer, text, text, text, jsonb
) to authenticated;

create or replace function public.admin_link_board_to_legacy_tribe(
  p_legacy_tribe_id bigint,
  p_board_id uuid,
  p_relation_type text default 'legacy_snapshot',
  p_confidence_score numeric default 1.00,
  p_notes text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
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

  if p_relation_type not in ('legacy_snapshot', 'continued_in_current', 'renumbered_continuity') then
    raise exception 'Invalid relation type: %', p_relation_type;
  end if;

  insert into public.legacy_tribe_board_links (
    legacy_tribe_id,
    board_id,
    relation_type,
    confidence_score,
    notes,
    metadata
  ) values (
    p_legacy_tribe_id,
    p_board_id,
    p_relation_type,
    greatest(0, least(coalesce(p_confidence_score, 1.00), 1.00)),
    nullif(trim(coalesce(p_notes, '')), ''),
    coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (legacy_tribe_id, board_id, relation_type)
  do update set
    confidence_score = excluded.confidence_score,
    notes = excluded.notes,
    metadata = excluded.metadata;

  return jsonb_build_object(
    'success', true,
    'legacy_tribe_id', p_legacy_tribe_id,
    'board_id', p_board_id,
    'relation_type', p_relation_type
  );
end;
$$;

grant execute on function public.admin_link_board_to_legacy_tribe(bigint, uuid, text, numeric, text, jsonb) to authenticated;

commit;
