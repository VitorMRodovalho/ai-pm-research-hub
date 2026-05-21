-- Migration: member_emails trigger email-theft guard + revoke SELECT from authenticated
-- Issue: #205 (council Tier 1 HIGH findings — email-theft via ON CONFLICT DO UPDATE SET member_id)
-- Triggered by: PR #240 council Tier 1 review (platform-guardian MED-1 + code-reviewer HIGH-1)
-- Migration: 20260802000009 (follow-up to 20260802000008)
--
-- ROLLBACK:
--   1. CREATE OR REPLACE FUNCTION public.sync_member_email_trigger_fn() with the previous body
--      (see 20260802000008_member_alternate_emails.sql lines 52-80) — be advised that
--      reverting reopens the email-theft vector documented in PR #240 council review.
--   2. GRANT SELECT ON public.member_emails TO authenticated;
--   3. NOTIFY pgrst, 'reload schema';
--
-- LEAK CLEANUP (if test rows from member_emails.test.mjs leaked from prior CI runs):
--   DELETE FROM public.members WHERE name = '__test_member_205_synthetic__';
--   -- (CASCADE removes member_emails rows automatically via FK)

BEGIN;

-- Replace trigger function with cross-member collision guard
CREATE OR REPLACE FUNCTION public.sync_member_email_trigger_fn()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_existing_member_id uuid;
BEGIN
  -- Defensive: no-op for NULL email (members.email may be NULL in legacy rows)
  IF NEW.email IS NULL THEN
    RETURN NEW;
  END IF;

  -- Only act when INSERT or email-change UPDATE
  IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE' AND OLD.email IS DISTINCT FROM NEW.email) THEN
    -- Cross-member collision guard (Issue #205 council Tier 1 amendment)
    -- The original DO UPDATE SET member_id = NEW.id silently transferred email ownership
    -- between members (email theft vector); now we raise instead.
    SELECT member_id INTO v_existing_member_id
    FROM public.member_emails
    WHERE email = NEW.email::citext;

    IF v_existing_member_id IS NOT NULL AND v_existing_member_id <> NEW.id THEN
      RAISE EXCEPTION
        'Email % already belongs to another member (id=%); cross-member email transfer not allowed via members.email change.',
        NEW.email, v_existing_member_id
        USING ERRCODE = '23505',  -- unique_violation
              HINT = 'Deactivate or migrate the existing member_emails row before reassigning ownership.';
    END IF;

    -- For UPDATE path: demote current primary first
    IF (TG_OP = 'UPDATE') THEN
      UPDATE public.member_emails
      SET is_primary = false
      WHERE member_id = NEW.id AND is_primary = true;
    END IF;

    -- INSERT or same-member sync. On conflict (same member), we preserve the
    -- existing kind (the row may have been seeded as institutional/chapter/other);
    -- only is_primary and organization_id are updated. member_id is NEVER touched
    -- on conflict because the cross-member guard above ensures collision is
    -- only possible for the same member.
    INSERT INTO public.member_emails (member_id, email, is_primary, kind, organization_id)
    VALUES (NEW.id, NEW.email, true, 'personal', NEW.organization_id)
    ON CONFLICT (email) DO UPDATE
    SET is_primary = true,
        organization_id = EXCLUDED.organization_id;
  END IF;
  RETURN NEW;
END;
$$;

-- Defense in depth (council LOW-1): revoke SELECT from authenticated.
-- The SECDEF RPCs (member_resolve_email / member_list_emails) are the canonical read
-- path; direct PostgREST SELECT was already blocked by RLS PERMISSIVE(false), but
-- removing the grant prevents accidental future drift if the policy is ever changed.
REVOKE SELECT ON public.member_emails FROM authenticated;

COMMENT ON FUNCTION public.sync_member_email_trigger_fn() IS
'Sync trigger from members.email → member_emails primary; cross-member email collision raises 23505 (Issue #205 council Tier 1 amendment, PR #240).';

NOTIFY pgrst, 'reload schema';

COMMIT;
