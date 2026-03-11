-- ═══════════════════════════════════════════════════════════════════════════
-- Tribe continuity overrides (explicit renumbering mappings)
-- Date: 2026-03-12
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.tribe_continuity_overrides (
  id bigserial primary key,
  continuity_key text not null unique,
  legacy_cycle_code text not null,
  legacy_tribe_id integer references public.tribes(id) on delete set null,
  current_cycle_code text not null,
  current_tribe_id integer references public.tribes(id) on delete set null,
  leader_name text,
  continuity_type text not null default 'renumbered_continuity'
    check (continuity_type in ('renumbered_continuity', 'same_stream_new_id', 'same_stream_same_id')),
  is_active boolean not null default true,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.members(id) on delete set null
);

create index if not exists idx_continuity_overrides_current
  on public.tribe_continuity_overrides(current_cycle_code, current_tribe_id);

create or replace function public.tribe_continuity_overrides_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_tribe_continuity_overrides_set_updated_at on public.tribe_continuity_overrides;
create trigger trg_tribe_continuity_overrides_set_updated_at
before update on public.tribe_continuity_overrides
for each row execute function public.tribe_continuity_overrides_set_updated_at();

alter table public.tribe_continuity_overrides enable row level security;

drop policy if exists tribe_continuity_overrides_read_auth on public.tribe_continuity_overrides;
create policy tribe_continuity_overrides_read_auth
on public.tribe_continuity_overrides
for select to authenticated
using (true);

drop policy if exists tribe_continuity_overrides_write_mgmt on public.tribe_continuity_overrides;
create policy tribe_continuity_overrides_write_mgmt
on public.tribe_continuity_overrides
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

create or replace function public.admin_upsert_tribe_continuity_override(
  p_continuity_key text,
  p_legacy_cycle_code text,
  p_legacy_tribe_id integer,
  p_current_cycle_code text,
  p_current_tribe_id integer,
  p_leader_name text default null,
  p_continuity_type text default 'renumbered_continuity',
  p_is_active boolean default true,
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

  if coalesce(trim(p_continuity_key), '') = '' then
    raise exception 'continuity_key is required';
  end if;
  if coalesce(trim(p_legacy_cycle_code), '') = '' then
    raise exception 'legacy_cycle_code is required';
  end if;
  if coalesce(trim(p_current_cycle_code), '') = '' then
    raise exception 'current_cycle_code is required';
  end if;
  if p_continuity_type not in ('renumbered_continuity', 'same_stream_new_id', 'same_stream_same_id') then
    raise exception 'Invalid continuity_type: %', p_continuity_type;
  end if;

  insert into public.tribe_continuity_overrides (
    continuity_key,
    legacy_cycle_code,
    legacy_tribe_id,
    current_cycle_code,
    current_tribe_id,
    leader_name,
    continuity_type,
    is_active,
    notes,
    metadata,
    updated_by
  ) values (
    trim(p_continuity_key),
    trim(p_legacy_cycle_code),
    p_legacy_tribe_id,
    trim(p_current_cycle_code),
    p_current_tribe_id,
    nullif(trim(coalesce(p_leader_name, '')), ''),
    p_continuity_type,
    coalesce(p_is_active, true),
    nullif(trim(coalesce(p_notes, '')), ''),
    coalesce(p_metadata, '{}'::jsonb),
    v_caller.id
  )
  on conflict (continuity_key)
  do update set
    legacy_cycle_code = excluded.legacy_cycle_code,
    legacy_tribe_id = excluded.legacy_tribe_id,
    current_cycle_code = excluded.current_cycle_code,
    current_tribe_id = excluded.current_tribe_id,
    leader_name = excluded.leader_name,
    continuity_type = excluded.continuity_type,
    is_active = excluded.is_active,
    notes = excluded.notes,
    metadata = excluded.metadata,
    updated_by = v_caller.id;

  return jsonb_build_object(
    'success', true,
    'continuity_key', trim(p_continuity_key),
    'continuity_type', p_continuity_type
  );
end;
$$;

grant execute on function public.admin_upsert_tribe_continuity_override(
  text, text, integer, text, integer, text, text, boolean, text, jsonb
) to authenticated;

commit;
