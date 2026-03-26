-- Migration: pg_cron wrapper functions for H4-1 notifications automation
-- These functions bypass auth.uid() (NULL in pg_cron context) and are NOT
-- callable via PostgREST — only by postgres/superuser (pg_cron).

-- =============================================================================
-- 1. CRON WRAPPER: detect_and_notify_detractors_cron
-- Finds members with 0 attendance in last 21 days, notifies GP + tribe leaders.
-- Deduplicates: skips if same detractor→leader notification exists within 7 days.
-- Schedule: weekly (Mondays 11:00 BRT = 14:00 UTC)
-- =============================================================================
DROP FUNCTION IF EXISTS detect_and_notify_detractors_cron();
CREATE FUNCTION public.detect_and_notify_detractors_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count int := 0;
  v_member record;
  v_leader record;
BEGIN
  -- No auth check — designed exclusively for pg_cron (postgres role)

  FOR v_member IN
    SELECT m.id, m.name, m.tribe_id
    FROM members m
    WHERE m.is_active = true
    AND m.current_cycle_active = true
    AND m.operational_role NOT IN ('sponsor', 'chapter_liaison')
    AND NOT EXISTS (
      SELECT 1 FROM attendance a
      JOIN events e ON a.event_id = e.id
      WHERE a.member_id = m.id AND a.present = true
      AND e.date >= (now() - interval '21 days')::date
    )
    AND EXISTS (
      SELECT 1 FROM events e
      WHERE e.date >= (now() - interval '21 days')::date
      AND (e.type IN ('geral', 'tribo') OR e.tribe_id = m.tribe_id)
    )
  LOOP
    FOR v_leader IN
      SELECT m2.id FROM members m2
      WHERE m2.is_active = true AND (
        m2.is_superadmin = true
        OR m2.operational_role IN ('manager', 'deputy_manager')
        OR (m2.operational_role = 'tribe_leader' AND m2.tribe_id = v_member.tribe_id)
      )
    LOOP
      IF NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.recipient_id = v_leader.id
        AND n.type = 'attendance_detractor'
        AND n.source_id = v_member.id
        AND n.created_at > now() - interval '7 days'
      ) THEN
        PERFORM create_notification(
          v_leader.id,
          'attendance_detractor',
          'Detractor Alert: ' || v_member.name,
          v_member.name || ' missed 3+ consecutive eligible meetings',
          '/admin/members',
          'member',
          v_member.id
        );
      END IF;
    END LOOP;
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('detractors_found', v_count);
END;
$function$;

-- =============================================================================
-- 2. CRON WRAPPER: send_attendance_reminders_cron
-- Sends notifications for all events happening today.
-- Deduplicates: skips if reminder already sent for that event+member.
-- Respects notification_preferences.muted_types.
-- Schedule: daily 11:00 BRT = 14:00 UTC
-- =============================================================================
DROP FUNCTION IF EXISTS send_attendance_reminders_cron();
CREATE FUNCTION public.send_attendance_reminders_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_event record;
  v_count int := 0;
BEGIN
  -- No auth check — designed exclusively for pg_cron (postgres role)

  FOR v_event IN
    SELECT e.id, e.title, e.date, e.tribe_id, e.type
    FROM events e
    WHERE e.date = current_date
    AND NOT EXISTS (
      SELECT 1 FROM notifications n
      WHERE n.type = 'attendance_reminder'
      AND n.source_id = e.id
    )
  LOOP
    INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
    SELECT m.id, 'attendance_reminder',
      v_event.title || ' starts soon!',
      'Don''t forget to check in!',
      '/attendance',
      'event',
      v_event.id
    FROM members m
    WHERE m.is_active = true
    AND m.current_cycle_active = true
    AND (v_event.type IN ('geral', 'tribo') OR m.tribe_id = v_event.tribe_id)
    AND NOT EXISTS (
      SELECT 1 FROM notifications n2
      WHERE n2.recipient_id = m.id AND n2.type = 'attendance_reminder' AND n2.source_id = v_event.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM notification_preferences np
      WHERE np.member_id = m.id AND 'attendance_reminder' = ANY(np.muted_types)
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('events_reminded', v_count);
END;
$function$;

-- =============================================================================
-- 3. SECURITY: revoke API access — these are pg_cron-only
-- =============================================================================
REVOKE EXECUTE ON FUNCTION detect_and_notify_detractors_cron() FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION send_attendance_reminders_cron() FROM authenticated, anon;

-- =============================================================================
-- 4. pg_cron jobs
-- =============================================================================
-- Detractors: Mondays at 14:00 UTC (11:00 BRT)
SELECT cron.schedule(
  'detect-detractors-weekly',
  '0 14 * * 1',
  $$SELECT detect_and_notify_detractors_cron()$$
);

-- Reminders: Daily at 14:00 UTC (11:00 BRT)
SELECT cron.schedule(
  'attendance-reminders-daily',
  '0 14 * * *',
  $$SELECT send_attendance_reminders_cron()$$
);

-- =============================================================================
-- 5. Schema reload
-- =============================================================================
NOTIFY pgrst, 'reload schema';
