-- p173 — Initiative-aware weekly digest cron
--
-- Context: p172 #21 enabled multi-leader per tribe. Gap surfaced p173:
-- cron iterates tribes table only. Non-tribe initiatives (workgroups,
-- committees, study_group, congress) with active leaders are invisible
-- to cron. Affected: Herlon (CPMAI study_group), Mayanna/Leticia/Maria Luiza
-- (Hub Comunicação workgroup), Fabricio cross 3 inits (Curadoria/Newsletter/
-- Publicações), Roberto/Sarah (Curadoria/Publicações), Vitor (LATAM LIM).
--
-- Refactor: cron iterates initiatives (not tribes). New helpers + new
-- RPC mirror tribe semantics by initiative_id. Legacy get_weekly_tribe_digest
-- + _v4_tribe_leader_member_id preserved (used by MCP tool + frontend).
-- Notification type unchanged ('weekly_tribe_digest_leader') for email
-- handler back-compat — payload sets tribe_name = initiative_name so
-- existing renderer works for all initiative kinds.

-- ============================================================
-- Helper 1: Active initiatives with at least 1 active leader
-- ============================================================
CREATE OR REPLACE FUNCTION public._v4_active_initiatives_with_leaders()
RETURNS TABLE(initiative_id uuid, name text, kind text, legacy_tribe_id integer)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT DISTINCT i.id, i.title, i.kind, i.legacy_tribe_id
  FROM initiatives i
  WHERE i.status = 'active'
    AND EXISTS (
      SELECT 1 FROM engagements e
      JOIN members m ON m.person_id = e.person_id
      WHERE e.initiative_id = i.id
        AND e.status = 'active'
        AND e.role IN ('leader','co_leader','coordinator','owner')
        AND m.member_status = 'active'
    )
    -- Parity with current cron: skip tribes that are is_active=false
    AND NOT EXISTS (
      SELECT 1 FROM tribes t WHERE t.id = i.legacy_tribe_id AND t.is_active = false
    )
  ORDER BY i.kind, i.title;
$$;

COMMENT ON FUNCTION public._v4_active_initiatives_with_leaders() IS
  'p173: returns (initiative_id, name, kind, legacy_tribe_id) for all active initiatives with >=1 active leader/coordinator engagement. Used by generate_weekly_leader_digest_cron. Excludes tribes with is_active=false (parity with prior cron behavior).';

-- ============================================================
-- Helper 2: Leader member ids by initiative_id
-- ============================================================
CREATE OR REPLACE FUNCTION public._v4_leader_member_ids_by_initiative(p_initiative_id uuid)
RETURNS SETOF uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT DISTINCT m.id
  FROM engagements e
  JOIN members m ON m.person_id = e.person_id
  WHERE e.initiative_id = p_initiative_id
    AND e.status = 'active'
    AND e.role IN ('leader','co_leader','coordinator','owner')
    AND m.member_status = 'active'
  ORDER BY m.id;
$$;

COMMENT ON FUNCTION public._v4_leader_member_ids_by_initiative(uuid) IS
  'p173: returns SETOF member_id for all active leaders/coordinators of an initiative. Includes leader/co_leader/coordinator/owner roles. Filters m.member_status=active. NOT filtered by is_authoritative (cert-pending leaders still get digest).';

-- ============================================================
-- New RPC: get_weekly_initiative_digest(p_initiative_id)
-- Mirrors get_weekly_tribe_digest semantics but parametrized by
-- initiative_id directly. Payload uses tribe_name/tribe_health_pct
-- field names for email handler back-compat.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_weekly_initiative_digest(p_initiative_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_initiative record;
  v_window_start timestamptz := date_trunc('day', now()) - interval '7 days';
  v_cycle_start timestamptz;
  v_cycle_end timestamptz;
  v_is_tribe boolean;
  v_is_leader boolean;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  SELECT * INTO v_initiative FROM public.initiatives WHERE id = p_initiative_id;
  IF v_initiative IS NULL THEN RAISE EXCEPTION 'Initiative not found: %', p_initiative_id; END IF;

  v_is_tribe := (v_initiative.legacy_tribe_id IS NOT NULL);

  -- Auth check: any active leader/coordinator OR manage_member
  IF auth.role() = 'service_role'
     OR current_setting('request.jwt.claims', true) IS NULL THEN
    NULL;
  ELSE
    v_is_leader := EXISTS (
      SELECT 1 FROM public._v4_leader_member_ids_by_initiative(p_initiative_id) lid
      WHERE lid = v_caller_id
    );
    IF NOT v_is_leader AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
      RAISE EXCEPTION 'Unauthorized: only initiative leader/coordinator or manage_member can read initiative digest';
    END IF;
  END IF;

  SELECT cycle_start::timestamptz, cycle_end::timestamptz
    INTO v_cycle_start, v_cycle_end
  FROM public.cycles WHERE is_current = true LIMIT 1;

  SELECT jsonb_build_object(
    'initiative_id', p_initiative_id,
    'initiative_name', v_initiative.title,
    'initiative_kind', v_initiative.kind,
    'legacy_tribe_id', v_initiative.legacy_tribe_id,
    'is_tribe', v_is_tribe,
    -- Back-compat aliases (email handler reads tribe_name + tribe_health_pct)
    'tribe_id', v_initiative.legacy_tribe_id,
    'tribe_name', v_initiative.title,
    'generated_at', now(),
    'window_start', v_window_start,
    'cycle_start', v_cycle_start,
    'cycle_end', v_cycle_end,
    'aggregates', jsonb_build_object(
      'active_members', COALESCE((
        SELECT count(DISTINCT e.person_id) FROM public.engagements e
        WHERE e.initiative_id = p_initiative_id AND e.status = 'active'
      ), 0),
      'members_with_overdue_cards', COALESCE((
        SELECT count(DISTINCT bi.assignee_id) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        WHERE pb.initiative_id = p_initiative_id
          AND bi.status NOT IN ('done', 'archived')
          AND bi.due_date < CURRENT_DATE
      ), 0),
      'cards_overdue_total', COALESCE((
        SELECT count(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        WHERE pb.initiative_id = p_initiative_id
          AND bi.status NOT IN ('done', 'archived') AND bi.due_date < CURRENT_DATE
      ), 0),
      'cards_due_next_7d', COALESCE((
        SELECT count(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        WHERE pb.initiative_id = p_initiative_id
          AND bi.status NOT IN ('done', 'archived')
          AND bi.due_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
      ), 0),
      'cards_without_assignee', COALESCE((
        SELECT count(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        WHERE pb.initiative_id = p_initiative_id
          AND bi.status NOT IN ('done', 'archived') AND bi.assignee_id IS NULL
      ), 0),
      'cards_without_due_date', COALESCE((
        SELECT count(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        WHERE pb.initiative_id = p_initiative_id
          AND bi.status NOT IN ('done', 'archived') AND bi.due_date IS NULL
      ), 0),
      'cards_completed_window', COALESCE((
        SELECT count(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        WHERE pb.initiative_id = p_initiative_id
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
        WHERE pb.initiative_id = p_initiative_id
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
            -- Initiative scope: direct match + (geral with no initiative only when this initiative is a tribe)
            AND (e.initiative_id = p_initiative_id
                 OR (v_is_tribe AND e.type = 'geral' AND e.initiative_id IS NULL))
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
            AND (e.initiative_id = p_initiative_id
                 OR (v_is_tribe AND e.type = 'geral' AND e.initiative_id IS NULL))
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
            AND (e.initiative_id = p_initiative_id
                 OR (v_is_tribe AND e.type = 'geral' AND e.initiative_id IS NULL))
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

COMMENT ON FUNCTION public.get_weekly_initiative_digest(uuid) IS
  'p173: initiative-aware variant of get_weekly_tribe_digest. Same aggregate shape, filter by initiative_id directly (works for tribes via legacy_tribe_id + non-tribe initiatives). Payload aliases tribe_name=initiative_name + tribe_id=legacy_tribe_id for email handler back-compat.';

-- ============================================================
-- Cron: drop + create (RETURNS TABLE signature changes)
-- ============================================================
DROP FUNCTION IF EXISTS public.generate_weekly_leader_digest_cron();

CREATE OR REPLACE FUNCTION public.generate_weekly_leader_digest_cron()
RETURNS TABLE(initiative_id uuid, initiative_name text, leader_id uuid, notified boolean, reason text, batch_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_init record;
  v_leader_id uuid;
  v_digest jsonb;
  v_has_signal boolean;
  v_batch_id uuid := gen_random_uuid();
  v_leader_pref text;
  v_leader_count int;
BEGIN
  FOR v_init IN
    SELECT * FROM public._v4_active_initiatives_with_leaders()
  LOOP
    SELECT count(*) INTO v_leader_count
    FROM public._v4_leader_member_ids_by_initiative(v_init.initiative_id);

    IF v_leader_count = 0 THEN
      initiative_id := v_init.initiative_id;
      initiative_name := v_init.name;
      leader_id := NULL;
      notified := false;
      reason := 'no_active_v4_leader_engagement';
      batch_id := NULL;
      RETURN NEXT;
      CONTINUE;
    END IF;

    v_digest := public.get_weekly_initiative_digest(v_init.initiative_id);

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
      SELECT lid FROM public._v4_leader_member_ids_by_initiative(v_init.initiative_id) lid
    LOOP
      SELECT notify_delivery_mode_pref INTO v_leader_pref
      FROM public.members WHERE id = v_leader_id;

      IF v_leader_pref = 'suppress_all' THEN
        initiative_id := v_init.initiative_id;
        initiative_name := v_init.name;
        leader_id := v_leader_id;
        notified := false;
        reason := 'leader_suppressed_all';
        batch_id := NULL;
        RETURN NEXT;
        CONTINUE;
      END IF;

      IF v_has_signal THEN
        INSERT INTO public.notifications (
          recipient_id, type, title, body, link, source_type, source_id,
          is_read, delivery_mode, digest_batch_id
        ) VALUES (
          v_leader_id,
          'weekly_tribe_digest_leader', -- type unchanged for email handler back-compat
          'Resumo semanal: ' || v_init.name,
          v_digest::text,
          '/admin/portfolio',
          'leader_digest',
          v_batch_id,
          false,
          'transactional_immediate',
          v_batch_id
        );
        initiative_id := v_init.initiative_id;
        initiative_name := v_init.name;
        leader_id := v_leader_id;
        notified := true;
        reason := 'sent';
        batch_id := v_batch_id;
      ELSE
        initiative_id := v_init.initiative_id;
        initiative_name := v_init.name;
        leader_id := v_leader_id;
        notified := false;
        reason := 'no_signal_skip';
        batch_id := NULL;
      END IF;
      RETURN NEXT;
    END LOOP;
  END LOOP;
END;
$function$;

COMMENT ON FUNCTION public.generate_weekly_leader_digest_cron() IS
  'p173: initiative-aware (multi-leader + multi-initiative-kind). LOOP per active initiative (tribes + workgroup + committee + study_group + congress). Each leader/coordinator/owner gets 1 notification. Tribes is_active=false auto-skipped via _v4_active_initiatives_with_leaders. Notification type unchanged for email handler back-compat.';

NOTIFY pgrst, 'reload schema';
