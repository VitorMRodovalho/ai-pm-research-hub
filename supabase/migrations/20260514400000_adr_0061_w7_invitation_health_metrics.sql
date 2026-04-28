-- ADR-0061 W7: Invitation health metrics RPC
-- Closes #88 observability gap: pre-W7 the only signal for cron breakage was
-- pg_cron.job_run_details, which is not surfaceable to admins via MCP. This
-- exposes invitation status counts + stale-pending-past-1h-of-expiry as a
-- single jsonb response so admins can spot cron silence quickly.
-- Authority: view_internal_analytics (org-wide audit-scope).
-- Rollback: DROP FUNCTION public.get_invitation_health();

CREATE OR REPLACE FUNCTION public.get_invitation_health()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_member_id uuid;
  v_counts jsonb;
  v_stale integer;
  v_last_cron jsonb;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();

  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT public.can_by_member(v_caller_member_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  SELECT jsonb_build_object(
    'pending', count(*) FILTER (WHERE status='pending'),
    'accepted', count(*) FILTER (WHERE status='accepted'),
    'declined', count(*) FILTER (WHERE status='declined'),
    'expired', count(*) FILTER (WHERE status='expired'),
    'revoked', count(*) FILTER (WHERE status='revoked'),
    'canceled', count(*) FILTER (WHERE status='canceled'),
    'total', count(*),
    'expired_last_7_days', count(*) FILTER (WHERE status='expired' AND created_at >= now() - interval '7 days'),
    'created_last_24h', count(*) FILTER (WHERE created_at >= now() - interval '24 hours')
  )
  INTO v_counts
  FROM public.initiative_invitations;

  -- Stale: any pending invitation past expires_at + 1h grace (cron should've caught it)
  SELECT count(*) INTO v_stale
  FROM public.initiative_invitations
  WHERE status='pending' AND expires_at < now() - interval '1 hour';

  -- Last cron run (succeeded/failed), if accessible
  SELECT jsonb_build_object(
    'last_run_at', max(start_time),
    'last_status', (
      SELECT status FROM cron.job_run_details d
      WHERE d.jobid = j.jobid ORDER BY start_time DESC LIMIT 1
    ),
    'last_5_status', (
      SELECT jsonb_agg(jsonb_build_object('start', start_time, 'status', status, 'msg', return_message) ORDER BY start_time DESC)
      FROM (
        SELECT start_time, status, return_message
        FROM cron.job_run_details d2
        WHERE d2.jobid = j.jobid
        ORDER BY start_time DESC
        LIMIT 5
      ) t
    )
  )
  INTO v_last_cron
  FROM cron.job j
  LEFT JOIN cron.job_run_details d ON d.jobid = j.jobid
  WHERE j.jobname = 'expire-stale-invitations-hourly'
  GROUP BY j.jobid;

  RETURN jsonb_build_object(
    'counts', v_counts,
    'stale_pending_past_expires_grace_1h', v_stale,
    'cron', coalesce(v_last_cron, jsonb_build_object('error', 'cron job not found')),
    'health_signal', CASE
      WHEN v_stale = 0 THEN 'green'
      WHEN v_stale < 5 THEN 'yellow'
      ELSE 'red'
    END,
    'fetched_at', now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_invitation_health() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_invitation_health() TO authenticated;

COMMENT ON FUNCTION public.get_invitation_health() IS
'ADR-0061 W7: Invitation health snapshot for admins. Returns status counts, stale-pending-past-expiry (>1h grace = cron silence), last cron firings. Authority: view_internal_analytics. Health signal green if 0 stale, yellow if <5, red otherwise.';

NOTIFY pgrst, 'reload schema';
