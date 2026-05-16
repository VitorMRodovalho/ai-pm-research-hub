-- ============================================================================
-- P168 R3-a — Harden identity-resolver RPCs (remove silent secondary-email auto-claim)
-- Authorization: PM Vitor 2026-05-15 (after R1+R2 closed P168 D=1 incident — Paulo
--   Roberto de Camargo Filho was silently hijacking Paulo Alves' member row via
--   email match on members.secondary_emails — see docs/audit/P168_D1_PAULO_ALVES_AUTH_HIJACK_BRIEF.md)
--
-- Changes:
--   1. get_member_by_auth: remove (a) match-by-secondary_emails branch and
--      (b) "replace existing primary auth_id" branch. Keep direct auth_id match,
--      secondary_auth_ids match (admin-pre-approved → safe rotation), and
--      primary-email first-link ONLY when auth_id IS NULL. Add admin_audit_log
--      writes for any auto-claim event.
--   2. try_auto_link_ghost: remove the "different auth_id, same primary email
--      → reassign" branch. Keep first-link by primary email when auth_id IS NULL.
--      Add admin_audit_log write for first-link.
--   3. JSON return shape of get_member_by_auth UNCHANGED (callers in middleware,
--      Nav.astro, every page that calls sb.rpc('get_member_by_auth') keep working).
--
-- After this migration:
--   - A user logging in with credentials whose email matches another member's
--     secondary_emails will NOT be silently linked. They will resolve to NULL
--     (genuine ghost) and admin must manually disposition via secondary_auth_ids.
--   - A user logging in with credentials whose email matches a member's primary
--     email AND that member already has a different auth_id will NOT have the
--     primary reassigned. Same disposition path.
--   - Legitimate auto-link still works in two cases:
--       (a) First-time login by a member whose email matches members.email and
--           members.auth_id IS NULL.
--       (b) Member with multiple OAuth identities pre-approved in
--           secondary_auth_ids — rotation still happens (admin chose those).
--
-- R4 (future) will restore the secondary-email auto-claim path safely by
-- requiring email-ownership verification before write to secondary_emails.
--
-- Rollback: restore prior bodies from
--   - get_member_by_auth: current live body (pre-migration) captured in
--     docs/audit/P168_D1_PAULO_ALVES_AUTH_HIJACK_BRIEF.md "Root cause (code)"
--   - try_auto_link_ghost: migration 20260415090000_v4_phase7c_ghost_resolution_persons.sql
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_member_by_auth()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  v_member_id uuid;
  v_existing_auth_id uuid;
  v_result json;
BEGIN
  IF v_uid IS NULL THEN
    RETURN NULL;
  END IF;

  -- Step 1: direct match on members.auth_id (the common case)
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_uid LIMIT 1;

  -- Step 2: match on secondary_auth_ids (admin-pre-approved alternates → safe to rotate)
  IF v_member_id IS NULL THEN
    SELECT id INTO v_member_id
      FROM public.members
     WHERE v_uid = ANY(COALESCE(secondary_auth_ids, '{}'))
     LIMIT 1;

    IF v_member_id IS NOT NULL THEN
      SELECT auth_id INTO v_existing_auth_id FROM public.members WHERE id = v_member_id;

      UPDATE public.members
         SET auth_id            = v_uid,
             secondary_auth_ids = array_append(
                                    array_remove(COALESCE(secondary_auth_ids, '{}'::uuid[]), v_uid),
                                    v_existing_auth_id
                                  ),
             updated_at         = now()
       WHERE id = v_member_id;

      INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
      VALUES (
        v_member_id,
        'members.auth_id.rotated_secondary_to_primary',
        'member',
        v_member_id,
        jsonb_build_object(
          'promoted_auth_id', v_uid,
          'demoted_auth_id', v_existing_auth_id
        ),
        jsonb_build_object('via', 'get_member_by_auth.step2_secondary_auth_ids_match')
      );
    END IF;
  END IF;

  -- Step 3: PRIMARY email first-link (only when auth_id IS NULL — genuine ghost first login).
  -- P168 R3-a: dropped the (a) secondary_emails match branch and (b) replace-existing-auth_id
  -- branch. Both were the mechanism behind Paulo Alves identity hijack.
  IF v_member_id IS NULL THEN
    SELECT lower(email) INTO v_email FROM auth.users WHERE id = v_uid;

    IF v_email IS NOT NULL THEN
      SELECT id INTO v_member_id
        FROM public.members
       WHERE lower(email) = v_email
         AND auth_id IS NULL
       LIMIT 1;

      IF v_member_id IS NOT NULL THEN
        UPDATE public.members
           SET auth_id    = v_uid,
               updated_at = now()
         WHERE id = v_member_id;

        INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
        VALUES (
          v_member_id,
          'members.auth_id.first_link',
          'member',
          v_member_id,
          jsonb_build_object(
            'linked_auth_id', v_uid,
            'matched_via',    'primary_email',
            'matched_email',  v_email
          ),
          jsonb_build_object('via', 'get_member_by_auth.step3_primary_email_when_null')
        );
      END IF;
    END IF;
  END IF;

  IF v_member_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Return JSON shape — UNCHANGED from prior version (callers depend on this).
  SELECT row_to_json(q) INTO v_result FROM (
    SELECT m.id, m.name, m.email, m.secondary_emails,
      m.pmi_id, m.phone, m.operational_role, m.designations,
      compute_legacy_role(m.operational_role, m.designations)  AS role,
      compute_legacy_roles(m.operational_role, m.designations) AS roles,
      m.chapter, m.tribe_id, m.current_cycle_active, m.is_superadmin, m.is_active,
      m.member_status, m.state, m.country, m.share_whatsapp, m.signature_url,
      m.address, m.city, m.birth_date,
      m.share_address, m.share_birth_date,
      m.privacy_consent_accepted_at, m.privacy_consent_version, m.data_last_reviewed_at,
      m.inactivated_at, m.inactivation_reason,
      m.photo_url, m.linkedin_url, m.auth_id,
      m.credly_url, m.credly_badges, m.cpmai_certified,
      m.created_at, m.updated_at
    FROM public.members m
    WHERE m.id = v_member_id
  ) q;

  RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.get_member_by_auth() IS
  'Resolve current auth.uid() to a member row (JSON). P168 R3-a hardened: drops the silent-hijack branch (secondary_emails match + replace-existing-auth_id). Auto-claim now only happens via direct auth_id match, admin-approved secondary_auth_ids rotation, or first-link by primary email when auth_id IS NULL. Every auto-claim writes admin_audit_log. See docs/audit/P168_D1_PAULO_ALVES_AUTH_HIJACK_BRIEF.md.';

GRANT EXECUTE ON FUNCTION public.get_member_by_auth() TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.try_auto_link_ghost()
RETURNS SETOF public.members
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  v_member_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;

  -- Already linked? Sync persons.auth_id if stale, return the member.
  IF EXISTS (SELECT 1 FROM public.members WHERE auth_id = v_uid) THEN
    UPDATE public.persons
       SET auth_id = v_uid
     WHERE legacy_member_id = (SELECT id FROM public.members WHERE auth_id = v_uid LIMIT 1)
       AND (auth_id IS NULL OR auth_id != v_uid);

    RETURN QUERY SELECT * FROM public.members WHERE auth_id = v_uid LIMIT 1;
    RETURN;
  END IF;

  -- First-link by primary email (genuine ghost flow).
  SELECT email INTO v_email FROM auth.users WHERE id = v_uid;
  IF v_email IS NULL THEN
    RETURN;
  END IF;

  SELECT id INTO v_member_id
    FROM public.members
   WHERE lower(email) = lower(v_email)
     AND auth_id IS NULL
   LIMIT 1;

  IF v_member_id IS NOT NULL THEN
    UPDATE public.members SET auth_id = v_uid, updated_at = now() WHERE id = v_member_id;
    UPDATE public.persons SET auth_id = v_uid WHERE legacy_member_id = v_member_id;

    INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      v_member_id,
      'members.auth_id.first_link',
      'member',
      v_member_id,
      jsonb_build_object(
        'linked_auth_id', v_uid,
        'matched_via',    'primary_email',
        'matched_email',  lower(v_email)
      ),
      jsonb_build_object('via', 'try_auto_link_ghost.primary_email_when_null')
    );

    RETURN QUERY SELECT * FROM public.members WHERE id = v_member_id;
    RETURN;
  END IF;

  -- P168 R3-a: the "match by email when auth_id IS NOT NULL → reassign" branch has been
  -- REMOVED. Cross-identity matches must now go through admin manual disposition.
  RETURN;
END;
$function$;

COMMENT ON FUNCTION public.try_auto_link_ghost() IS
  'Ghost first-link by primary email. P168 R3-a hardened: drops the silent reassignment branch (matching member.email when auth_id IS NOT NULL → replace primary, propagate to persons). Only first-link when auth_id IS NULL is auto. Cross-identity reassignment now requires admin action.';

GRANT EXECUTE ON FUNCTION public.try_auto_link_ghost() TO authenticated;

NOTIFY pgrst, 'reload schema';
