-- =====================================================================================
-- #684 — SECURITY FIX (CRITICAL/HIGH): close the same SECDEF auth-gate bypass on the
-- anon-reachable functions (the systemic case found while shipping #676 Slice 4 / PR #683).
--
-- Root cause (identical to #676): the cron/service heuristic
--   current_setting('role') IN ('service_role','postgres') OR current_user IN ('postgres','supabase_admin')
-- is ALWAYS true inside a SECDEF owned by `postgres` (current_user = owner for every caller),
-- so the per-function auth check (self / manage_member / etc.) never ran. Verified live:
-- `SET ROLE anon; SELECT detect_inactive_members();` executed instead of raising Unauthorized;
-- `member_set_primary_email` body skips the ownership check for all callers.
--
-- Impact: the 5 `member_*_email` functions are granted to `anon` → anyone could set/add/remove
-- a member's email (account integrity). `detect_inactive_members` leaks the inactive-member PII
-- list to anon and allows side-effects via p_dry_run:=false.
--
-- Fix: generic role-GUC discriminator `_request_is_rest_caller()` (true for authenticated/anon;
-- false for cron — postgres, role GUC unset — and service_role). The bypass flag becomes
-- `NOT _request_is_rest_caller()`. Bodies are otherwise re-emitted verbatim. Also REVOKE anon
-- EXECUTE on all six (defense in depth — none should ever be anon-callable).
--
-- Scope: this fixes the 6 ANON-reachable functions. The 3 authenticated-only MED functions
-- (auto_promote_eligible_leads_for_cycle, compute_ai_calibration_stats, list_ai_calibration_runs)
-- carry the same pattern and are tracked for a fast follow-up (lower severity, no anon path).
-- See #684.
-- =====================================================================================

-- ----------------------------------------------------------------------------
-- Generic caller discriminator (NOT security definer — reads the caller's role GUC).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._request_is_rest_caller()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'public','pg_temp'
AS $function$
  -- True for PostgREST end-users (role GUC = authenticated/anon). current_user is ALWAYS
  -- the SECDEF owner (postgres) and cannot distinguish callers; the request role GUC can.
  SELECT coalesce(current_setting('role', true), '') IN ('authenticated','anon');
$function$;

REVOKE ALL ON FUNCTION public._request_is_rest_caller() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._request_is_rest_caller() TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- member_add_alternate_email
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.member_add_alternate_email(p_member_id uuid, p_email text, p_kind text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_is_service_role boolean := false;
  v_allowed boolean := false;
  v_new_id uuid;
  v_org_id uuid;
BEGIN
  -- #684: role-GUC discriminator (current_user is always the SECDEF owner under SECDEF).
  v_is_service_role := NOT public._request_is_rest_caller();

  IF NOT v_is_service_role THEN
    SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
    IF v_caller.id IS NULL THEN
      RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Check if self or manage_member permission
    IF v_caller.id = p_member_id OR public.can_by_member(v_caller.id, 'manage_member') THEN
      v_allowed := true;
    END IF;

    IF NOT v_allowed THEN
      RAISE EXCEPTION 'Unauthorized to add alternate email';
    END IF;
  END IF;

  -- Verify p_kind value is valid
  IF p_kind NOT IN ('personal', 'institutional', 'chapter', 'other') THEN
    RAISE EXCEPTION 'Invalid email kind: %', p_kind;
  END IF;

  -- Get organization_id of the member to ensure multi-tenancy scoping
  SELECT organization_id INTO v_org_id FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Member not found: %', p_member_id;
  END IF;

  -- Insert the alternate email. Alternate emails are not primary.
  INSERT INTO public.member_emails (member_id, email, is_primary, kind, organization_id)
  VALUES (p_member_id, p_email, false, p_kind, v_org_id)
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$function$;

-- ----------------------------------------------------------------------------
-- member_list_emails
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.member_list_emails(p_member_id uuid)
 RETURNS TABLE(id uuid, member_id uuid, email citext, is_primary boolean, kind text, added_at timestamp with time zone, organization_id uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_is_service_role boolean := false;
  v_allowed boolean := false;
BEGIN
  -- #684: role-GUC discriminator (current_user is always the SECDEF owner under SECDEF).
  v_is_service_role := NOT public._request_is_rest_caller();

  IF NOT v_is_service_role THEN
    SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
    IF v_caller.id IS NULL THEN
      RAISE EXCEPTION 'Not authenticated';
    END IF;

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
$function$;

-- ----------------------------------------------------------------------------
-- member_remove_alternate_email
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.member_remove_alternate_email(p_member_id uuid, p_email text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_is_service_role boolean := false;
  v_allowed boolean := false;
  v_target_org_id uuid;
  v_row_id uuid;
  v_is_primary boolean;
BEGIN
  -- #684: role-GUC discriminator (current_user is always the SECDEF owner under SECDEF).
  v_is_service_role := NOT public._request_is_rest_caller();

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
$function$;

-- ----------------------------------------------------------------------------
-- member_set_primary_email
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.member_set_primary_email(p_member_id uuid, p_email text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_is_service_role boolean := false;
  v_allowed boolean := false;
  v_target_org_id uuid;
  v_row_id uuid;
  v_is_primary boolean;
  v_canonical citext;
BEGIN
  -- #684: role-GUC discriminator (current_user is always the SECDEF owner under SECDEF).
  v_is_service_role := NOT public._request_is_rest_caller();

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
$function$;

-- ----------------------------------------------------------------------------
-- member_update_alternate_email_kind
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.member_update_alternate_email_kind(p_member_id uuid, p_email text, p_new_kind text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_is_service_role boolean := false;
  v_allowed boolean := false;
  v_target_org_id uuid;
  v_row_id uuid;
  v_is_primary boolean;
BEGIN
  -- #684: role-GUC discriminator (current_user is always the SECDEF owner under SECDEF).
  v_is_service_role := NOT public._request_is_rest_caller();

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
$function$;

-- ----------------------------------------------------------------------------
-- detect_inactive_members
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.detect_inactive_members(p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_threshold int;
  v_candidates jsonb := '[]'::jsonb;
  v_count int := 0;
  v_notified int := 0;
  v_cron_context boolean;
BEGIN
  -- #684: role-GUC discriminator (current_user is always the SECDEF owner under SECDEF).
  v_cron_context := NOT public._request_is_rest_caller();

  IF NOT v_cron_context AND auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF NOT v_cron_context THEN
    PERFORM 1 FROM public.members
    WHERE auth_id = auth.uid()
      AND public.can_by_member(id, 'manage_member');
    IF NOT FOUND THEN RAISE EXCEPTION 'Unauthorized: requires manage_member'; END IF;
  END IF;

  SELECT COALESCE((value::text)::int, 180) INTO v_threshold
  FROM public.site_config WHERE key = 'inactivity_threshold_days';
  v_threshold := COALESCE(v_threshold, 180);

  WITH inactive AS (
    SELECT
      m.id AS member_id,
      m.name,
      m.email,
      m.tribe_id,
      m.chapter,
      m.created_at AS member_created_at,
      (SELECT MAX(a.checked_in_at) FROM public.attendance a
        WHERE a.member_id = m.id AND a.present = true) AS last_attendance_at,
      m.updated_at AS last_member_update_at
    FROM public.members m
    WHERE m.member_status = 'active'
      AND m.is_active = true
      AND m.anonymized_at IS NULL
      AND m.name <> 'VP Desenvolvimento Profissional (PMI-GO)'
      -- Exclude very recent joins (need at least threshold days history)
      AND m.created_at < (now() - make_interval(days => v_threshold))
      -- Either no attendance ever, OR last attendance older than threshold
      AND NOT EXISTS (
        SELECT 1 FROM public.attendance a
        WHERE a.member_id = m.id AND a.present = true
          AND a.checked_in_at > (now() - make_interval(days => v_threshold))
      )
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'member_id', member_id,
    'name', name,
    'chapter', chapter,
    'tribe_id', tribe_id,
    'last_attendance_at', last_attendance_at,
    'days_since_last_attendance',
      CASE WHEN last_attendance_at IS NULL
        THEN EXTRACT(DAY FROM now() - member_created_at)::int
        ELSE EXTRACT(DAY FROM now() - last_attendance_at)::int
      END
  )), '[]'::jsonb), COALESCE(COUNT(*), 0)
  INTO v_candidates, v_count
  FROM inactive;

  -- p179 ADR-0011 V4: notify admins via manage_platform capability
  -- (replaces operational_role IN ('manager','deputy_manager')).
  IF NOT p_dry_run AND v_count > 0 THEN
    INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id)
    SELECT mgr.id,
           'arm9_inactivity_alert',
           v_count || ' membro(s) sem atividade há mais de ' || v_threshold || ' dias',
           'Considerar transição para status inactive. Lista disponível em /admin/members?filter=inactive_candidates',
           '/admin/members?filter=inactive_candidates',
           'arm9_inactivity_detection',
           NULL
    FROM public.members mgr
    WHERE mgr.is_active = true
      AND can_by_member(mgr.id, 'manage_platform');
    GET DIAGNOSTICS v_notified = ROW_COUNT;

    -- p180 fix: target_type='system_event' explicit. p179 passed NULL which
    -- overrides column DEFAULT 'member' and triggers NOT NULL violation.
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL, 'arm9.inactivity_detection_run', 'system_event', NULL,
      jsonb_build_object('threshold_days', v_threshold, 'candidates_count', v_count, 'managers_notified', v_notified),
      jsonb_build_object('dry_run', false, 'source', 'cron_or_manual')
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'threshold_days', v_threshold,
    'candidates_count', v_count,
    'candidates', v_candidates,
    'managers_notified', v_notified,
    'dry_run', p_dry_run
  );
END $function$;

-- ----------------------------------------------------------------------------
-- Defense in depth: none of these should be anon-callable.
-- ----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.member_add_alternate_email(uuid, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.member_list_emails(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.member_remove_alternate_email(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.member_set_primary_email(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.member_update_alternate_email_kind(uuid, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.detect_inactive_members(boolean) FROM anon;

NOTIFY pgrst, 'reload schema';
