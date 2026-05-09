-- p133 ARM-3 Triage automation: cron-based auto-triage on consent (p107 leftover, ADR-0074)
-- Driver: hoje analyze_application MCP tool requer chamada manual do admin para invocar
--         pmi-ai-triage EF. Sem cron, apps com consent ficam aguardando ação humana.
-- Pattern: copia retry_pending_ai_analyses (Gemini analyze cron). Sonnet 4.6 dispatch idêntico.
-- LGPD compliance: respeita consent_ai_analysis_revoked_at (purge handled by existing trigger).
-- Cadence: 15min (mesmo período do retry_pending_ai_analyses para consistency).

CREATE OR REPLACE FUNCTION public.retry_pending_ai_triages()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_app record;
  v_dispatched int := 0;
  v_skipped int := 0;
  v_service_role_key text;
  v_pending_count int;
BEGIN
  -- Eligible apps: consent granted, not revoked, not yet triaged, consent older than 5min (allow lazy extract)
  SELECT count(*) INTO v_pending_count
  FROM selection_applications
  WHERE consent_ai_analysis_at IS NOT NULL
    AND consent_ai_analysis_revoked_at IS NULL
    AND ai_triage_at IS NULL
    AND consent_ai_analysis_at < now() - interval '5 minutes';

  IF v_pending_count = 0 THEN
    RETURN jsonb_build_object('pending', 0, 'dispatched', 0);
  END IF;

  SELECT decrypted_secret INTO v_service_role_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

  IF v_service_role_key IS NULL THEN
    RETURN jsonb_build_object('error', 'no_service_role_key', 'pending', v_pending_count);
  END IF;

  FOR v_app IN
    SELECT id
    FROM selection_applications
    WHERE consent_ai_analysis_at IS NOT NULL
      AND consent_ai_analysis_revoked_at IS NULL
      AND ai_triage_at IS NULL
      AND consent_ai_analysis_at < now() - interval '5 minutes'
    ORDER BY consent_ai_analysis_at ASC
    LIMIT 50
  LOOP
    BEGIN
      PERFORM net.http_post(
        url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/pmi-ai-triage',
        body := jsonb_build_object('application_id', v_app.id),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_role_key
        )
      );
      v_dispatched := v_dispatched + 1;
    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      RAISE NOTICE 'retry_pending_ai_triages dispatch failed app_id=%: %', v_app.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'pending_total', v_pending_count,
    'dispatched', v_dispatched,
    'skipped', v_skipped,
    'limit_per_run', 50
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.retry_pending_ai_triages() TO authenticated;

-- Schedule cron every 15min (matches retry_pending_ai_analyses cadence)
DO $do$
DECLARE
  v_existing_jobid bigint;
  v_new_jobid bigint;
BEGIN
  SELECT jobid INTO v_existing_jobid FROM cron.job WHERE jobname='retry-pending-ai-triages';
  IF v_existing_jobid IS NOT NULL THEN
    PERFORM cron.unschedule(v_existing_jobid);
  END IF;

  v_new_jobid := cron.schedule(
    'retry-pending-ai-triages',
    '*/15 * * * *',
    'SELECT public.retry_pending_ai_triages();'
  );
  RAISE NOTICE 'Scheduled retry-pending-ai-triages jobid=%', v_new_jobid;
END $do$;

-- Audit entry recording the new automation
INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
VALUES (
  NULL,
  'cron_create',
  'cron.job',
  NULL,
  jsonb_build_object(
    'job_name', 'retry-pending-ai-triages',
    'schedule', '*/15 * * * *',
    'rationale', 'ARM-3 Triage automation per ADR-0074. Auto-dispatch pmi-ai-triage EF for applications with consent_ai_analysis_at NOT NULL AND ai_triage_at IS NULL. Decouples manual analyze_application MCP tool requirement.',
    'source', 'p133',
    'arm_pillar', 'ARM-3'
  )
);

NOTIFY pgrst, 'reload schema';
