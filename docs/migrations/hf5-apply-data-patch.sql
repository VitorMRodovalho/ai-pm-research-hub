-- HF5 Apply - Data Patch Follow Through (idempotent)
-- Scope:
-- 1) Sarah LinkedIn restoration (only when blank)
-- 2) Align members role/designations with active member_cycle_history snapshot
-- 3) Enforce deputy_manager <-> co_gp consistency
--
-- Safe to run multiple times.

begin;

-- 1) Sarah LinkedIn restoration (only if empty)
-- Uses an existing non-empty value from another matching Sarah record if available.
with source_linkedin as (
  select m.linkedin_url
  from public.members m
  where
    (lower(m.email) = 'sarah.famr@gmail.com' or lower(m.name) like '%sarah%')
    and nullif(trim(coalesce(m.linkedin_url, '')), '') is not null
  order by m.updated_at desc nulls last
  limit 1
)
update public.members target
set
  linkedin_url = src.linkedin_url,
  updated_at = now()
from source_linkedin src
where
  (lower(target.email) = 'sarah.famr@gmail.com' or lower(target.name) like '%sarah%')
  and nullif(trim(coalesce(target.linkedin_url, '')), '') is null;

-- 2) Align with active cycle history (source of truth for current cycle role state)
with active_hist as (
  select distinct on (h.member_id)
    h.member_id,
    coalesce(h.operational_role, 'guest') as hist_operational_role,
    coalesce(h.designations, '{}'::text[]) as hist_designations
  from public.member_cycle_history h
  where h.is_active = true
  order by h.member_id, h.cycle_code desc nulls last
)
update public.members m
set
  operational_role = ah.hist_operational_role,
  designations = ah.hist_designations,
  updated_at = now()
from active_hist ah
where
  m.id = ah.member_id
  and (
    coalesce(m.operational_role, 'guest') <> ah.hist_operational_role
    or coalesce(m.designations, '{}'::text[]) <> ah.hist_designations
  );

-- 3a) deputy_manager must include co_gp
update public.members m
set
  designations = array(
    select distinct d
    from unnest(coalesce(m.designations, '{}'::text[]) || array['co_gp']) as d
  ),
  updated_at = now()
where
  m.current_cycle_active = true
  and m.operational_role = 'deputy_manager'
  and not ('co_gp' = any(coalesce(m.designations, '{}'::text[])));

-- 3b) manager should not include co_gp
update public.members m
set
  designations = array_remove(coalesce(m.designations, '{}'::text[]), 'co_gp'),
  updated_at = now()
where
  m.current_cycle_active = true
  and m.operational_role = 'manager'
  and ('co_gp' = any(coalesce(m.designations, '{}'::text[])));

commit;
