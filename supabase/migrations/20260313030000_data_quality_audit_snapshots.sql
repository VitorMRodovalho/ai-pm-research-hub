-- ═══════════════════════════════════════════════════════════════════════════
-- Persistent audit snapshot storage for historical governance tracking
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.data_quality_audit_snapshots (
  id uuid primary key default gen_random_uuid(),
  run_context text not null default 'manual',
  run_label text,
  source_batch_id uuid references public.ingestion_batches(id) on delete set null,
  audit_result jsonb not null,
  flag_count integer not null default 0,
  issue_count integer not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid references public.members(id) on delete set null
);

create index if not exists idx_data_quality_audit_snapshots_created_at
  on public.data_quality_audit_snapshots(created_at desc);

create index if not exists idx_data_quality_audit_snapshots_batch
  on public.data_quality_audit_snapshots(source_batch_id);

alter table public.data_quality_audit_snapshots enable row level security;

drop policy if exists data_quality_audit_snapshots_read_mgmt on public.data_quality_audit_snapshots;
create policy data_quality_audit_snapshots_read_mgmt
on public.data_quality_audit_snapshots
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

drop policy if exists data_quality_audit_snapshots_write_mgmt on public.data_quality_audit_snapshots;
create policy data_quality_audit_snapshots_write_mgmt
on public.data_quality_audit_snapshots
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

create or replace function public.admin_capture_data_quality_snapshot(
  p_run_context text default 'manual',
  p_run_label text default null,
  p_source_batch_id uuid default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_audit jsonb;
  v_flags jsonb;
  v_flag_count integer := 0;
  v_issue_count integer := 0;
  v_snapshot_id uuid;
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

  select public.admin_data_quality_audit() into v_audit;
  v_flags := coalesce(v_audit -> 'flags', '{}'::jsonb);

  select count(*) into v_flag_count
  from jsonb_each(v_flags);

  select count(*) into v_issue_count
  from jsonb_each(v_flags) e
  where coalesce((e.value)::text, 'false') = 'true';

  insert into public.data_quality_audit_snapshots (
    run_context,
    run_label,
    source_batch_id,
    audit_result,
    flag_count,
    issue_count,
    created_by
  ) values (
    coalesce(nullif(trim(p_run_context), ''), 'manual'),
    nullif(trim(coalesce(p_run_label, '')), ''),
    p_source_batch_id,
    v_audit,
    v_flag_count,
    v_issue_count,
    v_caller.id
  )
  returning id into v_snapshot_id;

  return jsonb_build_object(
    'snapshot_id', v_snapshot_id,
    'run_context', coalesce(nullif(trim(p_run_context), ''), 'manual'),
    'flag_count', v_flag_count,
    'issue_count', v_issue_count
  );
end;
$$;

grant execute on function public.admin_capture_data_quality_snapshot(text, text, uuid) to authenticated;

commit;
