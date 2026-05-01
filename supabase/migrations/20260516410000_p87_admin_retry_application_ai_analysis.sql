-- ============================================================================
-- p87 Sprint C.b — admin_retry_application_ai_analysis
-- ADR-0066 Amendment 2026-05-01 / Issue #117
-- ============================================================================
-- Permite manage_member dispatcher one-off retry do EF pmi-ai-analyze para
-- aplicação específica (não toca cron retry_pending_ai_analyses que filtra
-- ai_analysis IS NULL). Use case: backfill nova dimensão de schema AI
-- (raises_the_bar Sprint C) nos candidatos já analisados.
--
-- Auth: manage_member (admin/GP track only).
-- Vault: service_role_key required.
-- Triggered_by: 'admin_retry' (passes through to EF, which records in
--               ai_analysis_runs).
--
-- Rollback: DROP FUNCTION admin_retry_application_ai_analysis(uuid);
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_retry_application_ai_analysis(
  p_application_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_service_role_key text;
  v_dispatch_id bigint;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
    RAISE EXCEPTION 'Unauthorized: manage_member required';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  IF v_app.consent_ai_analysis_at IS NULL OR v_app.consent_ai_analysis_revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'Application has no active AI consent';
  END IF;

  SELECT decrypted_secret INTO v_service_role_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

  IF v_service_role_key IS NULL THEN
    RAISE EXCEPTION 'service_role_key not in vault';
  END IF;

  SELECT net.http_post(
    url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/pmi-ai-analyze',
    body := jsonb_build_object(
      'application_id', p_application_id,
      'triggered_by', 'admin_retry'
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_role_key
    )
  ) INTO v_dispatch_id;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'applicant_name', v_app.applicant_name,
    'dispatch_id', v_dispatch_id,
    'triggered_by', 'admin_retry',
    'dispatched_at', now()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_retry_application_ai_analysis(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_retry_application_ai_analysis(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
