-- p82 CBGPL launch observability: real-time metrics RPC for monitoring
-- during and after the 18h Ricardo Vargas QR code reveal.
-- Surfaces health of the entire PMI Journey v4 pipeline:
-- ingest → welcome → portal → consent → AI analysis → video/interview.

CREATE OR REPLACE FUNCTION public.get_pmi_launch_health(p_cycle_code text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_today_start timestamptz := date_trunc('day', now() AT TIME ZONE 'America/Sao_Paulo') AT TIME ZONE 'America/Sao_Paulo';
  v_cycle_filter uuid := NULL;
  v_result jsonb;
  v_dispatch_last timestamptz;
  v_retry_ai_last timestamptz;
BEGIN
  IF p_cycle_code IS NOT NULL THEN
    SELECT id INTO v_cycle_filter FROM selection_cycles WHERE cycle_code = p_cycle_code;
  END IF;

  SELECT max(start_time) INTO v_dispatch_last
  FROM cron.job_run_details jrd
  JOIN cron.job j ON j.jobid = jrd.jobid
  WHERE j.jobname = 'dispatch-pending-emails' AND jrd.start_time > now() - interval '24 hours';

  SELECT max(start_time) INTO v_retry_ai_last
  FROM cron.job_run_details jrd
  JOIN cron.job j ON j.jobid = jrd.jobid
  WHERE j.jobname = 'retry-pending-ai-analyses' AND jrd.start_time > now() - interval '24 hours';

  WITH
  apps AS (
    SELECT * FROM selection_applications
    WHERE (v_cycle_filter IS NULL OR cycle_id = v_cycle_filter)
  ),
  welcomes AS (
    SELECT
      cs.id, cs.created_at, cs.status,
      cr.delivered, cr.delivered_at
    FROM campaign_sends cs
    LEFT JOIN campaign_recipients cr ON cr.send_id = cs.id
    WHERE cs.created_at >= v_today_start
  ),
  app_metrics AS (
    SELECT
      count(*) AS total,
      count(*) FILTER (WHERE created_at >= v_today_start) AS today,
      count(*) FILTER (WHERE status = 'submitted') AS submitted,
      count(*) FILTER (WHERE status = 'screening') AS screening,
      count(*) FILTER (WHERE status = 'interview_pending') AS interview_pending,
      count(*) FILTER (WHERE status = 'interview_scheduled') AS interview_scheduled,
      count(*) FILTER (WHERE status = 'interview_done') AS interview_done,
      count(*) FILTER (WHERE status = 'approved') AS approved,
      count(*) FILTER (WHERE status = 'rejected') AS rejected,
      count(*) FILTER (WHERE status = 'withdrawn') AS withdrawn,
      count(*) FILTER (WHERE consent_ai_analysis_at IS NOT NULL AND consent_ai_analysis_revoked_at IS NULL) AS consent_active,
      count(*) FILTER (WHERE consent_ai_analysis_revoked_at IS NOT NULL) AS consent_revoked,
      count(*) FILTER (WHERE ai_analysis IS NOT NULL) AS ai_analyzed,
      count(*) FILTER (WHERE consent_ai_analysis_at IS NOT NULL AND consent_ai_analysis_revoked_at IS NULL AND ai_analysis IS NULL) AS ai_pending,
      count(*) FILTER (WHERE linkedin_url IS NOT NULL) AS profile_with_linkedin,
      count(*) FILTER (WHERE credly_url IS NOT NULL) AS profile_with_credly,
      count(*) FILTER (WHERE phone IS NOT NULL) AS profile_with_phone
    FROM apps
  ),
  welcome_metrics AS (
    SELECT
      count(*) AS today_total,
      count(*) FILTER (WHERE delivered = true) AS today_delivered,
      count(*) FILTER (WHERE delivered = false AND status NOT IN ('failed','throttled')) AS today_pending,
      count(*) FILTER (WHERE status = 'failed') AS today_failed,
      count(*) FILTER (WHERE status = 'throttled') AS today_throttled
    FROM welcomes
  ),
  video_metrics AS (
    SELECT
      count(DISTINCT vs.application_id) AS apps_with_videos,
      count(*) FILTER (WHERE vs.status = 'uploaded') AS uploaded,
      count(*) FILTER (WHERE vs.status = 'transcribed') AS transcribed,
      count(*) FILTER (WHERE vs.status = 'opted_out') AS opted_out,
      count(*) FILTER (WHERE vs.status = 'failed') AS failed
    FROM pmi_video_screenings vs
    WHERE EXISTS (SELECT 1 FROM apps a WHERE a.id = vs.application_id)
  )
  SELECT jsonb_build_object(
    'cycle_code', p_cycle_code,
    'as_of', now(),
    'today_start_brt', v_today_start,
    'applications', jsonb_build_object(
      'total', a.total,
      'today_new', a.today,
      'by_status', jsonb_build_object(
        'submitted', a.submitted,
        'screening', a.screening,
        'interview_pending', a.interview_pending,
        'interview_scheduled', a.interview_scheduled,
        'interview_done', a.interview_done,
        'approved', a.approved,
        'rejected', a.rejected,
        'withdrawn', a.withdrawn
      ),
      'consent_active', a.consent_active,
      'consent_revoked', a.consent_revoked,
      'ai_analyzed', a.ai_analyzed,
      'ai_pending', a.ai_pending,
      'profile_with_linkedin', a.profile_with_linkedin,
      'profile_with_credly', a.profile_with_credly,
      'profile_with_phone', a.profile_with_phone
    ),
    'welcomes_today', jsonb_build_object(
      'total', w.today_total,
      'delivered', w.today_delivered,
      'pending', w.today_pending,
      'failed', w.today_failed,
      'throttled', w.today_throttled,
      'remaining_daily_budget', GREATEST(0, 100 - w.today_delivered)
    ),
    'video_screenings', jsonb_build_object(
      'apps_with_screenings', v.apps_with_videos,
      'uploaded', v.uploaded,
      'transcribed', v.transcribed,
      'opted_out_for_interview', v.opted_out,
      'failed', v.failed
    ),
    'cron_health', jsonb_build_object(
      'dispatch_emails_last_run', v_dispatch_last,
      'retry_ai_last_run', v_retry_ai_last
    )
  )
  INTO v_result
  FROM app_metrics a, welcome_metrics w, video_metrics v;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_pmi_launch_health(text) TO service_role, authenticated;

NOTIFY pgrst, 'reload schema';
