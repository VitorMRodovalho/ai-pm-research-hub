-- ═══════════════════════════════════════════════════════════════════════════
-- Tribe lineage and legacy continuity links
-- Date: 2026-03-12
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.tribe_lineage (
  id bigserial primary key,
  legacy_tribe_id integer not null references public.tribes(id) on delete cascade,
  current_tribe_id integer not null references public.tribes(id) on delete cascade,
  relation_type text not null check (relation_type in (
    'continues_as',
    'renumbered_to',
    'merged_into',
    'split_from',
    'legacy_of'
  )),
  cycle_scope text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.members(id) on delete set null,
  updated_by uuid references public.members(id) on delete set null
);

create unique index if not exists idx_tribe_lineage_unique_pair
  on public.tribe_lineage (legacy_tribe_id, current_tribe_id, relation_type, coalesce(cycle_scope, ''));

create index if not exists idx_tribe_lineage_current on public.tribe_lineage (current_tribe_id);
create index if not exists idx_tribe_lineage_legacy on public.tribe_lineage (legacy_tribe_id);

create or replace function public.tribe_lineage_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_tribe_lineage_set_updated_at on public.tribe_lineage;
create trigger trg_tribe_lineage_set_updated_at
before update on public.tribe_lineage
for each row execute function public.tribe_lineage_set_updated_at();

alter table public.tribe_lineage enable row level security;

drop policy if exists tribe_lineage_select_auth on public.tribe_lineage;
create policy tribe_lineage_select_auth on public.tribe_lineage
  for select to authenticated
  using (true);

drop policy if exists tribe_lineage_write_mgmt on public.tribe_lineage;
create policy tribe_lineage_write_mgmt on public.tribe_lineage
  for all to authenticated
  using (
    exists (
      select 1
      from public.get_my_member_record() r
      where
        r.is_superadmin is true
        or r.operational_role in ('manager', 'deputy_manager')
        or coalesce('co_gp' = any(r.designations), false)
    )
  )
  with check (
    exists (
      select 1
      from public.get_my_member_record() r
      where
        r.is_superadmin is true
        or r.operational_role in ('manager', 'deputy_manager')
        or coalesce('co_gp' = any(r.designations), false)
    )
  );

create or replace function public.admin_upsert_tribe_lineage(
  p_id bigint default null,
  p_legacy_tribe_id integer default null,
  p_current_tribe_id integer default null,
  p_relation_type text default 'continues_as',
  p_cycle_scope text default null,
  p_notes text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_is_active boolean default true
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

  if p_legacy_tribe_id is null or p_current_tribe_id is null then
    raise exception 'Legacy and current tribe IDs are required';
  end if;

  if p_relation_type not in ('continues_as', 'renumbered_to', 'merged_into', 'split_from', 'legacy_of') then
    raise exception 'Invalid relation type: %', p_relation_type;
  end if;

  if p_id is null then
    insert into public.tribe_lineage (
      legacy_tribe_id,
      current_tribe_id,
      relation_type,
      cycle_scope,
      notes,
      metadata,
      is_active,
      created_by,
      updated_by
    ) values (
      p_legacy_tribe_id,
      p_current_tribe_id,
      p_relation_type,
      nullif(trim(coalesce(p_cycle_scope, '')), ''),
      nullif(trim(coalesce(p_notes, '')), ''),
      coalesce(p_metadata, '{}'::jsonb),
      coalesce(p_is_active, true),
      v_caller.id,
      v_caller.id
    )
    returning id into v_id;
  else
    update public.tribe_lineage
    set legacy_tribe_id = p_legacy_tribe_id,
        current_tribe_id = p_current_tribe_id,
        relation_type = p_relation_type,
        cycle_scope = nullif(trim(coalesce(p_cycle_scope, '')), ''),
        notes = nullif(trim(coalesce(p_notes, '')), ''),
        metadata = coalesce(p_metadata, '{}'::jsonb),
        is_active = coalesce(p_is_active, true),
        updated_by = v_caller.id
    where id = p_id
    returning id into v_id;

    if v_id is null then
      raise exception 'Lineage entry not found: %', p_id;
    end if;
  end if;

  return jsonb_build_object(
    'success', true,
    'id', v_id,
    'legacy_tribe_id', p_legacy_tribe_id,
    'current_tribe_id', p_current_tribe_id,
    'relation_type', p_relation_type,
    'is_active', coalesce(p_is_active, true)
  );
end;
$$;

grant execute on function public.admin_upsert_tribe_lineage(
  bigint,
  integer,
  integer,
  text,
  text,
  text,
  jsonb,
  boolean
) to authenticated;

create or replace function public.admin_list_tribe_lineage(
  p_include_inactive boolean default false
)
returns table (
  id bigint,
  legacy_tribe_id integer,
  legacy_tribe_name text,
  current_tribe_id integer,
  current_tribe_name text,
  relation_type text,
  cycle_scope text,
  notes text,
  metadata jsonb,
  is_active boolean,
  updated_at timestamptz
)
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
      or v_caller.operational_role in ('manager', 'deputy_manager', 'tribe_leader')
      or coalesce('co_gp' = any(v_caller.designations), false)
    ) then
    raise exception 'Management access required';
  end if;

  return query
  select
    tl.id,
    tl.legacy_tribe_id,
    lt.name as legacy_tribe_name,
    tl.current_tribe_id,
    ct.name as current_tribe_name,
    tl.relation_type,
    tl.cycle_scope,
    tl.notes,
    tl.metadata,
    tl.is_active,
    tl.updated_at
  from public.tribe_lineage tl
  join public.tribes lt on lt.id = tl.legacy_tribe_id
  join public.tribes ct on ct.id = tl.current_tribe_id
  where p_include_inactive or tl.is_active is true
  order by tl.updated_at desc, tl.id desc;
end;
$$;

grant execute on function public.admin_list_tribe_lineage(boolean) to authenticated;

commit;
