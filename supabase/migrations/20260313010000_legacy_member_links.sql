-- ═══════════════════════════════════════════════════════════════════════════
-- Legacy member links for cycle-aware continuity traceability
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.legacy_member_links (
  id bigserial primary key,
  legacy_tribe_id bigint not null references public.legacy_tribes(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  cycle_code text not null,
  role_snapshot text,
  chapter_snapshot text,
  link_type text not null default 'historical_member'
    check (link_type in ('historical_member', 'historical_leader', 'continued_member')),
  confidence_score numeric(5,2) not null default 1.00,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.members(id) on delete set null
);

create unique index if not exists idx_legacy_member_links_unique
  on public.legacy_member_links(legacy_tribe_id, member_id, cycle_code, link_type);

create index if not exists idx_legacy_member_links_member
  on public.legacy_member_links(member_id, cycle_code);

create or replace function public.legacy_member_links_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_legacy_member_links_set_updated_at on public.legacy_member_links;
create trigger trg_legacy_member_links_set_updated_at
before update on public.legacy_member_links
for each row execute function public.legacy_member_links_set_updated_at();

alter table public.legacy_member_links enable row level security;

drop policy if exists legacy_member_links_read_auth on public.legacy_member_links;
create policy legacy_member_links_read_auth
on public.legacy_member_links
for select to authenticated
using (true);

drop policy if exists legacy_member_links_write_mgmt on public.legacy_member_links;
create policy legacy_member_links_write_mgmt
on public.legacy_member_links
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

create or replace function public.admin_link_member_to_legacy_tribe(
  p_legacy_tribe_id bigint,
  p_member_id uuid,
  p_cycle_code text,
  p_role_snapshot text default null,
  p_chapter_snapshot text default null,
  p_link_type text default 'historical_member',
  p_confidence_score numeric default 1.00,
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

  if p_link_type not in ('historical_member', 'historical_leader', 'continued_member') then
    raise exception 'Invalid link_type: %', p_link_type;
  end if;

  if coalesce(trim(p_cycle_code), '') = '' then
    raise exception 'cycle_code is required';
  end if;

  insert into public.legacy_member_links (
    legacy_tribe_id,
    member_id,
    cycle_code,
    role_snapshot,
    chapter_snapshot,
    link_type,
    confidence_score,
    metadata,
    created_by
  ) values (
    p_legacy_tribe_id,
    p_member_id,
    trim(p_cycle_code),
    nullif(trim(coalesce(p_role_snapshot, '')), ''),
    nullif(trim(coalesce(p_chapter_snapshot, '')), ''),
    p_link_type,
    greatest(0, least(coalesce(p_confidence_score, 1.00), 1.00)),
    coalesce(p_metadata, '{}'::jsonb),
    v_caller.id
  )
  on conflict (legacy_tribe_id, member_id, cycle_code, link_type)
  do update set
    role_snapshot = excluded.role_snapshot,
    chapter_snapshot = excluded.chapter_snapshot,
    confidence_score = excluded.confidence_score,
    metadata = excluded.metadata;

  return jsonb_build_object(
    'success', true,
    'legacy_tribe_id', p_legacy_tribe_id,
    'member_id', p_member_id,
    'cycle_code', trim(p_cycle_code),
    'link_type', p_link_type
  );
end;
$$;

grant execute on function public.admin_link_member_to_legacy_tribe(
  bigint, uuid, text, text, text, text, numeric, jsonb
) to authenticated;

commit;
