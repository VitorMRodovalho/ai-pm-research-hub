-- ============================================================================
-- V4 Phase 7c — Ghost resolution: sync persons.auth_id on login
-- ADR: ADR-0006 (Person + Engagement Identity Model)
-- Context: try_auto_link_ghost() sets members.auth_id on first login but
--          does NOT propagate to persons.auth_id. This migration fixes that.
-- Rollback: Restore try_auto_link_ghost from migration 20260403080000.
-- ============================================================================

CREATE OR REPLACE FUNCTION try_auto_link_ghost()
RETURNS SETOF members
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  v_member_id uuid;
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;

  -- Already linked? Sync persons.auth_id if needed, then return
  IF EXISTS (SELECT 1 FROM members WHERE auth_id = v_uid) THEN
    -- V4: ensure persons.auth_id is synced
    UPDATE persons SET auth_id = v_uid
    WHERE legacy_member_id = (SELECT id FROM members WHERE auth_id = v_uid LIMIT 1)
      AND (auth_id IS NULL OR auth_id != v_uid);
    RETURN QUERY SELECT * FROM members WHERE auth_id = v_uid LIMIT 1;
    RETURN;
  END IF;

  -- Get the email from auth.users
  SELECT email INTO v_email FROM auth.users WHERE id = v_uid;
  IF v_email IS NULL THEN RETURN; END IF;

  -- Try to find a member with matching email that has NO auth_id (never logged in)
  SELECT id INTO v_member_id FROM members
  WHERE lower(email) = lower(v_email) AND auth_id IS NULL
  LIMIT 1;

  IF v_member_id IS NOT NULL THEN
    UPDATE members SET auth_id = v_uid WHERE id = v_member_id;
    -- V4: propagate to persons
    UPDATE persons SET auth_id = v_uid WHERE legacy_member_id = v_member_id;
    RETURN QUERY SELECT * FROM members WHERE id = v_member_id;
    RETURN;
  END IF;

  -- Try member with matching email that HAS a DIFFERENT auth_id
  -- Safe because OAuth email is verified by the provider
  SELECT id INTO v_member_id FROM members
  WHERE lower(email) = lower(v_email) AND auth_id IS NOT NULL AND auth_id != v_uid
  LIMIT 1;

  IF v_member_id IS NOT NULL THEN
    UPDATE members SET auth_id = v_uid WHERE id = v_member_id;
    -- V4: propagate to persons
    UPDATE persons SET auth_id = v_uid WHERE legacy_member_id = v_member_id;
    RETURN QUERY SELECT * FROM members WHERE id = v_member_id;
    RETURN;
  END IF;

  -- No match found — genuine ghost
  RETURN;
END;
$$;

COMMENT ON FUNCTION try_auto_link_ghost() IS
  'Auto-link ghost to member by email match. V4: also syncs persons.auth_id (ADR-0006).';

GRANT EXECUTE ON FUNCTION try_auto_link_ghost TO authenticated;

NOTIFY pgrst, 'reload schema';
