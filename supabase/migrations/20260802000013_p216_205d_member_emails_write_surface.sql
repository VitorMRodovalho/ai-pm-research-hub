-- Migration: member_emails write surface completion (remove + set_primary + update_kind)
-- Issue: #205 GAP-205.D (P162 #126) — surfaced organically in p215 PM smoke
-- ADR: 0095 (amended 2026-05-21 — see "Amendment 2026-05-21 (GAP-205.D)")
--
-- Context:
--   p213/p214/p215 shipped read + add surface (resolve, list, add_alternate).
--   PM smoke in p215 revealed no kind-correction path without direct SQL: PM
--   added an alternate with kind='personal' intending 'institutional'. Three
--   write operations remain to complete the surface:
--     - member_remove_alternate_email: delete an alternate row
--     - member_set_primary_email: promote an existing alternate to primary
--     - member_update_alternate_email_kind: change kind on an alternate
--   All 3 RPCs follow the existing self-OR-manage_member auth pattern from
--   member_add_alternate_email (mig 20260802000008 lines 163-220) and reject
--   mutations on the primary email. Primary email is sync-trigger-driven from
--   members.email (mig 20260802000009 cross-member theft guard); kind on
--   primary follows the backfill convention 'personal' plus the trigger's
--   ON CONFLICT preservation of alt kind when an alt is promoted to primary.
--
-- Design choice (PM p216 ABCD Recommended): member_set_primary_email routes
--   the change through UPDATE members.email, which fires
--   sync_member_email_trigger_fn — single source of truth, reuses the existing
--   cross-member theft guard, alt kind preserved via ON CONFLICT DO UPDATE.
--
-- Rollback:
--   DROP FUNCTION IF EXISTS public.member_remove_alternate_email(uuid, text);
--   DROP FUNCTION IF EXISTS public.member_set_primary_email(uuid, text);
--   DROP FUNCTION IF EXISTS public.member_update_alternate_email_kind(uuid, text, text);
--   NOTIFY pgrst, 'reload schema';
--   MCP tools are removed from supabase/functions/nucleo-mcp/index.ts in the same PR.
--
-- Schema invariants: unchanged. T_member_has_exactly_one_primary_email already
-- enforces the partial-unique invariant; these RPCs cannot violate it because
-- (a) remove rejects primary, (b) set_primary routes via the existing trigger
-- which is itself constrained by the partial unique index, (c) update_kind
-- only touches the kind column (not is_primary).

BEGIN;

-- Idempotency: drop any prior signature variants (none expected — fresh names — but defensive per GC-097).
DROP FUNCTION IF EXISTS public.member_remove_alternate_email(uuid, text);
DROP FUNCTION IF EXISTS public.member_set_primary_email(uuid, text);
DROP FUNCTION IF EXISTS public.member_update_alternate_email_kind(uuid, text, text);

-- RPC: member_remove_alternate_email(p_member_id uuid, p_email text)
-- Returns true if a row was deleted, false if the email is not registered for this member.
-- Raises if the email is the member's primary (use member_set_primary_email to promote a different
-- alternate first, then remove the demoted one).
CREATE FUNCTION public.member_remove_alternate_email(
  p_member_id uuid,
  p_email text
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller members%ROWTYPE;
  v_is_service_role boolean := false;
  v_allowed boolean := false;
  v_row_id uuid;
  v_is_primary boolean;
BEGIN
  IF current_setting('role', true) IN ('service_role', 'postgres') OR current_user IN ('postgres', 'supabase_admin') THEN
    v_is_service_role := true;
  END IF;

  IF NOT v_is_service_role THEN
    SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
    IF v_caller.id IS NULL THEN
      RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF v_caller.id = p_member_id OR public.can_by_member(v_caller.id, 'manage_member') THEN
      v_allowed := true;
    END IF;

    IF NOT v_allowed THEN
      RAISE EXCEPTION 'Unauthorized to remove alternate email';
    END IF;
  END IF;

  SELECT id, is_primary INTO v_row_id, v_is_primary
  FROM public.member_emails
  WHERE member_id = p_member_id AND email = p_email::citext
  LIMIT 1;

  IF v_row_id IS NULL THEN
    RETURN false;
  END IF;

  IF v_is_primary THEN
    RAISE EXCEPTION 'Cannot remove primary email; promote another alternate via member_set_primary_email first.';
  END IF;

  DELETE FROM public.member_emails WHERE id = v_row_id;
  RETURN true;
END;
$$;

-- RPC: member_set_primary_email(p_member_id uuid, p_email text)
-- Promotes a registered alternate to primary by routing through UPDATE members.email,
-- which fires sync_member_email_trigger_fn (mig 20260802000009): the trigger demotes
-- the previous primary and promotes p_email via INSERT ... ON CONFLICT DO UPDATE
-- SET is_primary = true, preserving the existing alt kind.
-- Returns true on success or no-op (already primary). Raises if email is not registered
-- for the member (must be added via member_add_alternate_email first).
CREATE FUNCTION public.member_set_primary_email(
  p_member_id uuid,
  p_email text
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller members%ROWTYPE;
  v_is_service_role boolean := false;
  v_allowed boolean := false;
  v_row_id uuid;
  v_is_primary boolean;
  v_canonical citext;
BEGIN
  IF current_setting('role', true) IN ('service_role', 'postgres') OR current_user IN ('postgres', 'supabase_admin') THEN
    v_is_service_role := true;
  END IF;

  IF NOT v_is_service_role THEN
    SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
    IF v_caller.id IS NULL THEN
      RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF v_caller.id = p_member_id OR public.can_by_member(v_caller.id, 'manage_member') THEN
      v_allowed := true;
    END IF;

    IF NOT v_allowed THEN
      RAISE EXCEPTION 'Unauthorized to set primary email';
    END IF;
  END IF;

  SELECT id, is_primary, email INTO v_row_id, v_is_primary, v_canonical
  FROM public.member_emails
  WHERE member_id = p_member_id AND email = p_email::citext
  LIMIT 1;

  IF v_row_id IS NULL THEN
    RAISE EXCEPTION 'Email % is not registered for member %; add it via member_add_alternate_email first.', p_email, p_member_id;
  END IF;

  IF v_is_primary THEN
    RETURN true;
  END IF;

  UPDATE public.members SET email = v_canonical::text WHERE id = p_member_id;
  RETURN true;
END;
$$;

-- RPC: member_update_alternate_email_kind(p_member_id uuid, p_email text, p_new_kind text)
-- Updates the kind on a registered alternate email. Rejects mutations on the primary
-- (primary kind follows backfill convention 'personal' and the sync trigger).
-- Returns true if the row was updated, false if the email is not registered for the member.
CREATE FUNCTION public.member_update_alternate_email_kind(
  p_member_id uuid,
  p_email text,
  p_new_kind text
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller members%ROWTYPE;
  v_is_service_role boolean := false;
  v_allowed boolean := false;
  v_row_id uuid;
  v_is_primary boolean;
BEGIN
  IF current_setting('role', true) IN ('service_role', 'postgres') OR current_user IN ('postgres', 'supabase_admin') THEN
    v_is_service_role := true;
  END IF;

  IF NOT v_is_service_role THEN
    SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
    IF v_caller.id IS NULL THEN
      RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF v_caller.id = p_member_id OR public.can_by_member(v_caller.id, 'manage_member') THEN
      v_allowed := true;
    END IF;

    IF NOT v_allowed THEN
      RAISE EXCEPTION 'Unauthorized to update alternate email kind';
    END IF;
  END IF;

  IF p_new_kind NOT IN ('personal', 'institutional', 'chapter', 'other') THEN
    RAISE EXCEPTION 'Invalid email kind: %', p_new_kind;
  END IF;

  SELECT id, is_primary INTO v_row_id, v_is_primary
  FROM public.member_emails
  WHERE member_id = p_member_id AND email = p_email::citext
  LIMIT 1;

  IF v_row_id IS NULL THEN
    RETURN false;
  END IF;

  IF v_is_primary THEN
    RAISE EXCEPTION 'Cannot change kind on primary email; primary kind follows backfill convention. Promote a different alternate via member_set_primary_email if you want this alternate to take over the primary role.';
  END IF;

  UPDATE public.member_emails SET kind = p_new_kind WHERE id = v_row_id;
  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.member_remove_alternate_email(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.member_set_primary_email(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.member_update_alternate_email_kind(uuid, text, text) TO authenticated;

COMMENT ON FUNCTION public.member_remove_alternate_email(uuid, text) IS
'ADR-0095 GAP-205.D: Remove an alternate email row. Rejects primary; use member_set_primary_email to promote a different alternate first. Returns true if removed, false if email not registered for member.';

COMMENT ON FUNCTION public.member_set_primary_email(uuid, text) IS
'ADR-0095 GAP-205.D: Promote an existing alternate to primary via UPDATE members.email (fires sync trigger). Idempotent on already-primary. Raises if email not registered for member.';

COMMENT ON FUNCTION public.member_update_alternate_email_kind(uuid, text, text) IS
'ADR-0095 GAP-205.D: Change kind on an alternate email. Rejects primary (kind follows backfill convention). Returns true if updated, false if email not registered for member.';

NOTIFY pgrst, 'reload schema';

COMMIT;
