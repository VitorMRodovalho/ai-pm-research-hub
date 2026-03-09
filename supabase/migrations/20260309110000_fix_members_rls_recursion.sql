-- ═══════════════════════════════════════════════════════════════════════════
-- FIX: Members RLS infinite recursion
-- Date: 2026-03-09
-- 
-- PROBLEM: The members RLS policies used has_min_tier() and subqueries
-- on the members table itself. When Postgres evaluates a SELECT policy
-- on members, it needs to run the subquery which triggers the same
-- policies again → infinite recursion → 500 error.
--
-- This also cascaded to ALL other tables whose policies use has_min_tier()
-- because that function internally queries members.
--
-- SOLUTION: Create a SECURITY DEFINER helper that reads members WITHOUT
-- going through RLS (it runs as the function owner = postgres).
-- All members policies now use this helper instead of direct subqueries.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ─── Helper: get caller's member record bypassing RLS ───
-- SECURITY DEFINER runs as postgres, so it ignores all RLS policies.
-- This breaks the recursion chain.
create or replace function public.get_my_member_record()
returns table (
  id uuid,
  tribe_id integer,
  operational_role text,
  is_superadmin boolean,
  designations text[]
)
language sql
security definer
stable
as $$
  select m.id, m.tribe_id, m.operational_role, m.is_superadmin, m.designations
  from public.members m
  where m.auth_id = auth.uid()
  limit 1;
$$;

-- ─── Rebuild has_min_tier to use the helper (no direct members access) ───
create or replace function public.has_min_tier(required_rank integer)
returns boolean
language plpgsql
security definer
stable
as $$
declare
  v_rec record;
  v_rank integer := 0;
begin
  select * into v_rec from public.get_my_member_record();
  if not found then return false; end if;

  -- Tier mapping: visitor=0, member=1, observer=2, leader=3, admin=4, superadmin=5
  if v_rec.is_superadmin = true then
    v_rank := 5;
  elsif v_rec.operational_role in ('manager', 'deputy_manager') then
    v_rank := 4;
  elsif v_rec.operational_role = 'tribe_leader' then
    v_rank := 3;
  elsif v_rec.operational_role in ('researcher', 'facilitator', 'communicator') then
    v_rank := 1;
  elsif v_rec.designations is not null and array_length(v_rec.designations, 1) > 0 then
    -- Has designations like sponsor, co_gp → observer level
    v_rank := 2;
  else
    v_rank := 0;
  end if;

  return v_rank >= required_rank;
end;
$$;

-- ─── Drop and recreate ALL members policies (no recursion) ───

-- SELECT policies
drop policy if exists "members_select_own" on public.members;
create policy "members_select_own" on public.members
  for select to authenticated
  using (auth_id = auth.uid());

drop policy if exists "members_select_admin" on public.members;
create policy "members_select_admin" on public.members
  for select to authenticated
  using (
    (select is_superadmin from public.get_my_member_record()) = true
    or (select operational_role from public.get_my_member_record()) in ('manager', 'deputy_manager')
  );

drop policy if exists "members_select_tribe_leader" on public.members;
create policy "members_select_tribe_leader" on public.members
  for select to authenticated
  using (
    tribe_id is not null
    and tribe_id = (select g.tribe_id from public.get_my_member_record() g where g.operational_role = 'tribe_leader')
  );

-- UPDATE policies
drop policy if exists "members_update_own" on public.members;
create policy "members_update_own" on public.members
  for update to authenticated
  using (auth_id = auth.uid())
  with check (auth_id = auth.uid());

drop policy if exists "members_update_admin" on public.members;
create policy "members_update_admin" on public.members
  for update to authenticated
  using (
    (select is_superadmin from public.get_my_member_record()) = true
    or (select operational_role from public.get_my_member_record()) in ('manager', 'deputy_manager')
  )
  with check (
    (select is_superadmin from public.get_my_member_record()) = true
    or (select operational_role from public.get_my_member_record()) in ('manager', 'deputy_manager')
  );

-- INSERT policy
drop policy if exists "members_insert_admin" on public.members;
create policy "members_insert_admin" on public.members
  for insert to authenticated
  with check (
    (select is_superadmin from public.get_my_member_record()) = true
    or (select operational_role from public.get_my_member_record()) in ('manager', 'deputy_manager')
  );

-- DELETE policy
drop policy if exists "members_delete_superadmin" on public.members;
create policy "members_delete_superadmin" on public.members
  for delete to authenticated
  using (
    (select is_superadmin from public.get_my_member_record()) = true
  );

commit;
