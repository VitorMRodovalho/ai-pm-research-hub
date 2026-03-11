-- ═══════════════════════════════════════════════════════════════════════════
-- Ingestion run ledger and idempotency key contracts
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.ingestion_run_ledger (
  id uuid primary key default gen_random_uuid(),
  run_key text not null unique,
  source text not null,
  mode text not null check (mode in ('dry_run', 'apply')),
  manifest_hash text not null,
  status text not null default 'running' check (status in ('running', 'completed', 'failed', 'skipped')),
  batch_id uuid references public.ingestion_batches(id) on delete set null,
  run_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.members(id) on delete set null
);

create index if not exists idx_ingestion_run_ledger_source_mode_created
  on public.ingestion_run_ledger(source, mode, created_at desc);

create or replace function public.ingestion_run_ledger_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_ingestion_run_ledger_set_updated_at on public.ingestion_run_ledger;
create trigger trg_ingestion_run_ledger_set_updated_at
before update on public.ingestion_run_ledger
for each row execute function public.ingestion_run_ledger_set_updated_at();

alter table public.ingestion_run_ledger enable row level security;

drop policy if exists ingestion_run_ledger_read_mgmt on public.ingestion_run_ledger;
create policy ingestion_run_ledger_read_mgmt
on public.ingestion_run_ledger
for select to authenticated
using (
  exists (
    select 1
    from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
      or coalesce('chapter_liaison' = any(r.designations), false)
  )
);

drop policy if exists ingestion_run_ledger_write_mgmt on public.ingestion_run_ledger;
create policy ingestion_run_ledger_write_mgmt
on public.ingestion_run_ledger
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

create or replace function public.admin_register_ingestion_run(
  p_run_key text,
  p_source text,
  p_mode text,
  p_manifest_hash text,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_existing record;
  v_new_id uuid;
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

  if coalesce(trim(p_run_key), '') = '' then
    raise exception 'run_key is required';
  end if;
  if p_mode not in ('dry_run', 'apply') then
    raise exception 'Invalid mode: %', p_mode;
  end if;
  if coalesce(trim(p_manifest_hash), '') = '' then
    raise exception 'manifest_hash is required';
  end if;

  select * into v_existing
  from public.ingestion_run_ledger
  where run_key = trim(p_run_key)
  limit 1;

  if v_existing is not null then
    return jsonb_build_object(
      'proceed', false,
      'already_exists', true,
      'run_id', v_existing.id,
      'status', v_existing.status,
      'batch_id', v_existing.batch_id
    );
  end if;

  insert into public.ingestion_run_ledger(
    run_key, source, mode, manifest_hash, status, run_notes, created_by
  ) values (
    trim(p_run_key),
    coalesce(nullif(trim(p_source), ''), 'mixed'),
    p_mode,
    trim(p_manifest_hash),
    'running',
    nullif(trim(coalesce(p_notes, '')), ''),
    v_caller.id
  )
  returning id into v_new_id;

  return jsonb_build_object(
    'proceed', true,
    'already_exists', false,
    'run_id', v_new_id
  );
end;
$$;

grant execute on function public.admin_register_ingestion_run(text, text, text, text, text) to authenticated;

create or replace function public.admin_complete_ingestion_run(
  p_run_id uuid,
  p_status text,
  p_batch_id uuid default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_updated integer := 0;
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

  if p_status not in ('completed', 'failed', 'skipped') then
    raise exception 'Invalid completion status: %', p_status;
  end if;

  update public.ingestion_run_ledger
  set
    status = p_status,
    batch_id = coalesce(p_batch_id, batch_id),
    run_notes = coalesce(nullif(trim(coalesce(p_notes, '')), ''), run_notes)
  where id = p_run_id;
  get diagnostics v_updated = row_count;

  return jsonb_build_object(
    'success', v_updated > 0,
    'run_id', p_run_id,
    'status', p_status
  );
end;
$$;

grant execute on function public.admin_complete_ingestion_run(uuid, text, uuid, text) to authenticated;

commit;
