-- WS-B: self-service account claim for guests whose login email differs from the
-- email they applied with (VEP). Such a guest authenticates but matches no member
-- (get_member_by_auth Step 3 only matches the primary email), so the platform shows
-- "Conta não cadastrada" with no way out. This adds a verification-gated claim flow.
--
-- SECURITY INVARIANT (the R3-a / Paulo Alves hijack lesson): proof-of-possession is
-- ALWAYS sent to the MEMBER's registered email — never to the claimant's address or
-- session. Only someone who controls the member's inbox can complete the claim.
-- Rollback: DROP FUNCTION request_account_claim(text), confirm_account_claim(text);
--   DROP CONSTRAINT email_verification_pending_purpose_shape_check;
--   ALTER COLUMN requesting_member_id SET NOT NULL; DROP COLUMN claiming_auth_id, target_member_id.

-- 1. Reuse email_verification_pending for the new purpose.
ALTER TABLE public.email_verification_pending
  ADD COLUMN IF NOT EXISTS claiming_auth_id uuid,
  ADD COLUMN IF NOT EXISTS target_member_id uuid REFERENCES public.members(id) ON DELETE CASCADE;

ALTER TABLE public.email_verification_pending ALTER COLUMN requesting_member_id DROP NOT NULL;

ALTER TABLE public.email_verification_pending
  DROP CONSTRAINT IF EXISTS email_verification_pending_purpose_shape_check;
ALTER TABLE public.email_verification_pending
  ADD CONSTRAINT email_verification_pending_purpose_shape_check CHECK (
    (purpose = 'account_claim'
       AND target_member_id IS NOT NULL
       AND claiming_auth_id IS NOT NULL
       AND requesting_member_id IS NULL)
    OR (purpose <> 'account_claim' AND requesting_member_id IS NOT NULL)
  );

-- 2. request_account_claim: a guest-with-session names the email/PMI-ID they applied
-- with; if it maps to an UNCLAIMED member, we send a proof-of-possession email to that
-- member's registered address. Returns a generic message either way (anti-enumeration).
CREATE OR REPLACE FUNCTION public.request_account_claim(p_identifier text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid               uuid := auth.uid();
  v_norm              text;
  v_target_member_id  uuid;
  v_target_email      text;
  v_recent_by_caller  int;
  v_recent_by_target  int;
  v_token             text;
  v_service_role_key  text;
  -- identical shape whether or not a match exists → no account enumeration
  v_generic jsonb := jsonb_build_object(
    'success', true,
    'message', 'Se o identificador corresponder a uma conta pendente, enviamos um e-mail de verificação ao endereço cadastrado dela (o que você usou na candidatura). Verifique sua caixa de entrada.'
  );
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'not_authenticated');
  END IF;

  -- Already linked (primary or admin-curated secondary)? Nothing to claim.
  IF EXISTS (SELECT 1 FROM public.members WHERE auth_id = v_uid)
     OR EXISTS (SELECT 1 FROM public.members WHERE v_uid = ANY(COALESCE(secondary_auth_ids, '{}'::uuid[]))) THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_linked');
  END IF;

  v_norm := lower(trim(coalesce(p_identifier, '')));
  IF v_norm = '' THEN
    RETURN jsonb_build_object('success', false, 'reason', 'invalid_identifier');
  END IF;

  -- Rate limit per caller (about own auth → safe to report).
  SELECT count(*) INTO v_recent_by_caller
    FROM public.email_verification_pending
   WHERE purpose = 'account_claim' AND claiming_auth_id = v_uid
     AND created_at > now() - interval '1 hour';
  IF v_recent_by_caller >= 3 THEN
    RETURN jsonb_build_object('success', false, 'reason', 'rate_limited');
  END IF;

  -- Resolve an UNCLAIMED member by VEP email (primary or secondary) or PMI id.
  SELECT id, email INTO v_target_member_id, v_target_email
    FROM public.members
   WHERE auth_id IS NULL
     AND (
       lower(coalesce(email, '')) = v_norm
       OR v_norm = ANY(SELECT lower(unnest(coalesce(secondary_emails, '{}'::text[]))))
       OR lower(coalesce(pmi_id, '')) = v_norm
     )
   ORDER BY (lower(coalesce(email, '')) = v_norm) DESC
   LIMIT 1;

  -- No unclaimed match, or no email to send proof to → generic (do not reveal).
  IF v_target_member_id IS NULL OR coalesce(v_target_email, '') = '' THEN
    RETURN v_generic;
  END IF;

  -- Rate limit per target member (anti-spam toward a victim's inbox).
  SELECT count(*) INTO v_recent_by_target
    FROM public.email_verification_pending
   WHERE purpose = 'account_claim' AND target_member_id = v_target_member_id
     AND created_at > now() - interval '1 hour';
  IF v_recent_by_target >= 3 THEN
    RETURN v_generic;  -- silently throttle; do not reveal the member exists
  END IF;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  -- requesting_member_id omitted (NULL) on purpose: account_claim has no requesting
  -- member; the CHECK constraint enforces it must be NULL for this purpose.
  INSERT INTO public.email_verification_pending(
    token, target_email, target_member_id, claiming_auth_id, purpose, expires_at
  ) VALUES (
    v_token, lower(v_target_email), v_target_member_id, v_uid, 'account_claim', now() + interval '1 hour'
  );

  -- Dispatch proof-of-possession email to the MEMBER's address.
  BEGIN
    SELECT decrypted_secret INTO v_service_role_key
      FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
    IF v_service_role_key IS NOT NULL THEN
      PERFORM net.http_post(
        url     := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/send-account-claim',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_role_key
        ),
        body    := jsonb_build_object('token', v_token)
      );
    ELSE
      RAISE NOTICE 'request_account_claim: no service_role_key in vault, EF not dispatched (token still valid)';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'request_account_claim dispatch failed: %', SQLERRM;
  END;

  RETURN v_generic;
END;
$function$;

-- 3. confirm_account_claim: token-only (the token IS the credential, delivered only to
-- the member's inbox). Links the original claimant's auth to the member. Revalidates
-- unclaimed state at confirm time (TOCTOU). Can be called without a session.
CREATE OR REPLACE FUNCTION public.confirm_account_claim(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_pending public.email_verification_pending%ROWTYPE;
  v_member  public.members%ROWTYPE;
BEGIN
  SELECT * INTO v_pending
    FROM public.email_verification_pending
   WHERE token = p_token AND purpose = 'account_claim'
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'reason', 'invalid');
  END IF;
  IF v_pending.consumed_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_used');
  END IF;
  IF v_pending.expires_at < now() THEN
    RETURN jsonb_build_object('success', false, 'reason', 'expired');
  END IF;

  -- Defense: never write a NULL auth_id (would UNLINK an existing member). The CHECK
  -- constraint already guarantees this for account_claim rows; belt-and-suspenders.
  IF v_pending.claiming_auth_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'invalid');
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = v_pending.target_member_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'reason', 'invalid');
  END IF;

  -- TOCTOU: the target must still be unclaimed (another claim may have won the race).
  IF v_member.auth_id IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_claimed');
  END IF;

  -- Atomic guard against a concurrent confirm: only link if still unclaimed.
  UPDATE public.members
     SET auth_id = v_pending.claiming_auth_id, updated_at = now()
   WHERE id = v_member.id AND auth_id IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_claimed');
  END IF;

  -- Mirror the persons.auth_id sync done by get_member_by_auth / try_auto_link_ghost.
  UPDATE public.persons
     SET auth_id = v_pending.claiming_auth_id
   WHERE legacy_member_id = v_member.id
     AND (auth_id IS NULL OR auth_id <> v_pending.claiming_auth_id);

  UPDATE public.email_verification_pending SET consumed_at = now() WHERE id = v_pending.id;

  INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_member.id,
    'members.auth_id.claimed_self_service',
    'member',
    v_member.id,
    jsonb_build_object('linked_auth_id', v_pending.claiming_auth_id, 'matched_via', 'account_claim'),
    jsonb_build_object('via', 'confirm_account_claim', 'pending_id', v_pending.id)
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.request_account_claim(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_account_claim(text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.confirm_account_claim(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirm_account_claim(text) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
