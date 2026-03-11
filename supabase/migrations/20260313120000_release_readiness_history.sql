-- ═══════════════════════════════════════════════════════════════════════════
-- Release readiness decision history timeline
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.release_readiness_history (
  id uuid primary key default gen_random_uuid(),
  mode text not null check (mode in ('strict', 'advisory')),
  ready boolean not null,
  reasons jsonb not null default '[]'::jsonb,
  thresholds jsonb not null default '{}'::jsonb,
  open_alerts jsonb not null default '{}'::jsonb,
  snapshot jsonb,
  context_label text,
  created_at timestamptz not null default now(),
  created_by uuid references public.members(id) on delete set null
);

create index if not exists idx_release_readiness_history_created
  on public.release_readiness_history(created_at desc);

alter table public.release_readiness_history enable row level security;

drop policy if exists release_readiness_history_read_mgmt on public.release_readiness_history;
create policy release_readiness_history_read_mgmt
on public.release_readiness_history
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

drop policy if exists release_readiness_history_write_mgmt on public.release_readiness_history;
create policy release_readiness_history_write_mgmt
on public.release_readiness_history
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

create or replace function public.admin_record_release_readiness_decision(
  p_context_label text default null,
  p_mode text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_gate jsonb;
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

  v_gate := public.admin_release_readiness_gate(null, null, p_mode);

  insert into public.release_readiness_history (
    mode,
    ready,
    reasons,
    thresholds,
    open_alerts,
    snapshot,
    context_label,
    created_by
  ) values (
    coalesce(v_gate ->> 'mode', 'strict'),
    coalesce((v_gate ->> 'ready')::boolean, false),
    coalesce(v_gate -> 'reasons', '[]'::jsonb),
    coalesce(v_gate -> 'thresholds', '{}'::jsonb),
    coalesce(v_gate -> 'open_alerts', '{}'::jsonb),
    v_gate -> 'snapshot',
    nullif(trim(coalesce(p_context_label, '')), ''),
    v_caller.id
  )
  returning id into v_id;

  return jsonb_build_object(
    'id', v_id,
    'ready', coalesce((v_gate ->> 'ready')::boolean, false),
    'mode', coalesce(v_gate ->> 'mode', 'strict'),
    'reasons', coalesce(v_gate -> 'reasons', '[]'::jsonb)
  );
end;
$$;

grant execute on function public.admin_record_release_readiness_decision(text, text) to authenticated;

commit;
