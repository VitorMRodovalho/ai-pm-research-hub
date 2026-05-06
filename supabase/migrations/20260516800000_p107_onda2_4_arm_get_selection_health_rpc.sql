-- ARM Onda 2.4: get_selection_health RPC — Pattern 43 W7/W8/W9 saturation
--
-- Health observability para o pilar de Aquisição de Recursos. Segue padrão
-- get_invitation_health (W7) + get_lgpd_cron_health (W8) + get_digest_health (W9).
--
-- Surface:
--   - active_cycle: estado do ciclo ativo (id, code, status, created_at)
--   - application_counts: total + por estágio (kanban-like)
--   - stale_tokens_48h: onboarding_tokens não consumidos há >48h (deveriam ter sido)
--   - welcome_backlog: applications approved sem welcome dispatched
--   - crons[]: array de cron status com last_run_at / last_status / last_5_status
--   - health_signal: green | yellow | red baseado em stale + crons
--   - fetched_at
--
-- Crons monitorados:
--   - send-notification-emails (*/5min) — drain de notifications transactional
--   - retry-pending-ai-analyses (hourly) — retry de ai_analysis_runs failed
--   - nudge-reschedule-pending-daily — interview reschedule nudges
--   - detect-onboarding-overdue-daily — overdue SLA marker (Onda 1 #139)
--
-- Auth: requires view_internal_analytics (mesmo de get_selection_dashboard).

CREATE OR REPLACE FUNCTION public.get_selection_health()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_caller_id uuid;
  v_active_cycle jsonb;
  v_application_counts jsonb;
  v_stale_tokens integer;
  v_welcome_backlog integer;
  v_crons jsonb;
  v_health_signal text;
  v_critical_cron_down boolean := false;
  v_cron_names text[] := ARRAY[
    'send-notification-emails',
    'retry-pending-ai-analyses',
    'nudge-reschedule-pending-daily',
    'detect-onboarding-overdue-daily'
  ];
  v_cron_name text;
  v_cron_data jsonb;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  -- Active cycle
  SELECT jsonb_build_object(
    'id', c.id,
    'cycle_code', c.cycle_code,
    'title', c.title,
    'status', c.status,
    'phase', c.phase,
    'created_at', c.created_at
  )
  INTO v_active_cycle
  FROM public.selection_cycles c
  ORDER BY c.created_at DESC
  LIMIT 1;

  -- Application counts no ciclo ativo
  SELECT jsonb_build_object(
    'total', count(*),
    'submitted', count(*) FILTER (WHERE status='submitted'),
    'screening', count(*) FILTER (WHERE status='screening'),
    'objective_eval', count(*) FILTER (WHERE status='objective_eval'),
    'interview_pending', count(*) FILTER (WHERE status='interview_pending'),
    'interview_scheduled', count(*) FILTER (WHERE status='interview_scheduled'),
    'interview_done', count(*) FILTER (WHERE status='interview_done'),
    'final_eval', count(*) FILTER (WHERE status='final_eval'),
    'approved', count(*) FILTER (WHERE status IN ('approved','converted')),
    'rejected', count(*) FILTER (WHERE status IN ('rejected','objective_cutoff')),
    'cancelled', count(*) FILTER (WHERE status IN ('cancelled','withdrawn')),
    'waitlist', count(*) FILTER (WHERE status='waitlist'),
    'created_last_7d', count(*) FILTER (WHERE created_at >= now() - interval '7 days')
  )
  INTO v_application_counts
  FROM public.selection_applications
  WHERE cycle_id = (v_active_cycle->>'id')::uuid;

  -- Stale tokens: onboarding_tokens não consumidos há >48h
  SELECT count(*) INTO v_stale_tokens
  FROM public.onboarding_tokens t
  JOIN public.selection_applications a ON a.id = t.source_id
  WHERE t.source_type = 'pmi_application'
    AND COALESCE(t.access_count, 0) = 0
    AND t.created_at < now() - interval '48 hours'
    AND a.cycle_id = (v_active_cycle->>'id')::uuid;

  -- Welcome backlog: approved sem token consumed (proxy para welcome não dispatched)
  SELECT count(*) INTO v_welcome_backlog
  FROM public.selection_applications a
  WHERE a.cycle_id = (v_active_cycle->>'id')::uuid
    AND a.status IN ('approved','converted')
    AND NOT EXISTS (
      SELECT 1 FROM public.onboarding_tokens t
      WHERE t.source_id = a.id AND t.source_type = 'pmi_application' AND COALESCE(t.access_count, 0) > 0
    );

  -- Cron health para cada cron relevante
  v_crons := '[]'::jsonb;
  FOREACH v_cron_name IN ARRAY v_cron_names LOOP
    SELECT jsonb_build_object(
      'jobname', v_cron_name,
      'active', j.active,
      'schedule', j.schedule,
      'last_run_at', (
        SELECT max(start_time) FROM cron.job_run_details d WHERE d.jobid = j.jobid
      ),
      'last_status', (
        SELECT status FROM cron.job_run_details d WHERE d.jobid = j.jobid
        ORDER BY start_time DESC LIMIT 1
      ),
      'last_5_status', (
        SELECT jsonb_agg(jsonb_build_object('start', start_time, 'status', status, 'msg', return_message) ORDER BY start_time DESC)
        FROM (
          SELECT start_time, status, return_message FROM cron.job_run_details d2
          WHERE d2.jobid = j.jobid ORDER BY start_time DESC LIMIT 5
        ) t
      )
    )
    INTO v_cron_data
    FROM cron.job j
    WHERE j.jobname = v_cron_name;

    IF v_cron_data IS NULL THEN
      v_cron_data := jsonb_build_object(
        'jobname', v_cron_name,
        'active', false,
        'error', 'cron job not registered'
      );
      -- Critical: 4 monitored crons, all should exist
      v_critical_cron_down := true;
    END IF;

    v_crons := v_crons || jsonb_build_array(v_cron_data);
  END LOOP;

  -- Health signal
  v_health_signal := CASE
    WHEN v_critical_cron_down OR v_stale_tokens >= 5 THEN 'red'
    WHEN v_stale_tokens > 0 OR v_welcome_backlog > 0 THEN 'yellow'
    ELSE 'green'
  END;

  RETURN jsonb_build_object(
    'active_cycle', COALESCE(v_active_cycle, jsonb_build_object('error', 'no cycle found')),
    'application_counts', v_application_counts,
    'stale_tokens_48h', v_stale_tokens,
    'welcome_backlog', v_welcome_backlog,
    'crons', v_crons,
    'health_signal', v_health_signal,
    'fetched_at', now()
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.get_selection_health() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_selection_health() TO authenticated;

COMMENT ON FUNCTION public.get_selection_health() IS
  'ARM Onda 2.4: Pattern 43 saturation (W7/W8/W9 + W10). Health observability do funil de seleção: ciclo ativo, counts por estágio, stale tokens >48h, welcome backlog, status dos 4 crons relevantes (send-notification-emails, retry-pending-ai-analyses, nudge-reschedule-pending-daily, detect-onboarding-overdue-daily). Auth: view_internal_analytics. Retorna health_signal red/yellow/green.';

NOTIFY pgrst, 'reload schema';
