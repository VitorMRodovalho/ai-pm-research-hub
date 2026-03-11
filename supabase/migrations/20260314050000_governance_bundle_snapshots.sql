-- ═══════════════════════════════════════════════════════════════════════════
-- Governance bundle snapshot persistence contracts
-- Date: 2026-03-14
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.governance_bundle_snapshots (
  id uuid primary key default gen_random_uuid(),
  window_days integer not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  created_by uuid references public.members(id) on delete set null,
  context_label text
);

create index if not exists idx_governance_bundle_snapshots_created
  on public.governance_bundle_snapshots(created_at desc);

alter table public.governance_bundle_snapshots enable row level security;

drop policy if exists governance_bundle_snapshots_read_mgmt on public.governance_bundle_snapshots;
create policy governance_bundle_snapshots_read_mgmt
on public.governance_bundle_snapshots
for select to authenticated
using (
  exists (
    select 1 from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
      or coalesce('chapter_liaison' = any(r.designations), false)
      or coalesce('sponsor' = any(r.designations), false)
  )
);

drop policy if exists governance_bundle_snapshots_write_mgmt on public.governance_bundle_snapshots;
create policy governance_bundle_snapshots_write_mgmt
on public.governance_bundle_snapshots
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

create or replace function public.admin_capture_governance_bundle_snapshot(
  p_window_days integer default 30,
  p_context_label text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_payload jsonb;
  v_id uuid;
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

  v_payload := public.exec_governance_export_bundle(greatest(coalesce(p_window_days, 30), 1));

  insert into public.governance_bundle_snapshots (window_days, payload, created_by, context_label)
  values (greatest(coalesce(p_window_days, 30), 1), v_payload, v_caller.id, nullif(trim(coalesce(p_context_label, '')), ''))
  returning id into v_id;

  return jsonb_build_object('snapshot_id', v_id, 'window_days', greatest(coalesce(p_window_days, 30), 1));
end;
$$;

grant execute on function public.admin_capture_governance_bundle_snapshot(integer, text) to authenticated;

commit;
