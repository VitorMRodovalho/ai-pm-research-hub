-- ═══════════════════════════════════════════════════════════════════════════
-- Ingestion provenance signature contracts
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.ingestion_provenance_signatures (
  id bigserial primary key,
  batch_id uuid not null references public.ingestion_batches(id) on delete cascade,
  file_path text not null,
  file_hash text not null,
  source_kind text not null,
  signature text not null,
  signed_at timestamptz not null default now(),
  signed_by uuid references public.members(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  unique (batch_id, file_path, file_hash)
);

create index if not exists idx_ingestion_provenance_signatures_batch
  on public.ingestion_provenance_signatures(batch_id, signed_at desc);

alter table public.ingestion_provenance_signatures enable row level security;

drop policy if exists ingestion_provenance_signatures_read_mgmt on public.ingestion_provenance_signatures;
create policy ingestion_provenance_signatures_read_mgmt
on public.ingestion_provenance_signatures
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

drop policy if exists ingestion_provenance_signatures_write_mgmt on public.ingestion_provenance_signatures;
create policy ingestion_provenance_signatures_write_mgmt
on public.ingestion_provenance_signatures
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

create or replace function public.admin_sign_ingestion_file_provenance(
  p_batch_id uuid,
  p_file_path text,
  p_file_hash text,
  p_source_kind text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_signature text;
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

  if coalesce(trim(p_file_path), '') = '' or coalesce(trim(p_file_hash), '') = '' then
    raise exception 'file_path and file_hash are required';
  end if;

  v_signature := encode(
    digest(
      coalesce(p_batch_id::text, '') || '|' || trim(p_file_path) || '|' || trim(p_file_hash) || '|' || coalesce(trim(p_source_kind), 'unknown'),
      'sha256'
    ),
    'hex'
  );

  insert into public.ingestion_provenance_signatures (
    batch_id, file_path, file_hash, source_kind, signature, signed_by, metadata
  ) values (
    p_batch_id, trim(p_file_path), trim(p_file_hash), coalesce(trim(p_source_kind), 'unknown'), v_signature, v_caller.id, coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (batch_id, file_path, file_hash)
  do update set
    signature = excluded.signature,
    signed_by = v_caller.id,
    metadata = excluded.metadata,
    signed_at = now();

  return jsonb_build_object(
    'success', true,
    'batch_id', p_batch_id,
    'file_path', trim(p_file_path),
    'signature', v_signature
  );
end;
$$;

grant execute on function public.admin_sign_ingestion_file_provenance(uuid, text, text, text, jsonb) to authenticated;

commit;
