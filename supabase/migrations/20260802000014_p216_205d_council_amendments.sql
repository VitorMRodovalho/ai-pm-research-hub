-- Migration: member_emails write surface — Council Tier 1 amendments (HIGH + MED + LOW)
-- Issue: #205 GAP-205.D council review on PR #244 (commit 08b14ebc)
-- ADR: 0095 (amended 2026-05-21 GAP-205.D — see ADR Amendment 2026-05-21 GAP-205.D)
--
-- Council findings addressed:
--
--   HIGH (code-reviewer, LGPD member-existence oracle):
--     The error message in member_set_primary_email exposed the p_member_id
--     in the RAISE EXCEPTION format string (`Email % is not registered for
--     member %; add it via member_add_alternate_email first.`). An auth-gated
--     caller with manage_member capability could enumerate member_ids by
--     probing set_primary with a guessed email + member_id pair. Replaced
--     with a generic `Email not found for this member; ensure it was
--     previously added.` — the member_id is not echoed and the helper-RPC
--     hint is dropped.
--
--   MED #1 (code-reviewer, SELECT+DELETE race in member_remove_alternate_email):
--     The two-statement read-then-delete pattern allowed a concurrent
--     member_set_primary_email on another connection to promote the row
--     between our SELECT (is_primary=false) and our DELETE. The DELETE then
--     removed the newly-promoted primary row, leaving the member with zero
--     primary rows — violating invariant T_member_has_exactly_one_primary_email.
--     Added `FOR UPDATE` to the SELECT to serialize against trigger UPDATEs
--     on the same row.
--
--   MED #2 (code-reviewer, multi-tenant org boundary gap in 3 RPCs):
--     SECDEF functions bypass RLS — the member_emails_v4_org_scope
--     RESTRICTIVE policy that scopes to auth_org() does not apply during
--     function execution. A caller with manage_member capability in org A
--     passing a p_member_id from org B would operate on org B's email rows
--     without any boundary check. The capability gate via can_by_member is
--     not target-scoped — it only verifies the caller's authority globally.
--     Added the same org_id lookup that member_add_alternate_email
--     (mig 20260802000008 line 208) already performs: SELECT organization_id
--     FROM members WHERE id = p_member_id; RAISE if member not found. This
--     does not add a strict cross-org comparison (a member with manage_member
--     in org A operating on org B is still authorized per can_by_member), but
--     it (a) raises a clear error if the target member does not exist at all,
--     and (b) creates a single point where future org-scoping checks can be
--     added when the cross-org policy is tightened.
--
--   LOW #1 (code-reviewer, internal RPC name in error message):
--     `Cannot remove primary email; promote another alternate via
--     member_set_primary_email first.` exposed an internal RPC name in a
--     user-facing error. Replaced with `Cannot remove primary email; promote
--     a different alternate to primary first.` — same guidance, no internal
--     surface leak.
--
-- The three RPCs keep identical signatures (uuid, text) / (uuid, text) /
-- (uuid, text, text) so CREATE OR REPLACE FUNCTION can update the bodies
-- without a DROP + CREATE cycle. Existing GRANT EXECUTE and COMMENT ON
-- statements remain in effect from migration 20260802000013.
--
-- Schema invariants: unchanged (still 19). FOR UPDATE row-level lock
-- strengthens enforcement of T at concurrency boundaries but does not
-- change the invariant set.
--
-- Rollback:
--   Re-apply the bodies from migration 20260802000013 via CREATE OR REPLACE
--   FUNCTION. The signatures match, so no DROP is required.

BEGIN;

-- RPC: member_remove_alternate_email (amendments: MED #1 FOR UPDATE + MED #2 org check + LOW #1 generic msg)
CREATE OR REPLACE FUNCTION public.member_remove_alternate_email(
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
  v_target_org_id uuid;
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

  -- MED #2: org boundary anchor — raise if member not found (matches member_add_alternate_email pattern from mig 20260802000008 line 208).
  SELECT organization_id INTO v_target_org_id FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Member not found: %', p_member_id;
  END IF;

  -- MED #1: FOR UPDATE serializes against concurrent set_primary trigger UPDATEs on the same row.
  SELECT id, is_primary INTO v_row_id, v_is_primary
  FROM public.member_emails
  WHERE member_id = p_member_id AND email = p_email::citext
  LIMIT 1
  FOR UPDATE;

  IF v_row_id IS NULL THEN
    RETURN false;
  END IF;

  IF v_is_primary THEN
    -- LOW #1: replaced internal RPC name with neutral guidance.
    RAISE EXCEPTION 'Cannot remove primary email; promote a different alternate to primary first.';
  END IF;

  DELETE FROM public.member_emails WHERE id = v_row_id;
  RETURN true;
END;
$$;

-- RPC: member_set_primary_email (amendments: HIGH LGPD generic msg + MED #2 org check)
CREATE OR REPLACE FUNCTION public.member_set_primary_email(
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
  v_target_org_id uuid;
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

  -- MED #2: org boundary anchor.
  SELECT organization_id INTO v_target_org_id FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Member not found: %', p_member_id;
  END IF;

  SELECT id, is_primary, email INTO v_row_id, v_is_primary, v_canonical
  FROM public.member_emails
  WHERE member_id = p_member_id AND email = p_email::citext
  LIMIT 1;

  IF v_row_id IS NULL THEN
    -- HIGH (LGPD): generic message — no member_id echo, no helper-RPC hint.
    RAISE EXCEPTION 'Email not found for this member; ensure it was previously added.';
  END IF;

  IF v_is_primary THEN
    RETURN true;
  END IF;

  UPDATE public.members SET email = v_canonical::text WHERE id = p_member_id;
  RETURN true;
END;
$$;

-- RPC: member_update_alternate_email_kind (amendments: MED #2 org check only — HIGH/MED #1/LOW #1 do not apply)
CREATE OR REPLACE FUNCTION public.member_update_alternate_email_kind(
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
  v_target_org_id uuid;
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

  -- MED #2: org boundary anchor.
  SELECT organization_id INTO v_target_org_id FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Member not found: %', p_member_id;
  END IF;

  SELECT id, is_primary INTO v_row_id, v_is_primary
  FROM public.member_emails
  WHERE member_id = p_member_id AND email = p_email::citext
  LIMIT 1;

  IF v_row_id IS NULL THEN
    RETURN false;
  END IF;

  IF v_is_primary THEN
    RAISE EXCEPTION 'Cannot change kind on primary email; primary kind follows backfill convention. Promote a different alternate to primary if you want this alternate to take over the primary role.';
  END IF;

  UPDATE public.member_emails SET kind = p_new_kind WHERE id = v_row_id;
  RETURN true;
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;
