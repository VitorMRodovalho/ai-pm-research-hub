-- Migration: drop dead-schema verified_at column from member_emails
-- Issue: #205 GAP-205.C (P162 #118) — YAGNI cleanup
-- ADR: 0095 (amended 2026-05-21)
--
-- Context:
--   The verified_at column was added in 20260802000008 as speculative future use
--   for an email-verification flow. At p214 close (2026-05-21) the column had:
--     - 0 write paths anywhere in migrations / RPCs / EFs / src / tests
--     - 0 of 73 rows with a non-NULL value
--     - 0 readers apart from the SELECT in member_list_emails return shape
--   System policy "don't add features for hypothetical future requirements"
--   applies. Drop the column and recreate member_list_emails without it.
--
-- Rollback:
--   1. ALTER TABLE public.member_emails ADD COLUMN verified_at timestamptz;
--   2. DROP FUNCTION public.member_list_emails(uuid);
--   3. Recreate member_list_emails with verified_at restored to return TABLE.
--   4. NOTIFY pgrst, 'reload schema'.
--   All 73 backfilled rows would have verified_at NULL, matching pre-drop state.
--
-- Schema invariants: unchanged (T_member_has_exactly_one_primary_email does not
-- reference verified_at). Count stays at 19.

BEGIN;

-- 1. Drop existing RPC. CREATE OR REPLACE FUNCTION cannot change the RETURNS
--    TABLE column set on an existing function (errors with `cannot change
--    return type of existing function`), so we explicitly DROP first per GC-097.
DROP FUNCTION IF EXISTS public.member_list_emails(uuid);

-- 2. Drop the dead-schema column
ALTER TABLE public.member_emails DROP COLUMN verified_at;

-- 3. Recreate member_list_emails with verified_at removed from return TABLE.
--    Body is byte-identical to 20260802000008 lines 115-161 except the TABLE
--    columns and the SELECT projection — no auth-gate behaviour changes.
CREATE FUNCTION public.member_list_emails(p_member_id uuid)
RETURNS TABLE (
  id uuid,
  member_id uuid,
  email citext,
  is_primary boolean,
  kind text,
  added_at timestamptz,
  organization_id uuid
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller members%ROWTYPE;
  v_is_service_role boolean := false;
  v_allowed boolean := false;
BEGIN
  -- Determine if service_role or postgres is running
  IF current_setting('role', true) IN ('service_role', 'postgres') OR current_user IN ('postgres', 'supabase_admin') THEN
    v_is_service_role := true;
  END IF;

  IF NOT v_is_service_role THEN
    SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
    IF v_caller.id IS NULL THEN
      RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Check if self or manage_member or view_pii permission
    IF v_caller.id = p_member_id OR public.can_by_member(v_caller.id, 'manage_member') OR public.can_by_member(v_caller.id, 'view_pii') THEN
      v_allowed := true;
    END IF;

    IF NOT v_allowed THEN
      RAISE EXCEPTION 'Unauthorized to view member emails';
    END IF;
  END IF;

  RETURN QUERY
  SELECT me.id, me.member_id, me.email, me.is_primary, me.kind, me.added_at, me.organization_id
  FROM public.member_emails me
  WHERE me.member_id = p_member_id;
END;
$$;

-- 4. Re-grant execute permission
GRANT EXECUTE ON FUNCTION public.member_list_emails(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
