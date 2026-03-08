-- HF5 Audit - Data Patch Follow Through
-- Run this before and after applying `hf5-apply-data-patch.sql`.

-- 1) Targeted member snapshot (Sarah + Roberto)
select
  id,
  name,
  email,
  linkedin_url,
  operational_role,
  designations,
  current_cycle_active
from public.members
where
  lower(email) in ('sarah.famr@gmail.com', 'boblmacedo@gmail.com')
  or lower(name) like '%sarah%'
  or lower(name) like '%roberto%'
order by name;

-- 1b) Sarah still missing LinkedIn after patch? (should return 0 rows)
select
  id,
  name,
  email,
  linkedin_url
from public.members
where
  (lower(email) = 'sarah.famr@gmail.com' or lower(name) like '%sarah%')
  and nullif(trim(coalesce(linkedin_url, '')), '') is null;

-- 2) Role/designation mismatches between members and active cycle history
with active_hist as (
  select distinct on (h.member_id)
    h.member_id,
    h.operational_role as hist_operational_role,
    coalesce(h.designations, '{}'::text[]) as hist_designations,
    h.cycle_code
  from public.member_cycle_history h
  where h.is_active = true
  order by h.member_id, h.cycle_code desc nulls last
)
select
  m.id as member_id,
  m.name,
  m.operational_role as member_operational_role,
  ah.hist_operational_role,
  m.designations as member_designations,
  ah.hist_designations,
  ah.cycle_code
from public.members m
join active_hist ah on ah.member_id = m.id
where
  coalesce(m.operational_role, 'guest') <> coalesce(ah.hist_operational_role, 'guest')
  or coalesce(m.designations, '{}'::text[]) <> coalesce(ah.hist_designations, '{}'::text[])
order by m.name;

-- 3) Deputy hierarchy consistency checks
-- 3a) deputy_manager must include co_gp designation
select
  m.id,
  m.name,
  m.operational_role,
  m.designations
from public.members m
where m.current_cycle_active = true
  and m.operational_role = 'deputy_manager'
  and not ('co_gp' = any(coalesce(m.designations, '{}'::text[])))
order by m.name;

-- 3b) manager should not carry co_gp designation
select
  m.id,
  m.name,
  m.operational_role,
  m.designations
from public.members m
where m.current_cycle_active = true
  and m.operational_role = 'manager'
  and ('co_gp' = any(coalesce(m.designations, '{}'::text[])))
order by m.name;
