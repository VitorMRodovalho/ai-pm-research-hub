-- ============================================================================
-- Sprint W43.2 data follow-through: member data sanity patch
-- Date: 2026-03-14
-- ============================================================================

begin;

-- Ensure null/blank names do not break UI fallbacks.
update public.members
set name = 'Membro sem nome'
where trim(coalesce(name, '')) = '';

-- Ensure role-designation reads can always treat this as an array.
update public.members
set designations = '{}'::text[]
where designations is null;

-- Normalize phone storage to digits-only (or null when empty).
update public.members
set phone = nullif(regexp_replace(coalesce(phone, ''), '\D', '', 'g'), '')
where phone is not null;

commit;
