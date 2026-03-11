-- ═══════════════════════════════════════════════════════════════════════════
-- Unified ingestion pipeline audit tables and RPCs
-- Date: 2026-03-12
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.ingestion_batches (
  id uuid primary key default gen_random_uuid(),
  source text not null check (source in ('trello', 'notion', 'miro', 'calendar', 'volunteer_csv', 'whatsapp', 'mixed')),
  mode text not null default 'dry_run' check (mode in ('dry_run', 'apply')),
  status text not null default 'running' check (status in ('running', 'completed', 'failed', 'cancelled')),
  initiated_by uuid references public.members(id) on delete set null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  summary jsonb not null default '{}'::jsonb,
  notes text
);

create table if not exists public.ingestion_batch_files (
  id bigserial primary key,
  batch_id uuid not null references public.ingestion_batches(id) on delete cascade,
  source_kind text not null,
  file_path text not null,
  file_hash text,
  file_size_bytes bigint,
  status text not null default 'queued' check (status in ('queued', 'processed', 'skipped', 'failed')),
  result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_ingestion_batch_files_unique
  on public.ingestion_batch_files(batch_id, file_path);

create index if not exists idx_ingestion_batches_started_at
  on public.ingestion_batches(started_at desc);

create or replace function public.ingestion_batch_files_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_ingestion_batch_files_set_updated_at on public.ingestion_batch_files;
create trigger trg_ingestion_batch_files_set_updated_at
before update on public.ingestion_batch_files
for each row execute function public.ingestion_batch_files_set_updated_at();

alter table public.ingestion_batches enable row level security;
alter table public.ingestion_batch_files enable row level security;

drop policy if exists ingestion_batches_read_mgmt on public.ingestion_batches;
create policy ingestion_batches_read_mgmt
on public.ingestion_batches
for select to authenticated
using (
  exists (
    select 1 from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
  )
);

drop policy if exists ingestion_batches_write_mgmt on public.ingestion_batches;
create policy ingestion_batches_write_mgmt
on public.ingestion_batches
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

drop policy if exists ingestion_batch_files_read_mgmt on public.ingestion_batch_files;
create policy ingestion_batch_files_read_mgmt
on public.ingestion_batch_files
for select to authenticated
using (
  exists (
    select 1 from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
  )
);

drop policy if exists ingestion_batch_files_write_mgmt on public.ingestion_batch_files;
create policy ingestion_batch_files_write_mgmt
on public.ingestion_batch_files
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

create or replace function public.admin_start_ingestion_batch(
  p_source text,
  p_mode text default 'dry_run',
  p_notes text default null
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_batch_id uuid;
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

  insert into public.ingestion_batches (
    source, mode, status, initiated_by, notes
  ) values (
    p_source,
    p_mode,
    'running',
    v_caller.id,
    nullif(trim(coalesce(p_notes, '')), '')
  )
  returning id into v_batch_id;

  return v_batch_id;
end;
$$;

grant execute on function public.admin_start_ingestion_batch(text, text, text) to authenticated;

create or replace function public.admin_finalize_ingestion_batch(
  p_batch_id uuid,
  p_status text default 'completed',
  p_summary jsonb default '{}'::jsonb
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

  update public.ingestion_batches
  set status = p_status,
      summary = coalesce(p_summary, '{}'::jsonb),
      finished_at = now()
  where id = p_batch_id;

  if not found then
    raise exception 'Ingestion batch not found: %', p_batch_id;
  end if;

  return jsonb_build_object(
    'success', true,
    'batch_id', p_batch_id,
    'status', p_status
  );
end;
$$;

grant execute on function public.admin_finalize_ingestion_batch(uuid, text, jsonb) to authenticated;

commit;
