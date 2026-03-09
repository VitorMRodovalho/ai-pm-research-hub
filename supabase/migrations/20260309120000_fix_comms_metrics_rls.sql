-- ═══════════════════════════════════════════════════════════════════════════
-- FIX: Standardize comms_metrics and broadcast_log RLS to use
--      get_my_member_record() instead of has_min_tier() or direct members queries.
-- Date: 2026-03-09
--
-- While has_min_tier() was already fixed to use get_my_member_record()
-- internally, can_manage_comms_metrics() still has a fallback that queries
-- members directly. This migration standardizes everything.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ─── Rebuild can_manage_comms_metrics using get_my_member_record ───
create or replace function public.can_manage_comms_metrics()
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rec record;
begin
  select * into v_rec from public.get_my_member_record();
  if not found then return false; end if;

  return (
    v_rec.is_superadmin = true
    or v_rec.operational_role in ('manager', 'deputy_manager')
    or v_rec.designations @> ARRAY['comms_leader']
    or v_rec.designations @> ARRAY['comms_member']
  );
end;
$$;

-- ─── Recreate comms_metrics_daily policies using get_my_member_record ───
drop policy if exists comms_metrics_admin_read on public.comms_metrics_daily;
create policy comms_metrics_admin_read on public.comms_metrics_daily
  for select to authenticated
  using (
    (select is_superadmin from public.get_my_member_record()) = true
    or (select operational_role from public.get_my_member_record()) in ('manager', 'deputy_manager')
    or (select designations from public.get_my_member_record()) @> ARRAY['comms_leader']
    or (select designations from public.get_my_member_record()) @> ARRAY['comms_member']
  );

drop policy if exists comms_metrics_admin_insert on public.comms_metrics_daily;
create policy comms_metrics_admin_insert on public.comms_metrics_daily
  for insert to authenticated
  with check (public.can_manage_comms_metrics());

drop policy if exists comms_metrics_admin_update on public.comms_metrics_daily;
create policy comms_metrics_admin_update on public.comms_metrics_daily
  for update to authenticated
  using (public.can_manage_comms_metrics())
  with check (public.can_manage_comms_metrics());

drop policy if exists comms_metrics_admin_delete on public.comms_metrics_daily;
create policy comms_metrics_admin_delete on public.comms_metrics_daily
  for delete to authenticated
  using (public.can_manage_comms_metrics());

-- ─── Recreate comms_metrics_ingestion_log policies ───
drop policy if exists comms_ingestion_admin_read on public.comms_metrics_ingestion_log;
create policy comms_ingestion_admin_read on public.comms_metrics_ingestion_log
  for select to authenticated
  using (public.can_manage_comms_metrics());

drop policy if exists comms_ingestion_admin_insert on public.comms_metrics_ingestion_log;
create policy comms_ingestion_admin_insert on public.comms_metrics_ingestion_log
  for insert to authenticated
  with check (public.can_manage_comms_metrics());

drop policy if exists comms_ingestion_admin_update on public.comms_metrics_ingestion_log;
create policy comms_ingestion_admin_update on public.comms_metrics_ingestion_log
  for update to authenticated
  using (public.can_manage_comms_metrics())
  with check (public.can_manage_comms_metrics());

-- ─── Standardize broadcast_log admin policy ───
drop policy if exists "broadcast_log_read_admin" on public.broadcast_log;
create policy "broadcast_log_read_admin" on public.broadcast_log
  for select to authenticated
  using (
    (select is_superadmin from public.get_my_member_record()) = true
    or (select operational_role from public.get_my_member_record()) in ('manager', 'deputy_manager')
  );

-- Also fix broadcast_log tribe_leader policy to use helper
drop policy if exists "broadcast_log_read_tribe_leader" on public.broadcast_log;
create policy "broadcast_log_read_tribe_leader" on public.broadcast_log
  for select to authenticated
  using (
    tribe_id = (select g.tribe_id from public.get_my_member_record() g where g.operational_role = 'tribe_leader')
  );

commit;
