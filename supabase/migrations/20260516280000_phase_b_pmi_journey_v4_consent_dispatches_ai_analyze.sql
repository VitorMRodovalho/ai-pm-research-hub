-- p82 CBGPL: when candidate gives consent via token, fire-and-forget dispatch
-- to pmi-ai-analyze EF. Async, non-blocking. Same pattern as welcome dispatch.
-- If dispatch fails, EXCEPTION caught and logged via RAISE NOTICE — consent still recorded.

CREATE OR REPLACE FUNCTION public.give_consent_via_token(
  p_token text,
  p_consent_type text DEFAULT 'ai_analysis'::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_application_id uuid;
  v_app selection_applications%ROWTYPE;
  v_service_role_key text;
  v_dispatch_request_id bigint;
BEGIN
  SELECT * INTO v_token_row
  FROM onboarding_tokens
  WHERE token = p_token
    AND expires_at > now()
    AND 'consent_giving' = ANY(scopes);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid token or missing consent_giving scope'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token_row.source_type <> 'pmi_application' THEN
    RAISE EXCEPTION 'Token source_type % does not support consent giving', v_token_row.source_type;
  END IF;

  v_application_id := v_token_row.source_id;

  IF p_consent_type <> 'ai_analysis' THEN
    RAISE EXCEPTION 'Unsupported consent type: % (only ai_analysis is supported)', p_consent_type;
  END IF;

  UPDATE selection_applications
     SET consent_ai_analysis_at = COALESCE(consent_ai_analysis_at, now()),
         consent_ai_analysis_revoked_at = NULL,
         updated_at = now()
   WHERE id = v_application_id
  RETURNING * INTO v_app;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Token references missing application';
  END IF;

  -- Fire-and-forget dispatch to pmi-ai-analyze EF (Phase C parcial).
  -- If EF call fails, consent still persists; we just log and continue.
  BEGIN
    SELECT decrypted_secret INTO v_service_role_key
    FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

    IF v_service_role_key IS NOT NULL THEN
      SELECT net.http_post(
        url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/pmi-ai-analyze',
        body := jsonb_build_object('application_id', v_application_id),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_role_key
        )
      ) INTO v_dispatch_request_id;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pmi-ai-analyze dispatch failed: % (application_id=%)', SQLERRM, v_application_id;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_application_id,
    'consent_type', p_consent_type,
    'consent_at', v_app.consent_ai_analysis_at,
    'has_consent', true,
    'has_revoked', false,
    'ai_analyze_dispatch_request_id', v_dispatch_request_id
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
