-- ═══════════════════════════════════════════════════════════════════════════
-- Ingestion apply locking to prevent concurrent mutating runs
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.ingestion_apply_locks (
  source text primary key,
  holder text not null,
  acquired_at timestamptz not null default now(),
  expires_at timestamptz not null,
  metadata jsonb not null default '{}'::jsonb
);

alter table public.ingestion_apply_locks enable row level security;

drop policy if exists ingestion_apply_locks_read_mgmt on public.ingestion_apply_locks;
create policy ingestion_apply_locks_read_mgmt
on public.ingestion_apply_locks
for select to authenticated
using (
  exists (
    select 1
    from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
  )
);

drop policy if exists ingestion_apply_locks_write_mgmt on public.ingestion_apply_locks;
create policy ingestion_apply_locks_write_mgmt
on public.ingestion_apply_locks
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

create or replace function public.admin_acquire_ingestion_apply_lock(
  p_source text,
  p_holder text,
  p_ttl_minutes integer default 30,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_now timestamptz := now();
  v_expire timestamptz;
  v_existing record;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      auth.role() = 'service_role'
      or v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
    ) then
    raise exception 'Project management access required';
  end if;

  v_expire := v_now + make_interval(mins => greatest(coalesce(p_ttl_minutes, 30), 1));

  select * into v_existing
  from public.ingestion_apply_locks
  where source = p_source
  limit 1;

  if v_existing is not null and v_existing.expires_at > v_now then
    return jsonb_build_object(
      'acquired', false,
      'source', p_source,
      'holder', v_existing.holder,
      'expires_at', v_existing.expires_at
    );
  end if;

  insert into public.ingestion_apply_locks(source, holder, acquired_at, expires_at, metadata)
  values (p_source, p_holder, v_now, v_expire, coalesce(p_metadata, '{}'::jsonb))
  on conflict (source)
  do update set
    holder = excluded.holder,
    acquired_at = excluded.acquired_at,
    expires_at = excluded.expires_at,
    metadata = excluded.metadata;

  return jsonb_build_object(
    'acquired', true,
    'source', p_source,
    'holder', p_holder,
    'expires_at', v_expire
  );
end;
$$;

grant execute on function public.admin_acquire_ingestion_apply_lock(text, text, integer, jsonb) to authenticated;

create or replace function public.admin_release_ingestion_apply_lock(
  p_source text,
  p_holder text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_deleted integer := 0;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      auth.role() = 'service_role'
      or v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
    ) then
    raise exception 'Project management access required';
  end if;

  delete from public.ingestion_apply_locks
  where source = p_source
    and holder = p_holder;
  get diagnostics v_deleted = row_count;

  return jsonb_build_object(
    'released', v_deleted > 0,
    'source', p_source,
    'holder', p_holder
  );
end;
$$;

grant execute on function public.admin_release_ingestion_apply_lock(text, text) to authenticated;

commit;
