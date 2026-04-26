-- ADR-0022 W3 (p62): leader digest variant + tribe_broadcast urgent rate-limit
-- + custom_per_type RPCs + minimal analytics. Builds on W1+W2.
--
-- Components:
--   1. get_weekly_tribe_digest(integer) — aggregate-only RPC for leader
--      (privacy-preserving: NO individual cards, only tribe stats)
--   2. generate_weekly_leader_digest_cron() — iterates tribes with active
--      leader, generates digest, inserts weekly_tribe_digest_leader notification
--   3. trg_check_tribe_broadcast_urgent_rate_limit — trigger BEFORE INSERT
--      on notifications. If type=tribe_broadcast AND delivery_mode=
--      transactional_immediate, count actor_id's prior urgent broadcasts in
--      current week (Mon-Sun); raise if >= 1.
--   4. set_my_muted_notification_types(text[]) — for custom_per_type UI
--   5. get_my_notification_metrics(int) — sent/read counts (W3 minimal;
--      open/click via Resend webhook deferred to W4)
--   6. Cron entry for leader orchestrator (Saturday 12:30 UTC, 30min after
--      member digest to avoid race on consumed notifications)

-- ============================================================
-- 1. get_weekly_tribe_digest(integer) — aggregate-only
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_weekly_tribe_digest(p_tribe_id integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_tribe record;
  v_window_start timestamptz := date_trunc('day', now()) - interval '7 days';
  v_result jsonb;
  v_is_leader boolean;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe IS NULL THEN RAISE EXCEPTION 'Tribe not found: %', p_tribe_id; END IF;

  v_is_leader := (v_caller_id IS NOT NULL AND v_caller_id = v_tribe.leader_member_id);
  IF NOT v_is_leader AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: only tribe leader or manage_member can read tribe digest';
  END IF;

  SELECT jsonb_build_object(
    'tribe_id', p_tribe_id,
    'tribe_name', v_tribe.name,
    'leader_member_id', v_tribe.leader_member_id,
    'generated_at', now(),
    'window_start', v_window_start,
    'aggregates', jsonb_build_object(
      'active_members', COALESCE((
        SELECT count(*) FROM public.members m
        WHERE m.tribe_id = p_tribe_id AND m.current_cycle_active = true
      ), 0),
      'members_with_overdue_cards', COALESCE((
        SELECT count(DISTINCT bi.assignee_id) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        JOIN public.initiatives i ON i.id = pb.initiative_id
        JOIN public.members m ON m.id = bi.assignee_id
        WHERE i.legacy_tribe_id = p_tribe_id
          AND m.tribe_id = p_tribe_id
          AND bi.status NOT IN ('done', 'archived')
          AND bi.due_date < CURRENT_DATE
      ), 0),
      'cards_overdue_total', COALESCE((
        SELECT count(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        JOIN public.initiatives i ON i.id = pb.initiative_id
        WHERE i.legacy_tribe_id = p_tribe_id
          AND bi.status NOT IN ('done', 'archived')
          AND bi.due_date < CURRENT_DATE
      ), 0),
      'cards_due_next_7d', COALESCE((
        SELECT count(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        JOIN public.initiatives i ON i.id = pb.initiative_id
        WHERE i.legacy_tribe_id = p_tribe_id
          AND bi.status NOT IN ('done', 'archived')
          AND bi.due_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
      ), 0),
      'cards_without_assignee', COALESCE((
        SELECT count(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        JOIN public.initiatives i ON i.id = pb.initiative_id
        WHERE i.legacy_tribe_id = p_tribe_id
          AND bi.status NOT IN ('done', 'archived')
          AND bi.assignee_id IS NULL
      ), 0),
      'cards_without_due_date', COALESCE((
        SELECT count(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        JOIN public.initiatives i ON i.id = pb.initiative_id
        WHERE i.legacy_tribe_id = p_tribe_id
          AND bi.status NOT IN ('done', 'archived')
          AND bi.due_date IS NULL
      ), 0),
      'cards_completed_window', COALESCE((
        SELECT count(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        JOIN public.initiatives i ON i.id = pb.initiative_id
        WHERE i.legacy_tribe_id = p_tribe_id
          AND bi.status IN ('done')
          AND bi.updated_at >= v_window_start
      ), 0),
      'tribe_health_pct', COALESCE((
        SELECT CASE
          WHEN count(*) FILTER (WHERE bi.status NOT IN ('done', 'archived')) = 0 THEN 100
          ELSE (100.0 * count(*) FILTER (WHERE bi.status NOT IN ('done', 'archived') AND bi.due_date IS NOT NULL)
                / NULLIF(count(*) FILTER (WHERE bi.status NOT IN ('done', 'archived')), 0))::int
        END
        FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        JOIN public.initiatives i ON i.id = pb.initiative_id
        WHERE i.legacy_tribe_id = p_tribe_id
      ), 100)
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_weekly_tribe_digest(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_weekly_tribe_digest(integer) TO authenticated, service_role;
COMMENT ON FUNCTION public.get_weekly_tribe_digest(integer) IS
  'ADR-0022 W3 (p62): aggregate-only weekly digest for tribe leader. Privacy-preserving — NO individual member names or card titles, only counts/percentages. Auth: caller=tribe leader OR manage_member. Used by generate_weekly_leader_digest_cron.';

-- ============================================================
-- 2. generate_weekly_leader_digest_cron — orchestrator W3
-- ============================================================
CREATE OR REPLACE FUNCTION public.generate_weekly_leader_digest_cron()
RETURNS TABLE(tribe_id integer, leader_id uuid, notified boolean, reason text, batch_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_t record;
  v_digest jsonb;
  v_has_signal boolean;
  v_batch_id uuid := gen_random_uuid();
  v_leader_pref text;
BEGIN
  FOR v_t IN
    SELECT t.id, t.leader_member_id, t.name
    FROM public.tribes t
    WHERE t.is_active = true
      AND t.leader_member_id IS NOT NULL
  LOOP
    SELECT notify_delivery_mode_pref INTO v_leader_pref
    FROM public.members WHERE id = v_t.leader_member_id;

    IF v_leader_pref = 'suppress_all' THEN
      tribe_id := v_t.id; leader_id := v_t.leader_member_id;
      notified := false; reason := 'leader_suppressed_all'; batch_id := NULL;
      RETURN NEXT;
      CONTINUE;
    END IF;

    v_digest := public.get_weekly_tribe_digest(v_t.id);
    v_has_signal :=
      (v_digest->'aggregates'->>'cards_overdue_total')::int > 0
      OR (v_digest->'aggregates'->>'cards_due_next_7d')::int > 0
      OR (v_digest->'aggregates'->>'cards_without_assignee')::int > 0
      OR (v_digest->'aggregates'->>'cards_without_due_date')::int > 0
      OR (v_digest->'aggregates'->>'cards_completed_window')::int > 0;

    IF v_has_signal THEN
      INSERT INTO public.notifications (
        recipient_id, type, title, body, link, source_type, source_id,
        is_read, delivery_mode, digest_batch_id
      ) VALUES (
        v_t.leader_member_id,
        'weekly_tribe_digest_leader',
        'Resumo semanal da Tribo ' || v_t.name,
        v_digest::text,
        '/admin/portfolio',
        'leader_digest',
        v_batch_id,
        false,
        'transactional_immediate',
        v_batch_id
      );
      tribe_id := v_t.id; leader_id := v_t.leader_member_id;
      notified := true; reason := 'sent'; batch_id := v_batch_id;
    ELSE
      tribe_id := v_t.id; leader_id := v_t.leader_member_id;
      notified := false; reason := 'no_signal_skip'; batch_id := NULL;
    END IF;
    RETURN NEXT;
  END LOOP;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.generate_weekly_leader_digest_cron() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_weekly_leader_digest_cron() TO service_role;
COMMENT ON FUNCTION public.generate_weekly_leader_digest_cron() IS
  'ADR-0022 W3: leader digest orchestrator. Iterates active tribes with leader_member_id. For each: skips if leader opted suppress_all, else builds aggregate digest, skips if 0 signal, else inserts weekly_tribe_digest_leader notification. Cron: Saturday 12:30 UTC.';

-- ============================================================
-- 3. Trigger: tribe_broadcast urgent rate-limit (1/week/leader)
-- ============================================================
CREATE OR REPLACE FUNCTION public._tribe_broadcast_urgent_rate_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor_count integer;
  v_week_start timestamptz := date_trunc('week', now());
BEGIN
  IF NEW.type != 'tribe_broadcast' THEN RETURN NEW; END IF;
  IF NEW.delivery_mode != 'transactional_immediate' THEN RETURN NEW; END IF;
  IF NEW.actor_id IS NULL THEN RETURN NEW; END IF;

  SELECT count(DISTINCT digest_batch_id)
  INTO v_actor_count
  FROM public.notifications
  WHERE type = 'tribe_broadcast'
    AND delivery_mode = 'transactional_immediate'
    AND actor_id = NEW.actor_id
    AND created_at >= v_week_start
    AND id != NEW.id;

  IF v_actor_count >= 1 THEN
    RAISE EXCEPTION 'rate_limit_exceeded: tribe_broadcast urgent limited to 1/week/leader (current: %, week_start: %). Use delivery_mode=digest_weekly for non-urgent broadcast.',
      v_actor_count, v_week_start
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tribe_broadcast_urgent_rate_limit ON public.notifications;
CREATE TRIGGER trg_tribe_broadcast_urgent_rate_limit
  BEFORE INSERT ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public._tribe_broadcast_urgent_rate_limit();

COMMENT ON FUNCTION public._tribe_broadcast_urgent_rate_limit() IS
  'ADR-0022 W3 (p62): rate-limit trigger for tribe_broadcast urgent. Enforces 1 urgent broadcast batch per week per actor (counted by distinct digest_batch_id to allow multi-notification fan-outs as 1 batch). Non-urgent (delivery_mode=digest_weekly) is unrestricted.';

-- ============================================================
-- 4. set_my_muted_notification_types — for custom_per_type UI
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_my_muted_notification_types(p_muted_types text[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;

  INSERT INTO public.notification_preferences (member_id, muted_types, updated_at)
  VALUES (v_caller_id, COALESCE(p_muted_types, ARRAY[]::text[]), now())
  ON CONFLICT (member_id) DO UPDATE
    SET muted_types = COALESCE(EXCLUDED.muted_types, ARRAY[]::text[]),
        updated_at = now();

  RETURN jsonb_build_object(
    'success', true,
    'muted_types', COALESCE(p_muted_types, ARRAY[]::text[])
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.set_my_muted_notification_types(text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_muted_notification_types(text[]) TO authenticated;
COMMENT ON FUNCTION public.set_my_muted_notification_types(text[]) IS
  'ADR-0022 W3 (p62): self-update notification_preferences.muted_types array. Used by /settings/notifications custom_per_type UI.';

-- ============================================================
-- 5. get_my_notification_metrics — minimal W3 analytics (sent/read counts)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_my_notification_metrics(p_window_days integer DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_window_start timestamptz;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;

  v_window_start := now() - (p_window_days || ' days')::interval;

  SELECT jsonb_build_object(
    'window_days', p_window_days,
    'window_start', v_window_start,
    'total_received', count(*),
    'total_emailed', count(*) FILTER (WHERE email_sent_at IS NOT NULL),
    'total_read', count(*) FILTER (WHERE is_read = true),
    'total_unread', count(*) FILTER (WHERE is_read = false),
    'by_type', (
      SELECT jsonb_object_agg(type, cnt)
      FROM (
        SELECT type, count(*) AS cnt
        FROM public.notifications
        WHERE recipient_id = v_caller_id AND created_at >= v_window_start
        GROUP BY type
        ORDER BY cnt DESC
      ) sub
    ),
    'by_delivery_mode', (
      SELECT jsonb_object_agg(coalesce(delivery_mode, 'unset'), cnt)
      FROM (
        SELECT delivery_mode, count(*) AS cnt
        FROM public.notifications
        WHERE recipient_id = v_caller_id AND created_at >= v_window_start
        GROUP BY delivery_mode
      ) sub
    )
  ) INTO v_result
  FROM public.notifications
  WHERE recipient_id = v_caller_id
    AND created_at >= v_window_start;

  RETURN v_result;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_my_notification_metrics(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_notification_metrics(integer) TO authenticated;
COMMENT ON FUNCTION public.get_my_notification_metrics(integer) IS
  'ADR-0022 W3 (p62): minimal self-metrics for notification volume + read rate. Open/click rate via Resend webhook deferred to W4.';

-- ============================================================
-- 6. Cron entry — leader digest Saturday 12:30 UTC
-- ============================================================
DO $$
DECLARE
  v_existing bigint;
BEGIN
  SELECT jobid INTO v_existing FROM cron.job WHERE jobname = 'send-weekly-leader-digest';
  IF v_existing IS NULL THEN
    PERFORM cron.schedule(
      'send-weekly-leader-digest',
      '30 12 * * 6',
      $cmd$SELECT public.generate_weekly_leader_digest_cron();$cmd$
    );
  ELSE
    PERFORM cron.alter_job(
      v_existing,
      schedule := '30 12 * * 6',
      command := $cmd$SELECT public.generate_weekly_leader_digest_cron();$cmd$
    );
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
