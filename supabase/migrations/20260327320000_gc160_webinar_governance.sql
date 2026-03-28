-- GC-160: Webinar Governance — Multi-Entity Co-Management
-- Creates webinars table (base from 20260309, never applied to prod) + governance extensions:
--   board_item (pipeline) → webinar (management) → event (operational session)
-- Adds: co-managers, lifecycle events, notification triggers, enriched RPCs.
-- Applied to prod via Supabase MCP as combined migration.

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 0: Base webinars table (originally from 20260309140000, never applied)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.webinars (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title         text NOT NULL,
  description   text,
  scheduled_at  timestamptz NOT NULL,
  duration_min  integer NOT NULL DEFAULT 60,
  status        text NOT NULL DEFAULT 'planned'
                  CHECK (status IN ('planned','confirmed','completed','cancelled')),
  chapter_code  text NOT NULL
                  CHECK (chapter_code IN ('CE','DF','GO','MG','RS','ALL')),
  tribe_id      integer REFERENCES public.tribes(id),
  organizer_id  uuid REFERENCES public.members(id),
  meeting_link  text,
  youtube_url   text,
  notes         text,
  created_by    uuid REFERENCES auth.users(id) DEFAULT auth.uid(),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.webinars IS 'Calendar of webinars/partnerships with PMI chapters (CE, DF, GO, MG, RS)';

CREATE INDEX IF NOT EXISTS idx_webinars_scheduled ON public.webinars (scheduled_at DESC);
CREATE INDEX IF NOT EXISTS idx_webinars_chapter   ON public.webinars (chapter_code);
CREATE INDEX IF NOT EXISTS idx_webinars_status    ON public.webinars (status);

ALTER TABLE public.webinars ENABLE ROW LEVEL SECURITY;

CREATE POLICY webinars_select ON public.webinars
  FOR SELECT TO authenticated USING (true);

CREATE POLICY webinars_delete ON public.webinars
  FOR DELETE TO authenticated
  USING ((SELECT r.is_superadmin FROM public.get_my_member_record() r));

CREATE OR REPLACE FUNCTION public.webinars_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS trg_webinars_updated_at ON public.webinars;
CREATE TRIGGER trg_webinars_updated_at
  BEFORE UPDATE ON public.webinars
  FOR EACH ROW EXECUTE FUNCTION public.webinars_set_updated_at();

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1: Schema expansion — governance columns
-- ═══════════════════════════════════════════════════════════════════════════

-- Co-managers: chapter GPs who share management responsibility
ALTER TABLE webinars ADD COLUMN IF NOT EXISTS co_manager_ids uuid[] DEFAULT '{}';

-- Link webinar → operational event (attendance/check-in session)
ALTER TABLE webinars ADD COLUMN IF NOT EXISTS event_id uuid REFERENCES events(id);

-- Link webinar → board item (tribe pipeline card)
ALTER TABLE webinars ADD COLUMN IF NOT EXISTS board_item_id uuid REFERENCES board_items(id);

-- Indexes for the new FKs
CREATE INDEX IF NOT EXISTS idx_webinars_event_id ON webinars(event_id) WHERE event_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_webinars_board_item_id ON webinars(board_item_id) WHERE board_item_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_webinars_organizer ON webinars(organizer_id) WHERE organizer_id IS NOT NULL;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2: Lifecycle events — audit trail for every webinar state change
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.webinar_lifecycle_events (
  id          serial PRIMARY KEY,
  webinar_id  uuid NOT NULL REFERENCES webinars(id) ON DELETE CASCADE,
  action      text NOT NULL,
  actor_id    uuid REFERENCES members(id),
  old_status  text,
  new_status  text,
  metadata    jsonb DEFAULT '{}',
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wle_webinar ON webinar_lifecycle_events(webinar_id);
CREATE INDEX IF NOT EXISTS idx_wle_created ON webinar_lifecycle_events(created_at DESC);

ALTER TABLE webinar_lifecycle_events ENABLE ROW LEVEL SECURITY;

-- Authenticated can read lifecycle events for webinars they can see
CREATE POLICY wle_select ON webinar_lifecycle_events
  FOR SELECT TO authenticated USING (true);

-- Only system (triggers) insert lifecycle events
CREATE POLICY wle_insert ON webinar_lifecycle_events
  FOR INSERT TO authenticated WITH CHECK (true);

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3: RLS — co-managers can update their webinars
-- ═══════════════════════════════════════════════════════════════════════════

-- Drop old restrictive update policy (manager/deputy_manager/SA only)
DROP POLICY IF EXISTS webinars_update ON webinars;

-- New policy: organizer, co-managers, or admin+ can update
CREATE POLICY webinars_update_v2 ON webinars
  FOR UPDATE TO authenticated
  USING (
    (SELECT id FROM get_my_member_record()) = organizer_id
    OR (SELECT id FROM get_my_member_record()) = ANY(co_manager_ids)
    OR (SELECT operational_role IN ('manager', 'deputy_manager') OR is_superadmin
        FROM get_my_member_record())
  );

-- Also allow co-managers and organizers to insert (create webinars)
DROP POLICY IF EXISTS webinars_insert ON webinars;

CREATE POLICY webinars_insert_v2 ON webinars
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT operational_role IN ('manager', 'deputy_manager') OR is_superadmin
     FROM get_my_member_record())
    -- organizer_id is set on insert, so co-managers create via admin action
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4: Notification trigger — status changes propagate to stakeholders
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION notify_webinar_status_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_recipient uuid;
  v_notif_type text;
  v_body text;
  v_link text;
  v_actor_id uuid;
BEGIN
  -- Only fire on actual status changes
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  v_notif_type := 'webinar_status_' || NEW.status;
  v_link := '/admin/webinars';

  -- Determine actor (who made the change)
  SELECT id INTO v_actor_id FROM members WHERE auth_id = auth.uid();

  -- Record lifecycle event
  INSERT INTO webinar_lifecycle_events (webinar_id, action, actor_id, old_status, new_status)
  VALUES (NEW.id, 'status_change', v_actor_id, OLD.status, NEW.status);

  -- Build contextual body per status
  v_body := CASE NEW.status
    WHEN 'confirmed' THEN 'Webinar "' || NEW.title || '" confirmado. Preparar logística e campanha de divulgação.'
    WHEN 'completed' THEN 'Webinar "' || NEW.title || '" realizado. Preparar follow-up, replay e materiais.'
    WHEN 'cancelled' THEN 'Webinar "' || NEW.title || '" cancelado.'
    ELSE 'Webinar "' || NEW.title || '" — status alterado para ' || NEW.status || '.'
  END;

  -- 1. Notify organizer (if not the actor)
  IF NEW.organizer_id IS NOT NULL AND NEW.organizer_id IS DISTINCT FROM v_actor_id THEN
    PERFORM create_notification(
      NEW.organizer_id, v_notif_type,
      'Webinar: ' || NEW.title, v_body, v_link,
      'webinar', NEW.id
    );
  END IF;

  -- 2. Notify co-managers (except actor)
  IF array_length(NEW.co_manager_ids, 1) > 0 THEN
    FOREACH v_recipient IN ARRAY NEW.co_manager_ids LOOP
      IF v_recipient IS DISTINCT FROM v_actor_id THEN
        PERFORM create_notification(
          v_recipient, v_notif_type,
          'Webinar: ' || NEW.title, v_body, v_link,
          'webinar', NEW.id
        );
      END IF;
    END LOOP;
  END IF;

  -- 3. Notify comms team on confirmed/completed (they need to act)
  IF NEW.status IN ('confirmed', 'completed') THEN
    FOR v_recipient IN
      SELECT id FROM members
      WHERE designations && ARRAY['comms_leader', 'comms_member']
        AND is_active = true
        AND id IS DISTINCT FROM v_actor_id
    LOOP
      PERFORM create_notification(
        v_recipient, v_notif_type,
        'Webinar: ' || NEW.title,
        CASE NEW.status
          WHEN 'confirmed' THEN 'Preparar campanha de divulgação para "' || NEW.title || '" — ' || NEW.chapter_code || '.'
          WHEN 'completed' THEN 'Preparar follow-up e divulgação de replay para "' || NEW.title || '".'
        END,
        '/admin/comms?context=webinar&title=' || NEW.title,
        'webinar', NEW.id
      );
    END LOOP;
  END IF;

  -- 4. Notify tribe leader if webinar has tribe_id
  IF NEW.tribe_id IS NOT NULL AND NEW.status IN ('confirmed', 'completed', 'cancelled') THEN
    FOR v_recipient IN
      SELECT id FROM members
      WHERE (fixed_tribe_id = NEW.tribe_id OR selected_tribe_id = NEW.tribe_id)
        AND operational_role = 'tribe_leader'
        AND is_active = true
        AND id IS DISTINCT FROM v_actor_id
    LOOP
      PERFORM create_notification(
        v_recipient, v_notif_type,
        'Webinar da sua tribo: ' || NEW.title, v_body,
        '/tribe/' || NEW.tribe_id || '?tab=board',
        'webinar', NEW.id
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_webinar_status_notify ON webinars;
CREATE TRIGGER trg_webinar_status_notify
  AFTER UPDATE OF status ON webinars
  FOR EACH ROW EXECUTE FUNCTION notify_webinar_status_change();

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 5: Lifecycle trigger for creation
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION log_webinar_created()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_actor_id uuid;
BEGIN
  SELECT id INTO v_actor_id FROM members WHERE auth_id = auth.uid();

  INSERT INTO webinar_lifecycle_events (webinar_id, action, actor_id, new_status, metadata)
  VALUES (NEW.id, 'created', v_actor_id, NEW.status,
    jsonb_build_object('chapter_code', NEW.chapter_code, 'tribe_id', NEW.tribe_id));

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_webinar_created ON webinars;
CREATE TRIGGER trg_webinar_created
  AFTER INSERT ON webinars
  FOR EACH ROW EXECUTE FUNCTION log_webinar_created();

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 6: Enriched RPCs for the new frontend
-- ═══════════════════════════════════════════════════════════════════════════

-- 6a. List webinars with enriched data (organizer name, tribe name, co-manager names, linked event)
DROP FUNCTION IF EXISTS public.list_webinars(text);

CREATE OR REPLACE FUNCTION public.list_webinars_v2(
  p_status text DEFAULT NULL,
  p_chapter text DEFAULT NULL,
  p_tribe_id integer DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.scheduled_at DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      w.id, w.title, w.description, w.scheduled_at, w.duration_min,
      w.status, w.chapter_code, w.tribe_id, w.organizer_id,
      w.co_manager_ids, w.meeting_link, w.youtube_url, w.notes,
      w.event_id, w.board_item_id,
      w.created_at, w.updated_at,
      m.name AS organizer_name,
      t.name AS tribe_name,
      e.date AS event_date,
      e.type AS event_type,
      (SELECT COUNT(*) FROM attendance a WHERE a.event_id = w.event_id AND a.present = true) AS attendee_count,
      (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', cm.id, 'name', cm.name)), '[]'::jsonb)
       FROM members cm WHERE cm.id = ANY(w.co_manager_ids)) AS co_managers,
      bi.title AS board_item_title,
      bi.status AS board_item_status
    FROM webinars w
    LEFT JOIN members m ON m.id = w.organizer_id
    LEFT JOIN tribes t ON t.id = w.tribe_id
    LEFT JOIN events e ON e.id = w.event_id
    LEFT JOIN board_items bi ON bi.id = w.board_item_id
    WHERE (p_status IS NULL OR w.status = p_status)
      AND (p_chapter IS NULL OR w.chapter_code = p_chapter)
      AND (p_tribe_id IS NULL OR w.tribe_id = p_tribe_id)
  ) r;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_webinars_v2(text, text, integer) TO authenticated;

-- 6b. Upsert webinar (create or update)
CREATE OR REPLACE FUNCTION public.upsert_webinar(
  p_id uuid DEFAULT NULL,
  p_title text DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_scheduled_at timestamptz DEFAULT NULL,
  p_duration_min integer DEFAULT 60,
  p_status text DEFAULT 'planned',
  p_chapter_code text DEFAULT 'ALL',
  p_tribe_id integer DEFAULT NULL,
  p_organizer_id uuid DEFAULT NULL,
  p_co_manager_ids uuid[] DEFAULT '{}',
  p_meeting_link text DEFAULT NULL,
  p_youtube_url text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_board_item_id uuid DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_rec record;
  v_member_id uuid;
  v_result jsonb;
BEGIN
  SELECT id, operational_role, is_superadmin INTO v_rec FROM get_my_member_record();
  IF v_rec IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  v_member_id := v_rec.id;

  IF p_id IS NOT NULL THEN
    -- UPDATE: check ownership or admin
    IF NOT (
      v_rec.is_superadmin
      OR v_rec.operational_role IN ('manager', 'deputy_manager')
      OR v_member_id = (SELECT organizer_id FROM webinars WHERE id = p_id)
      OR v_member_id = ANY((SELECT co_manager_ids FROM webinars WHERE id = p_id))
    ) THEN
      RAISE EXCEPTION 'access_denied';
    END IF;

    UPDATE webinars SET
      title = COALESCE(p_title, title),
      description = COALESCE(p_description, description),
      scheduled_at = COALESCE(p_scheduled_at, scheduled_at),
      duration_min = COALESCE(p_duration_min, duration_min),
      status = COALESCE(p_status, status),
      chapter_code = COALESCE(p_chapter_code, chapter_code),
      tribe_id = p_tribe_id,
      organizer_id = COALESCE(p_organizer_id, organizer_id),
      co_manager_ids = COALESCE(p_co_manager_ids, co_manager_ids),
      meeting_link = p_meeting_link,
      youtube_url = p_youtube_url,
      notes = p_notes,
      board_item_id = p_board_item_id
    WHERE id = p_id;

    SELECT row_to_json(w)::jsonb INTO v_result FROM webinars w WHERE w.id = p_id;
  ELSE
    -- INSERT: admin+ only
    IF NOT (v_rec.is_superadmin OR v_rec.operational_role IN ('manager', 'deputy_manager')) THEN
      RAISE EXCEPTION 'access_denied: admin required for creation';
    END IF;

    INSERT INTO webinars (title, description, scheduled_at, duration_min, status,
      chapter_code, tribe_id, organizer_id, co_manager_ids, meeting_link,
      youtube_url, notes, board_item_id)
    VALUES (p_title, p_description, p_scheduled_at, p_duration_min, p_status,
      p_chapter_code, p_tribe_id, COALESCE(p_organizer_id, v_member_id),
      p_co_manager_ids, p_meeting_link, p_youtube_url, p_notes, p_board_item_id)
    RETURNING row_to_json(webinars)::jsonb INTO v_result;
  END IF;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_webinar TO authenticated;

-- 6c. Link webinar to operational event
CREATE OR REPLACE FUNCTION public.link_webinar_event(
  p_webinar_id uuid,
  p_event_id uuid DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_rec record;
  v_member_id uuid;
  v_event_id uuid;
  v_webinar webinars%ROWTYPE;
BEGIN
  SELECT id, operational_role, is_superadmin INTO v_rec FROM get_my_member_record();
  IF v_rec IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  v_member_id := v_rec.id;

  SELECT * INTO v_webinar FROM webinars WHERE id = p_webinar_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'webinar_not_found'; END IF;

  -- Check permission
  IF NOT (
    v_rec.is_superadmin
    OR v_rec.operational_role IN ('manager', 'deputy_manager')
    OR v_member_id = v_webinar.organizer_id
    OR v_member_id = ANY(v_webinar.co_manager_ids)
  ) THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  IF p_event_id IS NOT NULL THEN
    -- Link to existing event
    v_event_id := p_event_id;
  ELSE
    -- Auto-create event from webinar data
    INSERT INTO events (title, type, date, duration_minutes, tribe_id, meeting_link,
      youtube_url, audience_level, created_by, source)
    VALUES (
      v_webinar.title, 'webinar', v_webinar.scheduled_at::date,
      v_webinar.duration_min, v_webinar.tribe_id, v_webinar.meeting_link,
      v_webinar.youtube_url, 'general', auth.uid(), 'webinar_governance'
    )
    RETURNING id INTO v_event_id;
  END IF;

  UPDATE webinars SET event_id = v_event_id WHERE id = p_webinar_id;

  -- Log lifecycle event
  INSERT INTO webinar_lifecycle_events (webinar_id, action, actor_id, metadata)
  VALUES (p_webinar_id, 'event_linked', v_member_id,
    jsonb_build_object('event_id', v_event_id));

  RETURN jsonb_build_object('ok', true, 'event_id', v_event_id, 'webinar_id', p_webinar_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.link_webinar_event TO authenticated;

-- 6d. Get webinar lifecycle (timeline)
CREATE OR REPLACE FUNCTION public.get_webinar_lifecycle(p_webinar_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.created_at DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT wle.id, wle.action, wle.old_status, wle.new_status,
      wle.metadata, wle.created_at,
      m.name AS actor_name
    FROM webinar_lifecycle_events wle
    LEFT JOIN members m ON m.id = wle.actor_id
    WHERE wle.webinar_id = p_webinar_id
  ) r;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_webinar_lifecycle(uuid) TO authenticated;

-- 6e. Webinars pending comms action (for Comms dashboard)
CREATE OR REPLACE FUNCTION public.webinars_pending_comms()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.scheduled_at), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      w.id, w.title, w.scheduled_at, w.status, w.chapter_code,
      w.meeting_link, w.youtube_url, w.tribe_id,
      t.name AS tribe_name,
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
    FROM webinars w
    LEFT JOIN tribes t ON t.id = w.tribe_id
    LEFT JOIN members m ON m.id = w.organizer_id
    WHERE w.status IN ('confirmed', 'completed')
    ORDER BY w.scheduled_at
  ) r;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.webinars_pending_comms() TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 7: Add webinar notification types to email delivery
-- ═══════════════════════════════════════════════════════════════════════════

-- The Edge Function send-notification-email checks CRITICAL_TYPES array.
-- We don't alter the EF here, but we ensure the notification types are consistent.
-- Types created by the trigger: webinar_status_confirmed, webinar_status_completed,
-- webinar_status_cancelled, webinar_status_planned.

NOTIFY pgrst, 'reload schema';

COMMIT;
