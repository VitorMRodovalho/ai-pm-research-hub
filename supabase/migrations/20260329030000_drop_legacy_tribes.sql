-- G13: Drop legacy_tribes table (code reference removed, data in cycle_tribe_dim)
ALTER TABLE z_archive.legacy_member_links DROP CONSTRAINT IF EXISTS legacy_member_links_legacy_tribe_id_fkey;
ALTER TABLE z_archive.legacy_tribe_board_links DROP CONSTRAINT IF EXISTS legacy_tribe_board_links_legacy_tribe_id_fkey;
DROP TABLE IF EXISTS public.legacy_tribes CASCADE;
DROP FUNCTION IF EXISTS public.legacy_tribes_set_updated_at() CASCADE;
