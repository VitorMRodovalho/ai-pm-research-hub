-- ACL Tier Parity v1 (Frontend <-> Backend)
-- Goal: align DB authorization semantics with frontend tier matrix.
--
-- Tier model:
-- visitor < member < observer < leader < admin < superadmin
--
-- Route/action parity targets:
-- - admin_panel          => observer+
-- - admin_analytics      => admin+
-- - admin_member_edit    => superadmin
-- - admin_manage_actions => admin+
--
-- IMPORTANT:
-- 1) Execute first in staging.
-- 2) Adapt table/policy names to your live schema if they differ.
-- 3) Keep SECURITY DEFINER RPCs with explicit tier checks inside function body.

begin;

-- 1) Helper: resolve tier rank from current auth user
create or replace function public.current_member_tier_rank()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  m record;
begin
  select id, is_superadmin, operational_role, coalesce(designations, '{}'::text[]) as designations
    into m
  from public.members
  where auth_id = auth.uid()
  limit 1;

  if m.id is null then
    return 0; -- visitor
  end if;

  if m.is_superadmin then
    return 5;
  end if;

  if m.operational_role in ('manager', 'deputy_manager') or ('co_gp' = any(m.designations)) then
    return 4; -- admin
  end if;

  if m.operational_role = 'tribe_leader' then
    return 3; -- leader
  end if;

  if ('sponsor' = any(m.designations)) or ('curator' = any(m.designations)) or ('chapter_liaison' = any(m.designations)) then
    return 2; -- observer
  end if;

  if m.operational_role in ('researcher', 'facilitator', 'communicator') or cardinality(m.designations) > 0 then
    return 1; -- member
  end if;

  return 0; -- visitor
end;
$$;

revoke all on function public.current_member_tier_rank() from public;
grant execute on function public.current_member_tier_rank() to authenticated;

-- 2) Helper: minimum tier check
create or replace function public.has_min_tier(required_rank int)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_member_tier_rank() >= required_rank;
$$;

revoke all on function public.has_min_tier(int) from public;
grant execute on function public.has_min_tier(int) to authenticated;

-- 3) Example policy parity (adapt names if needed)
-- announcements (admin_manage_actions => admin rank 4)
drop policy if exists announcements_admin_write on public.announcements;
create policy announcements_admin_write
on public.announcements
for all
to authenticated
using (public.has_min_tier(4))
with check (public.has_min_tier(4));

-- member_cycle_history writes (admin_member_edit => superadmin rank 5)
drop policy if exists mch_superadmin_write on public.member_cycle_history;
create policy mch_superadmin_write
on public.member_cycle_history
for all
to authenticated
using (public.has_min_tier(5))
with check (public.has_min_tier(5));

-- tribes settings writes (leader+ rank 3)
drop policy if exists tribes_leader_write on public.tribes;
create policy tribes_leader_write
on public.tribes
for update
to authenticated
using (public.has_min_tier(3))
with check (public.has_min_tier(3));

-- Optional: analytics governance table (admin_analytics => admin rank 4)
-- If you create a config table for embedded analytics links:
-- drop policy if exists analytics_config_admin_read on public.analytics_config;
-- create policy analytics_config_admin_read
-- on public.analytics_config
-- for select
-- to authenticated
-- using (public.has_min_tier(4));

commit;

