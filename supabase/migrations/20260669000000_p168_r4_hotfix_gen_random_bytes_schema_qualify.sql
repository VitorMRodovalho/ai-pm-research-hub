-- P168 R4 hotfix: pgcrypto.gen_random_bytes lives in `extensions` schema, not on the
-- default `public, pg_temp` search_path used by the SECURITY DEFINER RPC. Smoke caught
-- it before deploy. Fully qualify the call.

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
  SELECT id, email, COALESCE(secondary_emails, '{}'::text[])
    INTO v_caller_id, v_caller_primary_email, v_caller_secondary_array
    FROM public.members
   WHERE auth_id = (SELECT auth.uid())
   LIMIT 1;

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  v_normalized_email := lower(trim(coalesce(p_email, '')));

  IF v_normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid email format');
  END IF;

  IF lower(coalesce(v_caller_primary_email,'')) = v_normalized_email THEN
    RETURN jsonb_build_object('success', false, 'error', 'Email is already your primary');
  END IF;

  IF v_normalized_email = ANY(SELECT lower(unnest(v_caller_secondary_array))) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Email is already in your secondary list');
  END IF;

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

  -- Schema-qualify pgcrypto call (extensions schema not in search_path)
  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  INSERT INTO public.email_verification_pending(token, target_email, requesting_member_id, purpose)
  VALUES (v_token, v_normalized_email, v_caller_id, 'add_secondary_email')
  RETURNING id INTO v_pending_id;

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

NOTIFY pgrst, 'reload schema';
