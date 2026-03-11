-- ═══════════════════════════════════════════════════════════════════════════
-- Dual-control rollback audit trails
-- Date: 2026-03-14
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.rollback_audit_events (
  id bigserial primary key,
  plan_id uuid not null references public.ingestion_rollback_plans(id) on delete cascade,
  event_type text not null check (event_type in ('planned', 'approved_stage_1', 'approved_stage_2', 'executed', 'cancelled')),
  actor_id uuid references public.members(id) on delete set null,
  reason text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_rollback_audit_events_plan_created
  on public.rollback_audit_events(plan_id, created_at desc);

alter table public.rollback_audit_events enable row level security;

drop policy if exists rollback_audit_events_read_mgmt on public.rollback_audit_events;
create policy rollback_audit_events_read_mgmt
on public.rollback_audit_events
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

drop policy if exists rollback_audit_events_write_mgmt on public.rollback_audit_events;
create policy rollback_audit_events_write_mgmt
on public.rollback_audit_events
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

create or replace function public.admin_append_rollback_audit_event(
  p_plan_id uuid,
  p_event_type text,
  p_reason text default null,
  p_details jsonb default '{}'::jsonb
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
      auth.role() = 'service_role'
      or v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
    ) then
    raise exception 'Project management access required';
  end if;

  if p_event_type not in ('planned', 'approved_stage_1', 'approved_stage_2', 'executed', 'cancelled') then
    raise exception 'Invalid rollback audit event type: %', p_event_type;
  end if;

  insert into public.rollback_audit_events (plan_id, event_type, actor_id, reason, details)
  values (
    p_plan_id,
    p_event_type,
    v_caller.id,
    nullif(trim(coalesce(p_reason, '')), ''),
    coalesce(p_details, '{}'::jsonb)
  );

  return jsonb_build_object('success', true, 'plan_id', p_plan_id, 'event_type', p_event_type);
end;
$$;

grant execute on function public.admin_append_rollback_audit_event(uuid, text, text, jsonb) to authenticated;

commit;
