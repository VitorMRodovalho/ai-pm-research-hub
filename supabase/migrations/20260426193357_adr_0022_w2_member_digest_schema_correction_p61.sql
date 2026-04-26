-- ADR-0022 W2 schema correction (p61): notifications has no `metadata` col;
-- gamification_points uses `points` not `amount`. Re-create the 2 broken
-- RPCs with corrected column refs. Store digest payload inline in
-- notifications.body as JSON text (EF parses on send).

-- ============================================================
-- 3 (corrected). get_weekly_member_digest — 7 sections
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_weekly_member_digest(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_is_self boolean;
  v_member_tribe_id integer;
  v_window_start timestamptz := date_trunc('day', now()) - interval '7 days';
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
      -- ─── 1. CARDS ───
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
        ), '[]'::jsonb)
      ),

      -- ─── 2. ENGAGEMENTS ───
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

      -- ─── 3. EVENTS UPCOMING ───
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

      -- ─── 4. PUBLICATIONS ───
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

      -- ─── 5. BROADCASTS ───
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

      -- ─── 6. GOVERNANCE PENDING ───
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

      -- ─── 7. ACHIEVEMENTS ───
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
        AND n.created_at >= v_window_start
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;
COMMENT ON FUNCTION public.get_weekly_member_digest(uuid) IS
  'ADR-0022 W2: returns 7-section consolidated weekly digest. Sections: cards, engagements_new, events_upcoming, publications_new, broadcasts, governance_pending, achievements. Auth: caller=self OR manage_member. Returns consumed_notification_ids for orchestrator.';

-- ============================================================
-- 4 (corrected). generate_weekly_member_digest_cron — orchestrator
-- ============================================================
CREATE OR REPLACE FUNCTION public.generate_weekly_member_digest_cron()
RETURNS TABLE(member_id uuid, notified boolean, reason text, batch_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_m record;
  v_digest jsonb;
  v_has_content boolean;
  v_consumed_ids jsonb;
  v_batch_id uuid := gen_random_uuid();
  v_consumed_id_array uuid[];
BEGIN
  FOR v_m IN
    SELECT id FROM public.members
    WHERE is_active = true
      AND notify_weekly_digest = true
      AND notify_delivery_mode_pref IN ('weekly_digest', 'custom_per_type')
  LOOP
    v_digest := public.get_weekly_member_digest(v_m.id);
    v_has_content :=
      jsonb_array_length(v_digest->'sections'->'cards'->'this_week_pending') > 0
      OR jsonb_array_length(v_digest->'sections'->'cards'->'next_week_due') > 0
      OR jsonb_array_length(v_digest->'sections'->'cards'->'overdue_7plus') > 0
      OR jsonb_array_length(v_digest->'sections'->'engagements_new') > 0
      OR jsonb_array_length(v_digest->'sections'->'events_upcoming') > 0
      OR jsonb_array_length(v_digest->'sections'->'publications_new') > 0
      OR jsonb_array_length(v_digest->'sections'->'broadcasts') > 0
      OR jsonb_array_length(v_digest->'sections'->'governance_pending') > 0
      OR jsonb_array_length(v_digest->'sections'->'achievements'->'certificates_issued') > 0
      OR (v_digest->'sections'->'achievements'->>'xp_delta')::int > 0;

    IF v_has_content THEN
      v_consumed_ids := v_digest->'consumed_notification_ids';

      INSERT INTO public.notifications (
        recipient_id, type, title, body, link, source_type, source_id,
        is_read, delivery_mode, digest_batch_id
      ) VALUES (
        v_m.id,
        'weekly_member_digest',
        'Seu resumo semanal — Núcleo IA',
        v_digest::text,
        '/digest/' || v_batch_id::text,
        'digest',
        v_batch_id,
        false,
        'transactional_immediate',
        v_batch_id
      );

      IF jsonb_array_length(v_consumed_ids) > 0 THEN
        SELECT array_agg((value::text)::uuid) INTO v_consumed_id_array
        FROM jsonb_array_elements_text(v_consumed_ids);

        UPDATE public.notifications
        SET digest_delivered_at = now(),
            digest_batch_id = v_batch_id
        WHERE id = ANY(v_consumed_id_array)
          AND digest_delivered_at IS NULL;
      END IF;

      member_id := v_m.id; notified := true; reason := 'sent'; batch_id := v_batch_id;
    ELSE
      member_id := v_m.id; notified := false; reason := 'no_content_skip'; batch_id := NULL;
    END IF;
    RETURN NEXT;
  END LOOP;
END;
$$;
COMMENT ON FUNCTION public.generate_weekly_member_digest_cron() IS
  'ADR-0022 W2 (corrected): orchestrator. Iterates active members opted into weekly digest. For each: calls get_weekly_member_digest, skips if 0 content, otherwise inserts weekly_member_digest notification (delivery_mode=transactional_immediate so EF send-notification-email picks it up; body stores full digest as JSON text since notifications has no metadata col) AND marks consumed digest_weekly notifications as digest_delivered_at + digest_batch_id. Cron: Saturday 12:00 UTC.';

NOTIFY pgrst, 'reload schema';
