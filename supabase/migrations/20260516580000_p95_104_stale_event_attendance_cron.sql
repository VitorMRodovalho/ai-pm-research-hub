-- p95 #104: stale event attendance cron + health RPC (Pattern 43 reuse)
-- ====================================================================
-- Daily cron: detect events past 24-48h with ZERO attendance marked → notify GP+deputy.
-- Líder pode então cancelar reunião (cancel button — separate UX work) OR mark presença.
-- Without this alert, members get auto-marked falta when nobody marks anything.
--
-- delivery_mode='digest_weekly' per ADR-0022 default — Saturday email accumulates list.
-- Smoke validated p95 2026-05-05: 3/3 checks pass, dry-run cron returns count of 24-48h stale.

CREATE OR REPLACE FUNCTION public.get_event_attendance_health()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT (can_by_member(v_member_id, 'view_internal_analytics') OR can_by_member(v_member_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Access denied — requires view_internal_analytics or view_chapter_dashboards';
  END IF;

  WITH stale AS (
    SELECT e.id, e.title, e.date, e.time_start, e.initiative_id,
           i.title AS initiative_title
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE e.date < CURRENT_DATE - 1
      AND e.date >= CURRENT_DATE - 14
      AND NOT EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id)
  )
  SELECT jsonb_build_object(
    'stale_events_no_attendance', (SELECT count(*) FROM stale),
    'oldest_stale_date', (SELECT min(date) FROM stale),
    'window_days', 14,
    'sample', (SELECT jsonb_agg(jsonb_build_object(
      'event_id', id, 'title', title, 'date', date, 'initiative_title', initiative_title
    ) ORDER BY date DESC) FROM (SELECT * FROM stale ORDER BY date DESC LIMIT 10) s),
    'computed_at', now()
  ) INTO v_result;

  RETURN v_result;
END $function$;

REVOKE EXECUTE ON FUNCTION public.get_event_attendance_health() FROM PUBLIC, anon;

COMMENT ON FUNCTION public.get_event_attendance_health() IS
  'p95 #104: health monitor for stale events past 24h with zero attendance. Pattern 43 reuse (invitation/LGPD/digest health monitors). Admin read-only.';

CREATE OR REPLACE FUNCTION public.detect_stale_events_cron()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count integer := 0;
  v_inserted integer := 0;
BEGIN
  SELECT count(*) INTO v_count
  FROM events e
  WHERE e.date BETWEEN CURRENT_DATE - 2 AND CURRENT_DATE - 1
    AND NOT EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id);

  IF v_count > 0 THEN
    INSERT INTO notifications (recipient_id, type, title, body, delivery_mode, created_at)
    SELECT m.id,
           'event_stale_no_attendance',
           format('%s evento(s) sem attendance marcado', v_count),
           format('%s evento(s) passado(s) há mais de 24h não tem nenhuma marcação de presença. Cancele se a reunião não aconteceu OU marque presença em /attendance.', v_count),
           'digest_weekly',
           now()
    FROM members m
    WHERE m.is_active = true
      AND m.operational_role IN ('manager', 'deputy_manager');
    GET DIAGNOSTICS v_inserted = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object(
    'stale_count', v_count,
    'notifications_inserted', v_inserted,
    'window_hours', 48,
    'run_at', now()
  );
END $function$;

REVOKE EXECUTE ON FUNCTION public.detect_stale_events_cron() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.detect_stale_events_cron() IS
  'p95 #104: cron-only RPC. Detect events past 24-48h with ZERO attendance, enqueue digest_weekly notification to GP+deputy. Smart-skip when 0 stale (per ADR-0022 W3 pattern).';

SELECT cron.schedule(
  'event-stale-attendance-daily',
  '0 14 * * *',
  $$SELECT public.detect_stale_events_cron();$$
);

NOTIFY pgrst, 'reload schema';
