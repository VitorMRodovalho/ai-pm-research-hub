-- p95 #99 (PM decisions 1A+1B+1C): digest consumes attendance_reminder + assignment_new + auto-purge stale
-- ====================================================================
-- 1A: attendance_reminder visible in new section + consumed
-- 1B: assignment_new visible in cards.new_assignments subsection + consumed
-- 1C: monthly cron purges stale notifications (>30d) with sentinel batch_id
--
-- Pre-state p95: 2580 digest_pending, 990 orphans >30d (561 attendance + 352 assignments + 77 others).
-- Post-migration: future fires consume these types, monthly purge cleans historical orphans.
-- Initial purge p95 ran once: 990 → 0 orphans.

CREATE OR REPLACE FUNCTION public.get_weekly_member_digest(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_is_self boolean;
  v_member_tribe_id integer;
  v_window_start timestamptz := date_trunc('day', now()) - interval '7 days';
  v_extended_window timestamptz := date_trunc('day', now()) - interval '14 days';
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  v_is_self := (v_caller_id = p_member_id);

  IF NOT v_is_self AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: can only read own digest or requires manage_member permission';
  END IF;

  SELECT tribe_id INTO v_member_tribe_id FROM public.members WHERE id = p_member_id;

  SELECT jsonb_build_object(
    'member_id', p_member_id,
    'generated_at', now(),
    'window_start', v_window_start,
    'sections', jsonb_build_object(
      'cards', jsonb_build_object(
        'this_week_pending', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', bi.id, 'title', bi.title, 'status', bi.status,
            'due_date', bi.due_date, 'board_name', pb.board_name,
            'initiative_title', i.title,
            'days_overdue', GREATEST(0, CURRENT_DATE - bi.due_date)
          ) ORDER BY bi.due_date ASC)
          FROM public.board_items bi
          LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
          LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
          WHERE bi.assignee_id = p_member_id
            AND bi.status NOT IN ('done', 'archived')
            AND bi.due_date BETWEEN CURRENT_DATE - INTERVAL '7 days' AND CURRENT_DATE
        ), '[]'::jsonb),
        'next_week_due', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', bi.id, 'title', bi.title, 'status', bi.status,
            'due_date', bi.due_date, 'board_name', pb.board_name,
            'initiative_title', i.title
          ) ORDER BY bi.due_date ASC)
          FROM public.board_items bi
          LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
          LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
          WHERE bi.assignee_id = p_member_id
            AND bi.status NOT IN ('done', 'archived')
            AND bi.due_date > CURRENT_DATE
            AND bi.due_date <= CURRENT_DATE + INTERVAL '7 days'
        ), '[]'::jsonb),
        'overdue_7plus', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', bi.id, 'title', bi.title, 'status', bi.status,
            'due_date', bi.due_date, 'board_name', pb.board_name,
            'initiative_title', i.title,
            'days_overdue', CURRENT_DATE - bi.due_date
          ) ORDER BY bi.due_date ASC)
          FROM public.board_items bi
          LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
          LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
          WHERE bi.assignee_id = p_member_id
            AND bi.status NOT IN ('done', 'archived')
            AND bi.due_date < CURRENT_DATE - INTERVAL '7 days'
        ), '[]'::jsonb),
        'new_assignments', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', n.id, 'title', n.title, 'body', n.body,
            'created_at', n.created_at, 'link', n.link
          ) ORDER BY n.created_at DESC)
          FROM public.notifications n
          WHERE n.recipient_id = p_member_id
            AND n.delivery_mode = 'digest_weekly'
            AND n.digest_delivered_at IS NULL
            AND n.type = 'assignment_new'
            AND n.created_at >= v_extended_window
        ), '[]'::jsonb)
      ),

      'engagements_new', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', n.id, 'type', n.type, 'title', n.title,
          'created_at', n.created_at,
          'source_type', n.source_type, 'source_id', n.source_id,
          'link', n.link
        ) ORDER BY n.created_at DESC)
        FROM public.notifications n
        WHERE n.recipient_id = p_member_id
          AND n.delivery_mode = 'digest_weekly'
          AND n.digest_delivered_at IS NULL
          AND n.type IN ('engagement_welcome', 'engagement_added', 'volunteer_agreement_signed')
          AND n.created_at >= v_window_start
      ), '[]'::jsonb),

      'events_upcoming', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', e.id, 'title', e.title, 'date', e.date,
          'type', e.type, 'initiative_id', e.initiative_id,
          'initiative_title', i.title
        ) ORDER BY e.date ASC)
        FROM public.events e
        LEFT JOIN public.initiatives i ON i.id = e.initiative_id
        WHERE e.date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
          AND (
            i.legacy_tribe_id = v_member_tribe_id
            OR e.type IN ('plenaria', 'webinar', 'workshop_geral')
          )
      ), '[]'::jsonb),

      'attendance_reminders_pending', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', n.id, 'title', n.title, 'body', n.body,
          'created_at', n.created_at, 'link', n.link
        ) ORDER BY n.created_at DESC)
        FROM public.notifications n
        WHERE n.recipient_id = p_member_id
          AND n.delivery_mode = 'digest_weekly'
          AND n.digest_delivered_at IS NULL
          AND n.type = 'attendance_reminder'
          AND n.created_at >= v_extended_window
      ), '[]'::jsonb),

      'publications_new', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', ps.id, 'title', ps.title,
          'submission_date', ps.submission_date,
          'primary_author_id', ps.primary_author_id
        ) ORDER BY ps.submission_date DESC)
        FROM public.publication_submissions ps
        WHERE ps.status = 'published'::public.submission_status
          AND ps.submission_date >= v_window_start::date
      ), '[]'::jsonb),

      'broadcasts', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', n.id, 'title', n.title, 'body', n.body,
          'created_at', n.created_at, 'link', n.link
        ) ORDER BY n.created_at DESC)
        FROM public.notifications n
        WHERE n.recipient_id = p_member_id
          AND n.delivery_mode = 'digest_weekly'
          AND n.digest_delivered_at IS NULL
          AND n.type = 'tribe_broadcast'
          AND n.created_at >= v_window_start
      ), '[]'::jsonb),

      'governance_pending', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', n.id, 'type', n.type, 'title', n.title,
          'created_at', n.created_at, 'link', n.link
        ) ORDER BY n.created_at DESC)
        FROM public.notifications n
        WHERE n.recipient_id = p_member_id
          AND n.delivery_mode = 'digest_weekly'
          AND n.digest_delivered_at IS NULL
          AND n.type IN ('governance_vote_reminder', 'ip_ratification_gate_pending', 'change_request_pending')
          AND n.created_at >= v_window_start
      ), '[]'::jsonb),

      'achievements', jsonb_build_object(
        'certificates_issued', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', c.id, 'title', c.title, 'type', c.type,
            'issued_at', c.issued_at
          ) ORDER BY c.issued_at DESC)
          FROM public.certificates c
          WHERE c.member_id = p_member_id
            AND c.issued_at >= v_window_start
        ), '[]'::jsonb),
        'xp_delta', COALESCE((
          SELECT sum(gp.points)::int
          FROM public.gamification_points gp
          WHERE gp.member_id = p_member_id
            AND gp.created_at >= v_window_start
        ), 0)
      )
    ),
    'consumed_notification_ids', COALESCE((
      SELECT jsonb_agg(n.id)
      FROM public.notifications n
      WHERE n.recipient_id = p_member_id
        AND n.delivery_mode = 'digest_weekly'
        AND n.digest_delivered_at IS NULL
        AND (
          n.created_at >= v_window_start
          OR (n.type IN ('attendance_reminder', 'assignment_new') AND n.created_at >= v_extended_window)
        )
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.get_weekly_member_digest(uuid) IS
  'p95 #99 1A+1B: amended to include attendance_reminder + assignment_new sections + consumed set. 7-section format expanded to 8: cards (with new_assignments subsection) / engagements_new / events_upcoming / attendance_reminders_pending / publications_new / broadcasts / governance_pending / achievements. Extended window 14d for the 2 high-volume types.';

CREATE OR REPLACE FUNCTION public.purge_stale_digest_notifications_cron()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count integer;
  v_batch_id uuid := gen_random_uuid();
BEGIN
  WITH purged AS (
    UPDATE public.notifications
    SET digest_delivered_at = now(),
        digest_batch_id = v_batch_id
    WHERE delivery_mode = 'digest_weekly'
      AND digest_delivered_at IS NULL
      AND created_at < now() - interval '30 days'
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM purged;

  IF v_count > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
    VALUES (NULL, 'purge_stale_digest_notifications', 'notifications', NULL,
            jsonb_build_object('purged_count', v_count, 'batch_id', v_batch_id, 'cutoff_days', 30, 'cutoff_at', now() - interval '30 days'));
  END IF;

  RETURN jsonb_build_object('purged_count', v_count, 'batch_id', v_batch_id, 'cutoff_days', 30, 'run_at', now());
END $function$;

REVOKE EXECUTE ON FUNCTION public.purge_stale_digest_notifications_cron() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.purge_stale_digest_notifications_cron() IS
  'p95 #99 1C: monthly cron-only purge. Marks digest_weekly notifications >30d as delivered with sentinel batch_id. Audit logged. Smart-skip when 0 stale.';

SELECT cron.schedule(
  'digest-stale-purge-monthly',
  '0 14 5 * *',
  $$SELECT public.purge_stale_digest_notifications_cron();$$
);

NOTIFY pgrst, 'reload schema';
