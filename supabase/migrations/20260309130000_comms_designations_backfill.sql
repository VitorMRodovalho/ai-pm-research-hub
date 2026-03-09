-- ═══════════════════════════════════════════════════════════════════════════
-- S-COM1: Backfill comms_leader / comms_member designations
-- Date: 2026-03-09
--
-- Migrates from legacy 'comms_team' to granular 'comms_leader'/'comms_member'.
-- Applies to both members (Cycle 3) and member_cycle_history (Cycle 2).
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ─── Step 1: Mayanna Duarte → comms_leader (Cycle 3 - members) ───
update public.members
set designations = array_remove(coalesce(designations, '{}'::text[]), 'comms_team')
where lower(name) like '%mayanna%duarte%'
  and coalesce(designations, '{}') @> ARRAY['comms_team'];

update public.members
set designations = array_append(coalesce(designations, '{}'::text[]), 'comms_leader')
where lower(name) like '%mayanna%duarte%'
  and not (coalesce(designations, '{}') @> ARRAY['comms_leader']);

-- ─── Step 2: Leticia Clemente → comms_member ───
update public.members
set designations = array_remove(coalesce(designations, '{}'::text[]), 'comms_team')
where lower(name) like '%leticia%clemente%'
  and coalesce(designations, '{}') @> ARRAY['comms_team'];

update public.members
set designations = array_append(coalesce(designations, '{}'::text[]), 'comms_member')
where lower(name) like '%leticia%clemente%'
  and not (coalesce(designations, '{}') @> ARRAY['comms_member']);

-- ─── Step 3: Andressa Martins → comms_member ───
update public.members
set designations = array_remove(coalesce(designations, '{}'::text[]), 'comms_team')
where lower(name) like '%andressa%martins%'
  and coalesce(designations, '{}') @> ARRAY['comms_team'];

update public.members
set designations = array_append(coalesce(designations, '{}'::text[]), 'comms_member')
where lower(name) like '%andressa%martins%'
  and not (coalesce(designations, '{}') @> ARRAY['comms_member']);

-- ─── Step 4: Cleanup any remaining comms_team in members ───
update public.members
set designations = array_remove(designations, 'comms_team')
where designations @> ARRAY['comms_team'];

-- ─── Step 5: Backfill member_cycle_history via member_id lookup ───
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'member_cycle_history'
      and column_name = 'designations'
  ) then
    -- Update using member_id FK joined to members by name
    update public.member_cycle_history mch
    set designations = array_remove(coalesce(mch.designations, '{}'::text[]), 'comms_team')
    from public.members m
    where mch.member_id = m.id
      and lower(m.name) like '%mayanna%duarte%'
      and coalesce(mch.designations, '{}') @> ARRAY['comms_team'];

    update public.member_cycle_history mch
    set designations = array_append(coalesce(mch.designations, '{}'::text[]), 'comms_leader')
    from public.members m
    where mch.member_id = m.id
      and lower(m.name) like '%mayanna%duarte%'
      and not (coalesce(mch.designations, '{}') @> ARRAY['comms_leader']);

    update public.member_cycle_history mch
    set designations = array_remove(coalesce(mch.designations, '{}'::text[]), 'comms_team')
    from public.members m
    where mch.member_id = m.id
      and lower(m.name) like '%leticia%clemente%'
      and coalesce(mch.designations, '{}') @> ARRAY['comms_team'];

    update public.member_cycle_history mch
    set designations = array_append(coalesce(mch.designations, '{}'::text[]), 'comms_member')
    from public.members m
    where mch.member_id = m.id
      and lower(m.name) like '%leticia%clemente%'
      and not (coalesce(mch.designations, '{}') @> ARRAY['comms_member']);

    update public.member_cycle_history mch
    set designations = array_remove(coalesce(mch.designations, '{}'::text[]), 'comms_team')
    from public.members m
    where mch.member_id = m.id
      and lower(m.name) like '%andressa%martins%'
      and coalesce(mch.designations, '{}') @> ARRAY['comms_team'];

    update public.member_cycle_history mch
    set designations = array_append(coalesce(mch.designations, '{}'::text[]), 'comms_member')
    from public.members m
    where mch.member_id = m.id
      and lower(m.name) like '%andressa%martins%'
      and not (coalesce(mch.designations, '{}') @> ARRAY['comms_member']);

    -- Cleanup remaining comms_team in history
    update public.member_cycle_history
    set designations = array_remove(designations, 'comms_team')
    where designations @> ARRAY['comms_team'];
  end if;
end
$$;

commit;
