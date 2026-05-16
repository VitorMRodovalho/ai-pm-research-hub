-- p172 #21 — Multi-leader per initiative digest delivery (V4 N:N)
--
-- p170 Item #17 migrou digest cron de V3 cache (tribes.leader_member_id)
-- pra V4 lookup (_v4_tribe_leader_member_id helper). Mas helper retorna
-- single uuid (LIMIT 1 ORDER BY start_date DESC), ignorando co_leaders.
-- V4 modela leader + co_leader como engagements paralelos — ambos
-- deveriam receber digest semanal.
--
-- Hoje: 7 tribes com 1 leader cada + tribe 3 (TMO) is_active=false skipped.
-- Co_leaders existem em V4 schema (engagement_role enum check) mas nenhum
-- atualmente. Future-proof pra multi-leader scenarios + chapter expansion
-- (PMI-CE, PMI-GO replicas) onde co-leadership será mais comum.
--
-- Mudanças:
-- 1. Novo helper `_v4_initiative_leader_member_ids(p_tribe_id)`
--    returns SETOF uuid (all active leaders + co_leaders).
-- 2. `_v4_tribe_leader_member_id` mantido como-is (backward compat;
--    returns first row de helper set para single-uuid contexts).
-- 3. `get_weekly_tribe_digest` auth check usa EXISTS no set.
-- 4. `generate_weekly_leader_digest_cron` LOOP por cada leader ativo,
--    INSERT 1 notification cada. Audit row per (tribe, leader) pair.
--
-- Backward compat: tribes com 1 leader = comportamento idêntico p170.
-- Tribe 3 (TMO) is_active=false = naturalmente skipped (FOR loop filter).
--
-- Smoke (rollback-protected):
--   - Baseline: 7 rows notified=sent (1 per tribe ativa, sem co_leaders)
--   - Forward-compat: temp co_leader added → tribe 1 produces 2 rows.
--
-- Cron schedule: sábado 12:30 UTC = 09:30 BRT. Primeiro run com
-- multi-leader logic: 2026-05-23.
--
-- Rollback: restore previous bodies + DROP helper novo.

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 1 — New SETOF helper
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._v4_initiative_leader_member_ids(p_tribe_id integer)
RETURNS SETOF uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT DISTINCT m.id
  FROM engagements e
  JOIN members m ON m.person_id = e.person_id
  JOIN initiatives i ON i.id = e.initiative_id
  WHERE i.legacy_tribe_id = p_tribe_id
    AND e.status = 'active'
    AND e.role IN ('leader', 'co_leader')
  ORDER BY m.id;
$function$;

COMMENT ON FUNCTION public._v4_initiative_leader_member_ids(integer) IS
  'p172 #21 — SETOF uuid: all active leader + co_leader member ids for a tribe (via legacy_tribe_id bridge). Used by digest cron pra multi-leader delivery.';

GRANT EXECUTE ON FUNCTION public._v4_initiative_leader_member_ids(integer) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 2 — Update get_weekly_tribe_digest auth check to use multi-leader set
-- (Body herda de p170 #19 — full body restored com only auth check mudada)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_weekly_tribe_digest(p_tribe_id integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_tribe record;
  v_window_start timestamptz := date_trunc('day', now()) - interval '7 days';
  v_cycle_start timestamptz;
  v_cycle_end timestamptz;
  v_initiative_id uuid;
  v_leader_member_id uuid;
  v_is_leader boolean;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe IS NULL THEN RAISE EXCEPTION 'Tribe not found: %', p_tribe_id; END IF;

  v_leader_member_id := public._v4_tribe_leader_member_id(p_tribe_id);

  -- p172 #21: multi-leader auth check via SET (leader OR co_leader)
  IF auth.role() = 'service_role'
     OR current_setting('request.jwt.claims', true) IS NULL THEN
    NULL;
  ELSE
    v_is_leader := EXISTS (
      SELECT 1 FROM public._v4_initiative_leader_member_ids(p_tribe_id) lid
      WHERE lid = v_caller_id
    );
    IF NOT v_is_leader AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
      RAISE EXCEPTION 'Unauthorized: only tribe leader (or co_leader) or manage_member can read tribe digest';
    END IF;
  END IF;

  SELECT cycle_start::timestamptz, cycle_end::timestamptz
    INTO v_cycle_start, v_cycle_end
  FROM public.cycles WHERE is_current = true LIMIT 1;

  SELECT id INTO v_initiative_id FROM public.initiatives
  WHERE legacy_tribe_id = p_tribe_id
  LIMIT 1;

  SELECT jsonb_build_object(
    'tribe_id', p_tribe_id,
    'tribe_name', v_tribe.name,
    'initiative_id', v_initiative_id,
    'leader_member_id', v_leader_member_id,
    'generated_at', now(),
    'window_start', v_window_start,
    'cycle_start', v_cycle_start,
    'cycle_end', v_cycle_end,
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
        WHERE i.legacy_tribe_id = p_tribe_id AND m.tribe_id = p_tribe_id
          AND bi.status NOT IN ('done', 'archived')
          AND bi.due_date < CURRENT_DATE
      ), 0),
      'cards_overdue_total', COALESCE((
        SELECT count(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        JOIN public.initiatives i ON i.id = pb.initiative_id
        WHERE i.legacy_tribe_id = p_tribe_id
          AND bi.status NOT IN ('done', 'archived') AND bi.due_date < CURRENT_DATE
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
          AND bi.status NOT IN ('done', 'archived') AND bi.assignee_id IS NULL
      ), 0),
      'cards_without_due_date', COALESCE((
        SELECT count(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        JOIN public.initiatives i ON i.id = pb.initiative_id
        WHERE i.legacy_tribe_id = p_tribe_id
          AND bi.status NOT IN ('done', 'archived') AND bi.due_date IS NULL
      ), 0),
      'cards_completed_window', COALESCE((
        SELECT count(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        JOIN public.initiatives i ON i.id = pb.initiative_id
        WHERE i.legacy_tribe_id = p_tribe_id
          AND bi.status IN ('done') AND bi.updated_at >= v_window_start
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
      ), 100),

      'ata_pending', COALESCE((
        WITH pending AS (
          SELECT e.id, e.title, e.date, e.recurrence_group, e.type
          FROM public.events e
          WHERE e.type IN ('tribo','geral','lideranca')
            AND e.date::timestamptz < now()
            AND e.date::timestamptz >= v_cycle_start
            AND (v_cycle_end IS NULL OR e.date::timestamptz < (v_cycle_end + interval '1 day'))
            AND (e.status IS NULL OR e.status != 'cancelled')
            AND (e.initiative_id = v_initiative_id
                 OR (e.type = 'geral' AND e.initiative_id IS NULL))
            AND NOT EXISTS (
              SELECT 1 FROM public.meeting_artifacts ma
              WHERE ma.event_id = e.id AND ma.is_published = true
            )
        ),
        grouped AS (
          SELECT
            COALESCE(recurrence_group::text, id::text) AS group_key,
            recurrence_group,
            (recurrence_group IS NOT NULL) AS is_recurring,
            count(*) AS occurrence_count,
            (array_agg(title ORDER BY date DESC))[1] AS sample_title,
            (array_agg(id ORDER BY date DESC))[1] AS latest_event_id,
            max(date) AS latest_date
          FROM pending
          GROUP BY COALESCE(recurrence_group::text, id::text), recurrence_group
        ),
        agg AS (
          SELECT count(*) AS total_groups, (SELECT count(*) FROM pending) AS total_events
          FROM grouped
        ),
        top3 AS (
          SELECT * FROM grouped ORDER BY latest_date DESC LIMIT 3
        )
        SELECT jsonb_build_object(
          'count_groups', (SELECT total_groups FROM agg),
          'count_events', (SELECT total_events FROM agg),
          'top_groups', COALESCE((SELECT jsonb_agg(
            jsonb_build_object(
              'is_recurring', is_recurring,
              'occurrence_count', occurrence_count,
              'sample_title', sample_title,
              'latest_event_id', latest_event_id,
              'latest_date', latest_date
            )
          ) FROM top3), '[]'::jsonb)
        )
      ), jsonb_build_object('count_groups', 0, 'count_events', 0, 'top_groups', '[]'::jsonb)),

      'attendance_pending', COALESCE((
        WITH pending AS (
          SELECT e.id, e.title, e.date, e.recurrence_group
          FROM public.events e
          WHERE e.type IN ('tribo','geral','lideranca')
            AND e.date::timestamptz < now()
            AND e.date::timestamptz >= v_cycle_start
            AND (v_cycle_end IS NULL OR e.date::timestamptz < (v_cycle_end + interval '1 day'))
            AND (e.status IS NULL OR e.status != 'cancelled')
            AND (e.initiative_id = v_initiative_id
                 OR (e.type = 'geral' AND e.initiative_id IS NULL))
            AND NOT EXISTS (
              SELECT 1 FROM public.attendance a WHERE a.event_id = e.id
            )
        ),
        grouped AS (
          SELECT
            COALESCE(recurrence_group::text, id::text) AS group_key,
            recurrence_group,
            (recurrence_group IS NOT NULL) AS is_recurring,
            count(*) AS occurrence_count,
            (array_agg(title ORDER BY date DESC))[1] AS sample_title,
            (array_agg(id ORDER BY date DESC))[1] AS latest_event_id,
            max(date) AS latest_date
          FROM pending
          GROUP BY COALESCE(recurrence_group::text, id::text), recurrence_group
        ),
        agg AS (
          SELECT count(*) AS total_groups, (SELECT count(*) FROM pending) AS total_events
          FROM grouped
        ),
        top3 AS (SELECT * FROM grouped ORDER BY latest_date DESC LIMIT 3)
        SELECT jsonb_build_object(
          'count_groups', (SELECT total_groups FROM agg),
          'count_events', (SELECT total_events FROM agg),
          'count',        (SELECT total_groups FROM agg),
          'top_groups', COALESCE((SELECT jsonb_agg(
            jsonb_build_object(
              'is_recurring', is_recurring,
              'occurrence_count', occurrence_count,
              'sample_title', sample_title,
              'latest_event_id', latest_event_id,
              'latest_date', latest_date
            )
          ) FROM top3), '[]'::jsonb),
          'top_events', COALESCE((SELECT jsonb_agg(
            jsonb_build_object('event_id', latest_event_id, 'title', sample_title, 'date', latest_date)
          ) FROM top3), '[]'::jsonb)
        )
      ), jsonb_build_object('count_groups', 0, 'count_events', 0, 'count', 0, 'top_groups', '[]'::jsonb, 'top_events', '[]'::jsonb)),

      'champion_pending', COALESCE((
        WITH pending AS (
          SELECT e.id, e.title, e.date, e.recurrence_group
          FROM public.events e
          WHERE e.type IN ('tribo','geral','lideranca')
            AND e.date::timestamptz < now()
            AND e.date::timestamptz >= v_cycle_start
            AND (v_cycle_end IS NULL OR e.date::timestamptz < (v_cycle_end + interval '1 day'))
            AND (e.status IS NULL OR e.status != 'cancelled')
            AND (e.initiative_id = v_initiative_id
                 OR (e.type = 'geral' AND e.initiative_id IS NULL))
            AND NOT EXISTS (
              SELECT 1 FROM public.champions_awarded ca
              WHERE ca.context_kind = 'event' AND ca.context_id = e.id
                AND ca.status = 'active'
            )
        ),
        grouped AS (
          SELECT
            COALESCE(recurrence_group::text, id::text) AS group_key,
            recurrence_group,
            (recurrence_group IS NOT NULL) AS is_recurring,
            count(*) AS occurrence_count,
            (array_agg(title ORDER BY date DESC))[1] AS sample_title,
            (array_agg(id ORDER BY date DESC))[1] AS latest_event_id,
            max(date) AS latest_date
          FROM pending
          GROUP BY COALESCE(recurrence_group::text, id::text), recurrence_group
        ),
        agg AS (
          SELECT count(*) AS total_groups, (SELECT count(*) FROM pending) AS total_events
          FROM grouped
        ),
        top3 AS (SELECT * FROM grouped ORDER BY latest_date DESC LIMIT 3)
        SELECT jsonb_build_object(
          'count_groups', (SELECT total_groups FROM agg),
          'count_events', (SELECT total_events FROM agg),
          'count',        (SELECT total_groups FROM agg),
          'top_groups', COALESCE((SELECT jsonb_agg(
            jsonb_build_object(
              'is_recurring', is_recurring,
              'occurrence_count', occurrence_count,
              'sample_title', sample_title,
              'latest_event_id', latest_event_id,
              'latest_date', latest_date
            )
          ) FROM top3), '[]'::jsonb),
          'top_events', COALESCE((SELECT jsonb_agg(
            jsonb_build_object('event_id', latest_event_id, 'title', sample_title, 'date', latest_date)
          ) FROM top3), '[]'::jsonb)
        )
      ), jsonb_build_object('count_groups', 0, 'count_events', 0, 'count', 0, 'top_groups', '[]'::jsonb, 'top_events', '[]'::jsonb))
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.get_weekly_tribe_digest(integer) IS
  'p172 #21 — Multi-leader auth (leader OR co_leader via _v4_initiative_leader_member_ids). Body herda de p170 #19 (recurrence grouping em attendance_pending + champion_pending).';

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 3 — Multi-leader cron LOOP
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.generate_weekly_leader_digest_cron()
 RETURNS TABLE(tribe_id integer, leader_id uuid, notified boolean, reason text, batch_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_t record;
  v_leader_id uuid;
  v_digest jsonb;
  v_has_signal boolean;
  v_batch_id uuid := gen_random_uuid();
  v_leader_pref text;
  v_leader_count int;
BEGIN
  FOR v_t IN
    SELECT t.id, t.name
    FROM public.tribes t
    WHERE t.is_active = true
  LOOP
    SELECT COUNT(*) INTO v_leader_count
    FROM public._v4_initiative_leader_member_ids(v_t.id);

    IF v_leader_count = 0 THEN
      tribe_id := v_t.id; leader_id := NULL;
      notified := false; reason := 'no_active_v4_leader_engagement'; batch_id := NULL;
      RETURN NEXT;
      CONTINUE;
    END IF;

    v_digest := public.get_weekly_tribe_digest(v_t.id);

    v_has_signal :=
      (v_digest->'aggregates'->>'cards_overdue_total')::int > 0
      OR (v_digest->'aggregates'->>'cards_due_next_7d')::int > 0
      OR (v_digest->'aggregates'->>'cards_without_assignee')::int > 0
      OR (v_digest->'aggregates'->>'cards_without_due_date')::int > 0
      OR (v_digest->'aggregates'->>'cards_completed_window')::int > 0
      OR (v_digest->'aggregates'->'ata_pending'->>'count_events')::int > 0
      OR (v_digest->'aggregates'->'attendance_pending'->>'count')::int > 0
      OR (v_digest->'aggregates'->'champion_pending'->>'count')::int > 0;

    FOR v_leader_id IN
      SELECT lid FROM public._v4_initiative_leader_member_ids(v_t.id) lid
    LOOP
      SELECT notify_delivery_mode_pref INTO v_leader_pref
      FROM public.members WHERE id = v_leader_id;

      IF v_leader_pref = 'suppress_all' THEN
        tribe_id := v_t.id; leader_id := v_leader_id;
        notified := false; reason := 'leader_suppressed_all'; batch_id := NULL;
        RETURN NEXT;
        CONTINUE;
      END IF;

      IF v_has_signal THEN
        INSERT INTO public.notifications (
          recipient_id, type, title, body, link, source_type, source_id,
          is_read, delivery_mode, digest_batch_id
        ) VALUES (
          v_leader_id,
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
        tribe_id := v_t.id; leader_id := v_leader_id;
        notified := true; reason := 'sent'; batch_id := v_batch_id;
      ELSE
        tribe_id := v_t.id; leader_id := v_leader_id;
        notified := false; reason := 'no_signal_skip'; batch_id := NULL;
      END IF;
      RETURN NEXT;
    END LOOP;
  END LOOP;
END;
$function$;

COMMENT ON FUNCTION public.generate_weekly_leader_digest_cron() IS
  'p172 #21 — Multi-leader V4 N:N: LOOP per active leader (leader + co_leader). Each gets 1 notification per tribe. Tribes sem leaders ativos OR is_active=false skipped. Audit row per (tribe, leader) pair.';

NOTIFY pgrst, 'reload schema';
