-- ADR-0075 (p117 implementation): cv extraction pipeline.
-- RPC `extract_cv_text_batch` invoked by cron `extract-cv-text-15min`.
-- Picks up applications with consent + resume_url + missing cv_extracted_text.
-- Fires pg_net.http_post per app to extract-cv-text EF.
--
-- Rollback:
--   SELECT cron.unschedule('extract-cv-text-15min');
--   DROP FUNCTION IF EXISTS public.extract_cv_text_batch(int);

CREATE OR REPLACE FUNCTION public.extract_cv_text_batch(p_limit int DEFAULT 10)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_app RECORD;
  v_invoked int := 0;
  v_failed int := 0;
  v_skipped int := 0;
  v_url text := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/extract-cv-text';
  v_key text;
  v_dispatch_id bigint;
BEGIN
  -- Service-role gate (cron invokes as service_role; admin emergencies idem).
  -- Pattern matches ADR-0028 service_role bypass adapter.
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'extract_cv_text_batch requires service_role context (called by cron)'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_limit < 1 OR p_limit > 100 THEN
    RAISE EXCEPTION 'p_limit must be between 1 and 100, got %', p_limit;
  END IF;

  -- Read service_role_key from vault
  SELECT decrypted_secret INTO v_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  IF v_key IS NULL THEN
    RAISE EXCEPTION 'service_role_key not in vault (extract_cv_text_batch)';
  END IF;

  -- Pick up eligible applications. SKIP LOCKED protects against overlap if cron
  -- fires while previous run is still in flight (paranoia; cron is 15min, batch
  -- typically completes in <10s).
  FOR v_app IN
    SELECT id
    FROM public.selection_applications
    WHERE consent_ai_analysis_at IS NOT NULL
      AND consent_ai_analysis_revoked_at IS NULL
      AND resume_url IS NOT NULL
      AND (cv_extracted_text IS NULL OR length(cv_extracted_text) = 0)
    ORDER BY created_at DESC
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  LOOP
    BEGIN
      SELECT net.http_post(
        url := v_url,
        body := jsonb_build_object(
          'application_id', v_app.id,
          'triggered_by', 'cron'
        ),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_key
        )
      ) INTO v_dispatch_id;
      v_invoked := v_invoked + 1;
      -- Resend-style rate-limit guard (per project lesson p92)
      PERFORM pg_sleep(0.3);
    EXCEPTION WHEN OTHERS THEN
      v_failed := v_failed + 1;
      RAISE NOTICE 'extract-cv-text dispatch failed for app %: %', v_app.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'invoked', v_invoked,
    'failed', v_failed,
    'skipped', v_skipped,
    'limit', p_limit
  );
END;
$function$;

COMMENT ON FUNCTION public.extract_cv_text_batch(int) IS
  'p117 ADR-0075: pickup eligible selection_applications and dispatch extract-cv-text EF per app via pg_net. Service-role only (cron + admin). Returns counts.';

-- Schedule cron every 15 minutes
DO $$
DECLARE
  v_existing int;
BEGIN
  SELECT COUNT(*) INTO v_existing
  FROM cron.job WHERE jobname = 'extract-cv-text-15min';
  IF v_existing = 0 THEN
    PERFORM cron.schedule(
      'extract-cv-text-15min',
      '*/15 * * * *',
      $cmd$SELECT public.extract_cv_text_batch(p_limit := 10);$cmd$
    );
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
