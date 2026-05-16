-- ============================================================================
-- P168 R4 — Email-verified secondary_emails flow
-- Authorization: PM Vitor 2026-05-15 (R4 of P168 D=1 remediation roadmap)
--
-- Adds verification step before any email is appended to members.secondary_emails.
-- Locks direct column UPDATE via trigger; only the SECURITY DEFINER RPCs in this
-- migration (plus service_role / superadmin) can mutate the array.
--
-- Existing secondary_emails are GRANDFATHERED (PM choice) — trigger only guards
-- future CHANGES, not the snapshot. R3-a already closed the silent-claim hijack
-- in get_member_by_auth so the grandfathered state cannot be exploited the same way.
--
-- Components:
--   1. email_verification_pending table — token, target_email, requester, lifecycle
--   2. _tg_lock_members_secondary_emails BEFORE UPDATE trigger with bypass via
--      session-local `app.bypass_secondary_emails_lock = 'true'` set by RPCs
--   3. request_secondary_email_verification(p_email) — validate + insert + dispatch EF
--   4. confirm_secondary_email(p_token) — bypass + append + audit
--   5. remove_secondary_email(p_email) — direct removal (PM choice: no email confirm)
--
-- Token TTL: 24h (PM choice)
-- EF dispatch: pg_net.http_post → send-email-verification (deployed separately)
-- ============================================================================

-- 1) Table
CREATE TABLE IF NOT EXISTS public.email_verification_pending (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token                text NOT NULL UNIQUE,
  target_email         text NOT NULL CHECK (target_email = lower(target_email)),
  requesting_member_id uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  purpose              text NOT NULL DEFAULT 'add_secondary_email',
  expires_at           timestamptz NOT NULL DEFAULT (now() + interval '24 hours'),
  consumed_at          timestamptz,
  dispatched_at        timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS email_verification_pending_token_idx ON public.email_verification_pending(token);
CREATE INDEX IF NOT EXISTS email_verification_pending_member_idx ON public.email_verification_pending(requesting_member_id);
CREATE INDEX IF NOT EXISTS email_verification_pending_expires_idx ON public.email_verification_pending(expires_at);

ALTER TABLE public.email_verification_pending ENABLE ROW LEVEL SECURITY;

-- Allow caller to SELECT only their own pending rows (so frontend can show "verification sent to X")
CREATE POLICY evp_select_own ON public.email_verification_pending
  FOR SELECT
  TO authenticated
  USING (requesting_member_id IN (SELECT id FROM public.members WHERE auth_id = (SELECT auth.uid())));

-- No INSERT/UPDATE/DELETE from authenticated. Only SECURITY DEFINER RPCs (which use postgres role) and service_role.

GRANT SELECT ON public.email_verification_pending TO authenticated;
GRANT ALL    ON public.email_verification_pending TO service_role;

COMMENT ON TABLE public.email_verification_pending IS
  'Pending email-ownership verifications for adding a secondary email to a member. Token-based, 24h TTL. P168 R4.';


-- 2) Trigger to lock direct writes to members.secondary_emails
CREATE OR REPLACE FUNCTION public._tg_lock_members_secondary_emails()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF OLD.secondary_emails IS DISTINCT FROM NEW.secondary_emails THEN
    -- Allow bypass via session-local flag set by trusted RPCs
    IF current_setting('app.bypass_secondary_emails_lock', true) = 'true' THEN
      RETURN NEW;
    END IF;
    -- Allow service_role (admin scripts, backfills, anonymization cron)
    IF (SELECT auth.role()) = 'service_role' THEN
      RETURN NEW;
    END IF;
    -- Allow superadmin (admin UI manual operations)
    IF EXISTS (SELECT 1 FROM public.members WHERE auth_id = (SELECT auth.uid()) AND is_superadmin = true) THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'members.secondary_emails can only be modified via request_secondary_email_verification + confirm_secondary_email or remove_secondary_email RPCs (P168 R4)';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_lock_members_secondary_emails ON public.members;
CREATE TRIGGER trg_lock_members_secondary_emails
  BEFORE UPDATE ON public.members
  FOR EACH ROW
  EXECUTE FUNCTION public._tg_lock_members_secondary_emails();

COMMENT ON FUNCTION public._tg_lock_members_secondary_emails() IS
  'Locks direct UPDATE on members.secondary_emails. Allowed paths: (a) trusted SECURITY DEFINER RPC sets session-local app.bypass_secondary_emails_lock=true; (b) service_role; (c) superadmin. P168 R4.';


-- 3) RPC: request verification (start the flow)
CREATE OR REPLACE FUNCTION public.request_secondary_email_verification(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id              uuid;
  v_caller_primary_email   text;
  v_caller_secondary_array text[];
  v_other_member           uuid;
  v_token                  text;
  v_pending_id             uuid;
  v_service_role_key       text;
  v_normalized_email       text;
BEGIN
  -- Resolve caller member
  SELECT id, email, COALESCE(secondary_emails, '{}'::text[])
    INTO v_caller_id, v_caller_primary_email, v_caller_secondary_array
    FROM public.members
   WHERE auth_id = (SELECT auth.uid())
   LIMIT 1;

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Normalize
  v_normalized_email := lower(trim(coalesce(p_email, '')));

  -- Basic email shape check
  IF v_normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid email format');
  END IF;

  -- Already this caller's primary?
  IF lower(coalesce(v_caller_primary_email,'')) = v_normalized_email THEN
    RETURN jsonb_build_object('success', false, 'error', 'Email is already your primary');
  END IF;

  -- Already in caller's secondary?
  IF v_normalized_email = ANY(SELECT lower(unnest(v_caller_secondary_array))) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Email is already in your secondary list');
  END IF;

  -- Collision: email belongs to another member (primary OR secondary)?
  SELECT id INTO v_other_member
    FROM public.members
   WHERE id <> v_caller_id
     AND (
       lower(coalesce(email,'')) = v_normalized_email
       OR v_normalized_email = ANY(SELECT lower(unnest(coalesce(secondary_emails, '{}'::text[]))))
     )
   LIMIT 1;

  IF v_other_member IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Email already linked to another member. Contact an admin if you believe this is wrong.');
  END IF;

  -- Generate token (32 random bytes hex = 64 chars)
  v_token := encode(gen_random_bytes(32), 'hex');

  INSERT INTO public.email_verification_pending(token, target_email, requesting_member_id, purpose)
  VALUES (v_token, v_normalized_email, v_caller_id, 'add_secondary_email')
  RETURNING id INTO v_pending_id;

  -- Fire-and-forget dispatch to EF
  BEGIN
    SELECT decrypted_secret INTO v_service_role_key
      FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

    IF v_service_role_key IS NOT NULL THEN
      PERFORM net.http_post(
        url     := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/send-email-verification',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_role_key
        ),
        body    := jsonb_build_object('token', v_token)
      );
    ELSE
      RAISE NOTICE 'request_secondary_email_verification: no service_role_key in vault, EF not dispatched (token still valid)';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Dispatch failure does not invalidate the token — admin can re-trigger via separate mechanism
    RAISE NOTICE 'request_secondary_email_verification dispatch failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success',      true,
    'target_email', v_normalized_email,
    'expires_at',   (SELECT expires_at FROM public.email_verification_pending WHERE id = v_pending_id),
    'pending_id',   v_pending_id
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.request_secondary_email_verification(text) TO authenticated;

COMMENT ON FUNCTION public.request_secondary_email_verification(text) IS
  'Start email verification flow to add a secondary email to caller member. Inserts pending row + dispatches send-email-verification EF. Token TTL 24h. P168 R4.';


-- 4) RPC: confirm the verification (consume token)
CREATE OR REPLACE FUNCTION public.confirm_secondary_email(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_pending     public.email_verification_pending%ROWTYPE;
  v_current     text[];
  v_new         text[];
BEGIN
  SELECT * INTO v_pending FROM public.email_verification_pending WHERE token = p_token LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid or unknown token');
  END IF;

  IF v_pending.consumed_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Token already used');
  END IF;

  IF v_pending.expires_at < now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Token expired');
  END IF;

  -- Bypass the lock trigger for this transaction
  PERFORM set_config('app.bypass_secondary_emails_lock', 'true', true);

  SELECT COALESCE(secondary_emails, '{}'::text[]) INTO v_current
    FROM public.members WHERE id = v_pending.requesting_member_id;

  -- Append + deduplicate (lowercase set semantics)
  SELECT array_agg(DISTINCT e ORDER BY e) INTO v_new
    FROM (
      SELECT lower(unnest(v_current)) AS e
      UNION
      SELECT v_pending.target_email
    ) s
    WHERE e IS NOT NULL AND length(e) > 0;

  UPDATE public.members
     SET secondary_emails = v_new,
         updated_at       = now()
   WHERE id = v_pending.requesting_member_id;

  UPDATE public.email_verification_pending
     SET consumed_at = now()
   WHERE id = v_pending.id;

  INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_pending.requesting_member_id,
    'members.secondary_emails.added_verified',
    'member',
    v_pending.requesting_member_id,
    jsonb_build_object('added_email', v_pending.target_email, 'verification_token_id', v_pending.id),
    jsonb_build_object('via', 'confirm_secondary_email', 'session', 'p168_r4')
  );

  RETURN jsonb_build_object('success', true, 'email', v_pending.target_email);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.confirm_secondary_email(text) TO authenticated;

COMMENT ON FUNCTION public.confirm_secondary_email(text) IS
  'Consume verification token to append target_email to caller member secondary_emails. Idempotent: token single-use. Bearer-token authorization (clicking the link confirms ownership of the target email). P168 R4.';


-- 5) RPC: remove a secondary email (direct, no email confirmation — PM choice)
CREATE OR REPLACE FUNCTION public.remove_secondary_email(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id        uuid;
  v_current          text[];
  v_normalized_email text;
  v_new              text[];
BEGIN
  SELECT id, COALESCE(secondary_emails, '{}'::text[])
    INTO v_caller_id, v_current
    FROM public.members
   WHERE auth_id = (SELECT auth.uid())
   LIMIT 1;

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  v_normalized_email := lower(trim(coalesce(p_email, '')));

  IF v_normalized_email = '' OR NOT (v_normalized_email = ANY(SELECT lower(unnest(v_current)))) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Email not in your secondary list');
  END IF;

  -- Bypass trigger
  PERFORM set_config('app.bypass_secondary_emails_lock', 'true', true);

  v_new := ARRAY(SELECT e FROM unnest(v_current) AS e WHERE lower(e) <> v_normalized_email);

  UPDATE public.members
     SET secondary_emails = v_new,
         updated_at       = now()
   WHERE id = v_caller_id;

  INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id,
    'members.secondary_emails.removed',
    'member',
    v_caller_id,
    jsonb_build_object('removed_email', v_normalized_email),
    jsonb_build_object('via', 'remove_secondary_email', 'session', 'p168_r4')
  );

  RETURN jsonb_build_object('success', true, 'removed', v_normalized_email);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.remove_secondary_email(text) TO authenticated;

COMMENT ON FUNCTION public.remove_secondary_email(text) IS
  'Remove a secondary email from caller member. No email confirmation required (PM choice — less dangerous than adding). P168 R4.';


NOTIFY pgrst, 'reload schema';
