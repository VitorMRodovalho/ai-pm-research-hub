-- ACL Tier Parity Audit
-- Run after applying `acl-tier-parity-v1.sql` in staging/production.

-- 1) Ensure helper functions exist
select
  proname,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and proname in ('current_member_tier_rank', 'has_min_tier')
order by proname;

-- 2) Check target policies exist
select
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd
from pg_policies
where schemaname = 'public'
  and (
    (tablename = 'announcements' and policyname = 'announcements_admin_write') or
    (tablename = 'member_cycle_history' and policyname = 'mch_superadmin_write') or
    (tablename = 'tribes' and policyname = 'tribes_leader_write')
  )
order by tablename, policyname;

-- 3) Quick sanity: sample members and expected rank
-- Adjust limit/filter for your environment.
select
  m.id,
  m.name,
  m.is_superadmin,
  m.operational_role,
  m.designations,
  case
    when m.is_superadmin then 5
    when m.operational_role in ('manager','deputy_manager') or ('co_gp' = any(coalesce(m.designations, '{}'::text[]))) then 4
    when m.operational_role = 'tribe_leader' then 3
    when ('sponsor' = any(coalesce(m.designations, '{}'::text[])))
      or ('curator' = any(coalesce(m.designations, '{}'::text[])))
      or ('chapter_liaison' = any(coalesce(m.designations, '{}'::text[]))) then 2
    when m.operational_role in ('researcher','facilitator','communicator')
      or cardinality(coalesce(m.designations, '{}'::text[])) > 0 then 1
    else 0
  end as expected_rank
from public.members m
order by expected_rank desc, m.name
limit 30;

-- 4) Optional: run in each tier account/session to validate booleans
-- select public.current_member_tier_rank() as my_rank;
-- select public.has_min_tier(2) as can_admin_panel;
-- select public.has_min_tier(4) as can_admin_analytics;
-- select public.has_min_tier(5) as can_member_history_write;

