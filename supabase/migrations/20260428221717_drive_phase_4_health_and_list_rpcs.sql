-- ADR-0065 Drive Phase 4 — observability + list RPCs (Pattern 43 4th reuse).
-- get_drive_discovery_health: cron job state + counters + health signal.
-- list_drive_discoveries: paginated audit feed for review of unmatched/unpromoted discoveries.

CREATE OR REPLACE FUNCTION public.get_drive_discovery_health()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_total_discoveries integer;
  v_last_24h integer;
  v_unmatched integer;
  v_unpromoted_matched integer;
  v_minutes_folders_active integer;
  v_cron jsonb;
  v_days_since_run numeric;
  v_health text;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  SELECT count(*) INTO v_total_discoveries FROM public.drive_file_discoveries;
  SELECT count(*) INTO v_last_24h FROM public.drive_file_discoveries WHERE discovered_at >= now() - interval '24 hours';
  SELECT count(*) INTO v_unmatched FROM public.drive_file_discoveries WHERE matched_event_id IS NULL;
  SELECT count(*) INTO v_unpromoted_matched FROM public.drive_file_discoveries
    WHERE matched_event_id IS NOT NULL AND promoted_to_minutes_url = false;
  SELECT count(*) INTO v_minutes_folders_active FROM public.initiative_drive_links
    WHERE link_purpose = 'minutes' AND unlinked_at IS NULL;

  SELECT jsonb_build_object(
    'jobid', j.jobid,
    'schedule', j.schedule,
    'active', j.active,
    'last_run_at', (SELECT max(start_time) FROM cron.job_run_details d WHERE d.jobid = j.jobid),
    'last_status', (SELECT status FROM cron.job_run_details d WHERE d.jobid = j.jobid ORDER BY start_time DESC LIMIT 1),
    'last_message', (SELECT return_message FROM cron.job_run_details d WHERE d.jobid = j.jobid ORDER BY start_time DESC LIMIT 1),
    'last_5_status', (
      SELECT jsonb_agg(d2.status ORDER BY d2.start_time DESC)
      FROM (SELECT status, start_time FROM cron.job_run_details d2 WHERE d2.jobid = j.jobid ORDER BY d2.start_time DESC LIMIT 5) d2
    ),
    'failed_runs_last_30d', (
      SELECT count(*) FROM cron.job_run_details d
      WHERE d.jobid = j.jobid AND d.status = 'failed' AND d.start_time >= now() - interval '30 days'
    )
  )
  INTO v_cron
  FROM cron.job j WHERE j.jobname = 'drive-discover-atas-daily' LIMIT 1;

  SELECT extract(epoch FROM (now() - max(start_time))) / 86400
    INTO v_days_since_run
  FROM cron.job_run_details d
  WHERE d.jobid = (SELECT jobid FROM cron.job WHERE jobname = 'drive-discover-atas-daily' LIMIT 1);

  -- Health: green = ran within 36h (daily + 12h grace) AND no minutes folders OR has discoveries.
  -- Yellow = never ran yet OR no minutes folders configured (idle).
  -- Red = should have run but didn't OR cron returned failed last time.
  v_health := CASE
    WHEN v_minutes_folders_active = 0 THEN 'yellow'  -- nothing to scan; PM hasn't created /Atas folders yet
    WHEN v_cron IS NULL THEN 'red'  -- cron not registered
    WHEN v_days_since_run IS NULL THEN 'yellow'  -- registered but never fired
    WHEN v_days_since_run <= 1.5 AND v_cron->>'last_status' = 'succeeded' THEN 'green'
    WHEN v_days_since_run > 1.5 OR v_cron->>'last_status' = 'failed' THEN 'red'
    ELSE 'yellow'
  END;

  RETURN jsonb_build_object(
    'total_discoveries', v_total_discoveries,
    'discovered_last_24h', v_last_24h,
    'unmatched_discoveries', v_unmatched,
    'unpromoted_matched_discoveries', v_unpromoted_matched,
    'minutes_folders_active', v_minutes_folders_active,
    'cron', coalesce(v_cron, jsonb_build_object('registered', false)),
    'days_since_last_run', v_days_since_run,
    'health_signal', v_health,
    'note', 'Daily cron at 03:00 UTC. Yellow when no minutes folders linked yet (PM action needed: create /Atas subfolders + link_purpose=minutes via create_drive_subfolder).',
    'fetched_at', now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_drive_discovery_health() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_drive_discovery_health() TO authenticated;

COMMENT ON FUNCTION public.get_drive_discovery_health() IS
'ADR-0065 Pattern 43 4th reuse: Drive auto-discovery cron health + counters. Authority: view_internal_analytics. Health: green=ran <=36h ago + success, yellow=idle/no folders, red=>36h or failed last run.';

CREATE OR REPLACE FUNCTION public.list_drive_discoveries(
  p_initiative_id uuid DEFAULT NULL,
  p_status_filter text DEFAULT 'all',  -- all | unmatched | unpromoted | promoted
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_rows jsonb;
  v_total integer;
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;
  IF p_status_filter NOT IN ('all', 'unmatched', 'unpromoted', 'promoted') THEN
    RETURN jsonb_build_object('error', 'Invalid status_filter. Use: all | unmatched | unpromoted | promoted');
  END IF;

  WITH base AS (
    SELECT d.*, l.initiative_id
    FROM public.drive_file_discoveries d
    INNER JOIN public.initiative_drive_links l ON l.id = d.initiative_drive_link_id
    WHERE (p_initiative_id IS NULL OR l.initiative_id = p_initiative_id)
      AND (
        p_status_filter = 'all'
        OR (p_status_filter = 'unmatched' AND d.matched_event_id IS NULL)
        OR (p_status_filter = 'unpromoted' AND d.matched_event_id IS NOT NULL AND d.promoted_to_minutes_url = false)
        OR (p_status_filter = 'promoted' AND d.promoted_to_minutes_url = true)
      )
  )
  SELECT count(*) INTO v_total FROM base;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', d.id,
    'initiative_id', l.initiative_id,
    'initiative_title', i.title,
    'drive_folder_name', l.drive_folder_name,
    'drive_file_id', d.drive_file_id,
    'drive_file_url', d.drive_file_url,
    'filename', d.filename,
    'mime_type', d.mime_type,
    'size_bytes', d.size_bytes,
    'drive_modified_at', d.drive_modified_at,
    'discovered_at', d.discovered_at,
    'matched_event_id', d.matched_event_id,
    'matched_event_title', e.title,
    'matched_event_date', e.date,
    'match_strategy', d.match_strategy,
    'match_confidence', d.match_confidence,
    'promoted_to_minutes_url', d.promoted_to_minutes_url,
    'promoted_at', d.promoted_at,
    'promoted_by_name', m.name
  ) ORDER BY d.discovered_at DESC), '[]'::jsonb)
  INTO v_rows
  FROM public.drive_file_discoveries d
  INNER JOIN public.initiative_drive_links l ON l.id = d.initiative_drive_link_id
  LEFT JOIN public.initiatives i ON i.id = l.initiative_id
  LEFT JOIN public.events e ON e.id = d.matched_event_id
  LEFT JOIN public.members m ON m.id = d.promoted_by
  WHERE (p_initiative_id IS NULL OR l.initiative_id = p_initiative_id)
    AND (
      p_status_filter = 'all'
      OR (p_status_filter = 'unmatched' AND d.matched_event_id IS NULL)
      OR (p_status_filter = 'unpromoted' AND d.matched_event_id IS NOT NULL AND d.promoted_to_minutes_url = false)
      OR (p_status_filter = 'promoted' AND d.promoted_to_minutes_url = true)
    )
  ORDER BY d.discovered_at DESC
  LIMIT v_limit OFFSET v_offset;

  RETURN jsonb_build_object(
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset,
    'discoveries', v_rows,
    'fetched_at', now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_drive_discoveries(uuid, text, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_drive_discoveries(uuid, text, integer, integer) TO authenticated;

COMMENT ON FUNCTION public.list_drive_discoveries(uuid, text, integer, integer) IS
'ADR-0065 Drive Phase 4: paginated audit feed for drive_file_discoveries. Filters: initiative_id (optional), status_filter (all|unmatched|unpromoted|promoted). Authority: view_internal_analytics.';

NOTIFY pgrst, 'reload schema';
