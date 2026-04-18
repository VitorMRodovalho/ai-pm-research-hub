-- ============================================================================
-- ADR-0015 Phase 3b — DROP COLUMN webinars.tribe_id
--
-- Remove webinars.tribe_id. Readers que ainda incluíam `w.tribe_id` no SELECT
-- são refatorados para derivar via `i.legacy_tribe_id AS tribe_id` (mantém o
-- shape de output — frontend consumers não mudam).
--
-- Reader RPCs refatorados:
--   - list_webinars_v2: SELECT w.tribe_id → SELECT i.legacy_tribe_id AS tribe_id
--   - webinars_pending_comms: mesma mudança
--
-- Pre-drop validation:
--   - 0 views, 0 policies, 0 RLS policies referenciam webinars.tribe_id
--   - Index idx_webinars_tribe não existe (não houve no audit)
--   - FK webinars_tribe_id_fkey auto-dropado
--   - Writer upsert_webinar já refatorado em Step 1 (20260427170000) para
--     escrever inicialmente initiative_id (tribe_id column write removido do
--     Commit 1 refactor)
--   - link_webinar_event: similar
--
-- Nota sobre writer: my ADR-0015 Commit 1 dual-write migration (20260427140000)
-- still writes w.tribe_id = p_tribe_id explicitly. Step 1 V4 sweep
-- (20260427170000) also still writes w.tribe_id. THIS migration must first
-- CREATE OR REPLACE both to remove tribe_id column writes.
--
-- ADR: ADR-0015 Phase 3 (part b — webinars)
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. upsert_webinar — remove tribe_id do INSERT/UPDATE (column gone)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.upsert_webinar(
  p_id uuid DEFAULT NULL::uuid,
  p_title text DEFAULT NULL::text,
  p_description text DEFAULT NULL::text,
  p_scheduled_at timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_duration_min integer DEFAULT 60,
  p_status text DEFAULT 'planned'::text,
  p_chapter_code text DEFAULT 'ALL'::text,
  p_tribe_id integer DEFAULT NULL::integer,
  p_organizer_id uuid DEFAULT NULL::uuid,
  p_co_manager_ids uuid[] DEFAULT '{}'::uuid[],
  p_meeting_link text DEFAULT NULL::text,
  p_youtube_url text DEFAULT NULL::text,
  p_notes text DEFAULT NULL::text,
  p_board_item_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_member_id uuid;
  v_initiative_id uuid;
  v_existing webinars%ROWTYPE;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: not authenticated'; END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  IF p_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.webinars WHERE id = p_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'webinar_not_found'; END IF;

    IF NOT (
      public.can_by_member(v_member_id, 'manage_member')
      OR v_member_id = v_existing.organizer_id
      OR v_member_id = ANY(v_existing.co_manager_ids)
    ) THEN
      RAISE EXCEPTION 'Unauthorized: requires manage_member or organizer role';
    END IF;

    UPDATE public.webinars SET
      title = COALESCE(p_title, title),
      description = COALESCE(p_description, description),
      scheduled_at = COALESCE(p_scheduled_at, scheduled_at),
      duration_min = COALESCE(p_duration_min, duration_min),
      status = COALESCE(p_status, status),
      chapter_code = COALESCE(p_chapter_code, chapter_code),
      initiative_id = v_initiative_id,
      organizer_id = COALESCE(p_organizer_id, organizer_id),
      co_manager_ids = COALESCE(p_co_manager_ids, co_manager_ids),
      meeting_link = p_meeting_link,
      youtube_url = p_youtube_url,
      notes = p_notes,
      board_item_id = p_board_item_id
    WHERE id = p_id;

    SELECT row_to_json(w)::jsonb INTO v_result FROM public.webinars w WHERE w.id = p_id;
  ELSE
    IF NOT public.can_by_member(v_member_id, 'manage_member') THEN
      RAISE EXCEPTION 'Unauthorized: admin role required for webinar creation';
    END IF;

    INSERT INTO public.webinars (title, description, scheduled_at, duration_min, status,
      chapter_code, initiative_id, organizer_id, co_manager_ids, meeting_link,
      youtube_url, notes, board_item_id)
    VALUES (p_title, p_description, p_scheduled_at, p_duration_min, p_status,
      p_chapter_code, v_initiative_id, COALESCE(p_organizer_id, v_member_id),
      p_co_manager_ids, p_meeting_link, p_youtube_url, p_notes, p_board_item_id)
    RETURNING row_to_json(webinars)::jsonb INTO v_result;
  END IF;

  RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. list_webinars_v2 — replace w.tribe_id in SELECT with i.legacy_tribe_id
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.list_webinars_v2(
  p_status text DEFAULT NULL::text,
  p_chapter text DEFAULT NULL::text,
  p_tribe_id integer DEFAULT NULL::integer
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.scheduled_at DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      w.id, w.title, w.description, w.scheduled_at, w.duration_min,
      w.status, w.chapter_code,
      i.legacy_tribe_id AS tribe_id,
      w.organizer_id,
      w.co_manager_ids, w.meeting_link, w.youtube_url, w.notes,
      w.event_id, w.board_item_id,
      w.created_at, w.updated_at,
      m.name AS organizer_name,
      i.title AS tribe_name,
      e.date AS event_date,
      e.type AS event_type,
      (SELECT COUNT(*) FROM public.attendance a WHERE a.event_id = w.event_id AND a.present = true) AS attendee_count,
      (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', cm.id, 'name', cm.name)), '[]'::jsonb)
       FROM public.members cm WHERE cm.id = ANY(w.co_manager_ids)) AS co_managers,
      bi.title AS board_item_title,
      bi.status AS board_item_status
    FROM public.webinars w
    LEFT JOIN public.members m ON m.id = w.organizer_id
    LEFT JOIN public.initiatives i ON i.id = w.initiative_id
    LEFT JOIN public.events e ON e.id = w.event_id
    LEFT JOIN public.board_items bi ON bi.id = w.board_item_id
    WHERE (p_status IS NULL OR w.status = p_status)
      AND (p_chapter IS NULL OR w.chapter_code = p_chapter)
      AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
  ) r;

  RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. webinars_pending_comms — same w.tribe_id → i.legacy_tribe_id
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.webinars_pending_comms()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.scheduled_at), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      w.id, w.title, w.scheduled_at, w.status, w.chapter_code,
      w.meeting_link, w.youtube_url,
      i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name,
      m.name AS organizer_name,
      CASE
        WHEN w.status = 'confirmed' AND w.scheduled_at > now() THEN 'invite'
        WHEN w.status = 'confirmed' AND w.scheduled_at <= now() THEN 'followup'
        WHEN w.status = 'completed' AND w.youtube_url IS NULL THEN 'awaiting_replay'
        WHEN w.status = 'completed' AND w.youtube_url IS NOT NULL THEN 'replay_ready'
        ELSE 'info'
      END AS comms_action,
      CASE
        WHEN w.status = 'confirmed' AND w.scheduled_at > now() THEN 'Preparar convite e lembretes'
        WHEN w.status = 'confirmed' AND w.scheduled_at <= now() THEN 'Preparar follow-up pós-evento'
        WHEN w.status = 'completed' AND w.youtube_url IS NULL THEN 'Aguardando replay para divulgar'
        WHEN w.status = 'completed' AND w.youtube_url IS NOT NULL THEN 'Divulgar replay e materiais'
        ELSE 'Acompanhar'
      END AS comms_label
    FROM public.webinars w
    LEFT JOIN public.initiatives i ON i.id = w.initiative_id
    LEFT JOIN public.members m ON m.id = w.organizer_id
    WHERE w.status IN ('confirmed', 'completed')
    ORDER BY w.scheduled_at
  ) r;

  RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. link_webinar_event — remove v_webinar.tribe_id reference (ROWTYPE no longer has it)
--    Derive event tribe_id from initiatives.legacy_tribe_id via initiative_id JOIN.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.link_webinar_event(
  p_webinar_id uuid,
  p_event_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_member_id uuid;
  v_event_id uuid;
  v_webinar webinars%ROWTYPE;
  v_event_initiative_id uuid;
  v_event_tribe_id integer;
  v_audience text;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  SELECT * INTO v_webinar FROM public.webinars WHERE id = p_webinar_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'webinar_not_found'; END IF;

  IF NOT (
    public.can_by_member(v_member_id, 'manage_member')
    OR v_member_id = v_webinar.organizer_id
    OR v_member_id = ANY(v_webinar.co_manager_ids)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member or organizer role';
  END IF;

  IF p_event_id IS NOT NULL THEN
    v_event_id := p_event_id;
  ELSE
    -- Post-Phase 3b: webinars.tribe_id is gone. Resolve tribe scope from the
    -- webinar's initiative_id via legacy_tribe_id lookup. events.tribe_id
    -- column still exists (Phase 3b doesn't drop it), so we continue to write
    -- it derived — Phase 3 events drop will come in a later beat.
    v_event_initiative_id := v_webinar.initiative_id;
    IF v_event_initiative_id IS NOT NULL THEN
      SELECT legacy_tribe_id INTO v_event_tribe_id
      FROM public.initiatives WHERE id = v_event_initiative_id;
    END IF;

    v_audience := CASE WHEN v_event_tribe_id IS NOT NULL THEN 'tribe' ELSE 'all' END;

    INSERT INTO public.events (title, type, date, duration_minutes, tribe_id, initiative_id,
      meeting_link, youtube_url, audience_level, created_by, source)
    VALUES (
      v_webinar.title, 'webinar', v_webinar.scheduled_at::date,
      v_webinar.duration_min, v_event_tribe_id, v_event_initiative_id,
      v_webinar.meeting_link, v_webinar.youtube_url, v_audience, auth.uid(),
      'webinar_governance'
    )
    RETURNING id INTO v_event_id;
  END IF;

  UPDATE public.webinars SET event_id = v_event_id WHERE id = p_webinar_id;

  INSERT INTO public.webinar_lifecycle_events (webinar_id, action, actor_id, metadata)
  VALUES (p_webinar_id, 'event_linked', v_member_id,
    jsonb_build_object('event_id', v_event_id));

  RETURN jsonb_build_object('ok', true, 'event_id', v_event_id, 'webinar_id', p_webinar_id);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. DROP COLUMN webinars.tribe_id
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.webinars DROP COLUMN tribe_id;

COMMIT;

NOTIFY pgrst, 'reload schema';
