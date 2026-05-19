-- p197c E1 (2026-05-19): extract_cv_text_batch was filtering by resume_url IS NOT NULL,
-- but post-p195 VEP sync writes PDFs to private storage bucket selection-resumes and
-- leaves resume_url NULL for new cycles. This commit was originally framed as a fix for
-- "40% of cycle4-2026 PDFs failing extraction" — investigation showed the real numbers:
--
-- - 35 apps total in cycle4-2026
-- - 21 with consent_ai_analysis_at populated (consent given) — 20 fully parsed, 1 invalid PDF
-- - 14 without consent (consent_pending) — extraction correctly SKIPPED per LGPD Art. 20
-- - 1 invalid PDF (Marcio Pimenta — unpdf raised "Invalid PDF structure", corrupted upload)
--
-- So the 40% was NOT pipeline failure — it was correct LGPD compliance (no consent =
-- no IA processing). However, this migration still ships because:
-- (a) it removes a latent bug — when any of the 14 give consent later, they'd be invisible
--     to the cron because of the resume_url filter (post-p195 syncs only populate
--     resume_storage_path).
-- (b) the EF extract-cv-text was patched in parallel to fetch from the storage bucket
--     (sb.storage.from('selection-resumes').download) when resume_storage_path is present,
--     falling back to resume_url only for legacy rows that pre-date p195.
--
-- Future-proofing for cycle5+ where resume_url will be NULL by default.

CREATE OR REPLACE FUNCTION public.extract_cv_text_batch(p_limit integer DEFAULT 10)
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
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'extract_cv_text_batch requires service_role context (called by cron)'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_limit < 1 OR p_limit > 100 THEN
    RAISE EXCEPTION 'p_limit must be between 1 and 100, got %', p_limit;
  END IF;

  SELECT decrypted_secret INTO v_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  IF v_key IS NULL THEN
    RAISE EXCEPTION 'service_role_key not in vault (extract_cv_text_batch)';
  END IF;

  -- p197c E1: include resume_storage_path OR resume_url (was: only resume_url)
  FOR v_app IN
    SELECT id
    FROM public.selection_applications
    WHERE consent_ai_analysis_at IS NOT NULL
      AND consent_ai_analysis_revoked_at IS NULL
      AND (resume_storage_path IS NOT NULL OR resume_url IS NOT NULL)
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

COMMENT ON FUNCTION public.extract_cv_text_batch(integer) IS
  'p197c E1 (2026-05-19): pickup filter now includes resume_storage_path (post-p195 VEP sync writes PDFs to private bucket selection-resumes) — was previously only resume_url, latent bug for cycle5+ where resume_url is NULL by default. EF extract-cv-text patched in parallel to prefer storage_path. service_role-gated (cron). Audit found 40% NULL cv_extracted_text in cycle4-2026 was due to LGPD compliance (14/35 without consent_ai_analysis_at), NOT pipeline failure — only 1 actual failure (Marcio Pimenta, corrupted PDF "Invalid PDF structure"). Migration ships as future-proofing.';
