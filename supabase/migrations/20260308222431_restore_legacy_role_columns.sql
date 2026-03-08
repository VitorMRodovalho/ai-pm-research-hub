-- ═══════════════════════════════════════════════════════════════
-- Migration: restore legacy role/roles columns on members
-- Why: role and roles were dropped but RPCs (admin_force_tribe_selection,
--   admin_update_member, views gamification_leaderboard, public_members, etc.)
--   still reference them → "column role does not exist" crashes.
-- Fix: re-add role/roles as regular columns with a trigger that auto-computes
--   them from operational_role + designations. This fixes ALL existing RPCs/views
--   without needing to rewrite each one.
-- Safe: idempotent, uses IF NOT EXISTS / OR REPLACE.
-- ═══════════════════════════════════════════════════════════════

-- 1. Re-add columns if they were dropped
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'members' AND column_name = 'role'
  ) THEN
    ALTER TABLE public.members ADD COLUMN role text DEFAULT 'guest';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'members' AND column_name = 'roles'
  ) THEN
    ALTER TABLE public.members ADD COLUMN roles text[] DEFAULT ARRAY['guest']::text[];
  END IF;
END
$$;

-- 2. Backfill from operational_role + designations
UPDATE public.members SET
  role = COALESCE(
    compute_legacy_role(
      COALESCE(operational_role, 'guest'),
      COALESCE(designations, ARRAY[]::text[])
    ),
    'guest'
  ),
  roles = COALESCE(
    compute_legacy_roles(
      COALESCE(operational_role, 'guest'),
      COALESCE(designations, ARRAY[]::text[])
    ),
    ARRAY['guest']::text[]
  )
WHERE true;

-- 3. Trigger to keep role/roles in sync on every INSERT or UPDATE
CREATE OR REPLACE FUNCTION public.sync_legacy_role_columns()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.role := COALESCE(
    compute_legacy_role(
      COALESCE(NEW.operational_role, 'guest'),
      COALESCE(NEW.designations, ARRAY[]::text[])
    ),
    'guest'
  );
  NEW.roles := COALESCE(
    compute_legacy_roles(
      COALESCE(NEW.operational_role, 'guest'),
      COALESCE(NEW.designations, ARRAY[]::text[])
    ),
    ARRAY['guest']::text[]
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_legacy_role ON public.members;
CREATE TRIGGER trg_sync_legacy_role
  BEFORE INSERT OR UPDATE ON public.members
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_legacy_role_columns();
