-- p170 Item #17 — Digest leader V3 → V4 migration
--
-- Carry P162_GAP_OPPORTUNITY_LOG item #17 (CARRY p166+p167+p168+p169).
-- Risk identified: get_weekly_tribe_digest:47 + generate_weekly_leader_digest_cron
-- identificam líder via `tribes.leader_member_id` (V3 cache). Cache pode estar stale
-- após mudança V4 sem sync. Digest vai para ex-líder/alumni.
--
-- Drift confirmado pré-migration (2026-05-16):
--   Tribe #3 (TMO & PMO do Futuro):
--     V3 cache leader_member_id → Marcel Fleming (operational_role='alumni', is_active=false)
--     V4 engagements active leader → ZERO (Marcel's engagement expired 2026-03-20)
--   Cron envia digest pra alumni semanalmente desde então.
--
-- Cron: `30 12 * * 6` (Sábado 12:30 UTC = 09:30 BRT). Próximo run após esta migration:
-- 2026-05-23. Migration aplica antes da próxima execução, fechando o vazamento.
--
-- Fix:
--   1. Helper `_v4_tribe_leader_member_id(p_tribe_id)` — canonical V4 lookup via
--      engagements role='leader' status='active' filtered by initiative.legacy_tribe_id
--   2. Refactor get_weekly_tribe_digest():
--      • Auth gate (v_is_leader) usa V4 lookup
--      • Payload field 'leader_member_id' = V4 lookup result
--   3. Refactor generate_weekly_leader_digest_cron():
--      • Iterate active leader engagements (não tribes.leader_member_id IS NOT NULL)
--      • recipient_id = V4 member.id
--   4. One-shot data_anomaly_log: registrar drift V3↔V4 para revisão admin
--
-- Tribes sem V4 leader engagement: cron pula esta tribe + audit log entry.
-- (Anterior: cron enviava digest a stale V3 cache — silenciosamente quebrado.)
--
-- Padrão V4 canonical pattern (extraído de get_initiative_detail @20260422010000):
--   FROM engagements e JOIN persons p ON p.id = e.person_id
--   WHERE e.initiative_id = ? AND e.status = 'active' AND e.role = 'leader'
--
-- Rollback:
--   Restore V3 versions de get_weekly_tribe_digest + generate_weekly_leader_digest_cron
--   DROP FUNCTION _v4_tribe_leader_member_id(integer);

-- ============================================================
-- Helper canonical: V4 leader lookup for tribe (via legacy_tribe_id bridge)
-- ============================================================
CREATE OR REPLACE FUNCTION public._v4_tribe_leader_member_id(p_tribe_id integer)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT m.id
  FROM engagements e
  JOIN members m ON m.person_id = e.person_id
  JOIN initiatives i ON i.id = e.initiative_id
  WHERE i.legacy_tribe_id = p_tribe_id
    AND e.status = 'active'
    AND e.role = 'leader'
  ORDER BY e.start_date DESC
  LIMIT 1;
$function$;

COMMENT ON FUNCTION public._v4_tribe_leader_member_id(integer) IS
  'p170 Item #17 — canonical V4 lookup de tribe leader via engagements (não V3 cache tribes.leader_member_id). Pattern de get_initiative_detail. Returns NULL se sem leader ativo (PM deve assignar).';

-- ============================================================
-- Refactor: get_weekly_tribe_digest — use V4 lookup
-- ============================================================
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

  -- p170 V4 migration: leader via V4 engagements (não V3 cache)
  v_leader_member_id := public._v4_tribe_leader_member_id(p_tribe_id);

  -- Auth gate (unchanged semantically, just uses V4 source)
  IF auth.role() = 'service_role'
     OR current_setting('request.jwt.claims', true) IS NULL THEN
    NULL;
  ELSE
    v_is_leader := (v_caller_id IS NOT NULL AND v_caller_id = v_leader_member_id);
    IF NOT v_is_leader AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
      RAISE EXCEPTION 'Unauthorized: only tribe leader or manage_member can read tribe digest';
    END IF;
  END IF;

  -- Resolve current cycle bounds (NULL-safe)
  SELECT cycle_start::timestamptz, cycle_end::timestamptz
    INTO v_cycle_start, v_cycle_end
  FROM public.cycles WHERE is_current = true LIMIT 1;

  -- Resolve tribe → initiative via V3-V4 bridge (legacy_tribe_id)
  SELECT id INTO v_initiative_id FROM public.initiatives
  WHERE legacy_tribe_id = p_tribe_id
  LIMIT 1;

  SELECT jsonb_build_object(
    'tribe_id', p_tribe_id,
    'tribe_name', v_tribe.name,
    'initiative_id', v_initiative_id,
    'leader_member_id', v_leader_member_id,  -- p170: V4 source
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
          SELECT e.id, e.title, e.date
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
          ORDER BY date DESC
        ),
        top3 AS (SELECT * FROM pending LIMIT 3)
        SELECT jsonb_build_object(
          'count', (SELECT count(*) FROM pending),
          'top_events', COALESCE((SELECT jsonb_agg(
            jsonb_build_object('event_id', id, 'title', title, 'date', date)
          ) FROM top3), '[]'::jsonb)
        )
      ), jsonb_build_object('count', 0, 'top_events', '[]'::jsonb)),

      'champion_pending', COALESCE((
        WITH pending AS (
          SELECT e.id, e.title, e.date
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
          ORDER BY date DESC
        ),
        top3 AS (SELECT * FROM pending LIMIT 3)
        SELECT jsonb_build_object(
          'count', (SELECT count(*) FROM pending),
          'top_events', COALESCE((SELECT jsonb_agg(
            jsonb_build_object('event_id', id, 'title', title, 'date', date)
          ) FROM top3), '[]'::jsonb)
        )
      ), jsonb_build_object('count', 0, 'top_events', '[]'::jsonb))
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.get_weekly_tribe_digest(integer) IS
  'p170 Item #17 — V4 migrated. leader_member_id agora via _v4_tribe_leader_member_id() (engagements role=leader status=active). Pre-p170: V3 cache tribes.leader_member_id (drift risk).';

-- ============================================================
-- Refactor: generate_weekly_leader_digest_cron — iterate V4 engagements
-- ============================================================
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
BEGIN
  -- p170 Item #17: iterate tribes ACTIVE + with V4 leader engagement (não V3 cache)
  FOR v_t IN
    SELECT t.id, t.name,
           public._v4_tribe_leader_member_id(t.id) AS v4_leader_member_id
    FROM public.tribes t
    WHERE t.is_active = true
  LOOP
    v_leader_id := v_t.v4_leader_member_id;

    -- Skip tribes without active V4 leader (was: skip if V3 cache NULL → false negative)
    IF v_leader_id IS NULL THEN
      tribe_id := v_t.id; leader_id := NULL;
      notified := false; reason := 'no_active_v4_leader_engagement'; batch_id := NULL;
      RETURN NEXT;
      CONTINUE;
    END IF;

    SELECT notify_delivery_mode_pref INTO v_leader_pref
    FROM public.members WHERE id = v_leader_id;

    IF v_leader_pref = 'suppress_all' THEN
      tribe_id := v_t.id; leader_id := v_leader_id;
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
      OR (v_digest->'aggregates'->>'cards_completed_window')::int > 0
      OR (v_digest->'aggregates'->'ata_pending'->>'count_events')::int > 0
      OR (v_digest->'aggregates'->'attendance_pending'->>'count')::int > 0
      OR (v_digest->'aggregates'->'champion_pending'->>'count')::int > 0;

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
END;
$function$;

COMMENT ON FUNCTION public.generate_weekly_leader_digest_cron() IS
  'p170 Item #17 — V4 migrated. Iterates tribes ativas + V4 leader via _v4_tribe_leader_member_id(). Tribes sem V4 leader skipped + audit row no_active_v4_leader_engagement (anteriormente cron enviava digest para V3 stale cache).';

-- ============================================================
-- One-shot drift audit: log tribes onde V3 cache ≠ V4 lookup
-- ============================================================
-- Tagged delimiter $audit$ (não $$) para não colidir com kpi-portfolio-health.test.mjs regex
-- que procura o body de exec_portfolio_health via \$\$...\$\$ pattern.
DO $audit$
DECLARE
  v_drift record;
  v_drift_count int := 0;
BEGIN
  FOR v_drift IN
    SELECT
      t.id AS tribe_id, t.name AS tribe_name,
      t.leader_member_id AS v3_cache,
      public._v4_tribe_leader_member_id(t.id) AS v4_active,
      (SELECT name FROM public.members WHERE id = t.leader_member_id) AS v3_name,
      (SELECT name FROM public.members WHERE id = public._v4_tribe_leader_member_id(t.id)) AS v4_name
    FROM public.tribes t
    WHERE t.is_active = true
      AND (t.leader_member_id IS DISTINCT FROM public._v4_tribe_leader_member_id(t.id))
  LOOP
    v_drift_count := v_drift_count + 1;
    INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
    VALUES (
      'tribe_leader_v3_v4_drift',
      'warning',
      format('Tribe %s "%s" — V3 cache aponta %s (%s) mas V4 active engagement aponta %s (%s)',
        v_drift.tribe_id, v_drift.tribe_name,
        COALESCE(v_drift.v3_name, 'NULL'), COALESCE(v_drift.v3_cache::text, 'NULL'),
        COALESCE(v_drift.v4_name, 'NULL'), COALESCE(v_drift.v4_active::text, 'NULL')
      ),
      jsonb_build_object(
        'tribe_id', v_drift.tribe_id,
        'tribe_name', v_drift.tribe_name,
        'v3_cache_member_id', v_drift.v3_cache,
        'v3_cache_member_name', v_drift.v3_name,
        'v4_active_member_id', v_drift.v4_active,
        'v4_active_member_name', v_drift.v4_name,
        'migration', 'p170_item_17_digest_v4',
        'detected_at', now()
      )
    );
  END LOOP;
  RAISE NOTICE 'p170 Item #17 drift audit: % tribes com V3↔V4 leader mismatch logged in data_anomaly_log', v_drift_count;
END $audit$;

NOTIFY pgrst, 'reload schema';
