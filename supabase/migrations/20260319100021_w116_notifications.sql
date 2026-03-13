-- W116: Notification System — Schema + RPCs + Triggers
-- Gap G1.3: Members need in-app notifications for assignments, reviews, etc.

-- ── Tables ──

CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id uuid REFERENCES members(id) NOT NULL,
  type text NOT NULL,
  title text NOT NULL,
  body text,
  link text,
  source_type text,
  source_id uuid,
  is_read boolean DEFAULT false,
  read_at timestamptz,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notif_recipient ON notifications(recipient_id);
CREATE INDEX IF NOT EXISTS idx_notif_unread ON notifications(recipient_id, is_read) WHERE is_read = false;
CREATE INDEX IF NOT EXISTS idx_notif_created ON notifications(created_at DESC);

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notif_select_own" ON notifications
  FOR SELECT TO authenticated
  USING (recipient_id = (SELECT id FROM members WHERE auth_id = auth.uid()));

CREATE POLICY "notif_insert_system" ON notifications
  FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  member_id uuid PRIMARY KEY REFERENCES members(id),
  in_app boolean DEFAULT true,
  email_digest boolean DEFAULT true,
  digest_frequency text DEFAULT 'weekly'
    CHECK (digest_frequency IN ('daily','weekly','never')),
  muted_types text[] DEFAULT '{}',
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notifpref_own" ON notification_preferences
  FOR ALL TO authenticated
  USING (member_id = (SELECT id FROM members WHERE auth_id = auth.uid()));

-- ── Core RPC: create_notification ──
CREATE OR REPLACE FUNCTION create_notification(
  p_recipient_id uuid,
  p_type text,
  p_title text,
  p_body text DEFAULT NULL,
  p_link text DEFAULT NULL,
  p_source_type text DEFAULT NULL,
  p_source_id uuid DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_prefs notification_preferences%ROWTYPE;
BEGIN
  -- Check preferences
  SELECT * INTO v_prefs FROM notification_preferences WHERE member_id = p_recipient_id;
  IF FOUND THEN
    IF NOT v_prefs.in_app THEN RETURN; END IF;
    IF p_type = ANY(v_prefs.muted_types) THEN RETURN; END IF;
  END IF;

  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
  VALUES (p_recipient_id, p_type, p_title, p_body, p_link, p_source_type, p_source_id);
END;
$$;

-- ── RPC: get_my_notifications ──
CREATE OR REPLACE FUNCTION get_my_notifications(
  p_limit int DEFAULT 20,
  p_unread_only boolean DEFAULT false
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_member_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'auth_required'; END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(r)), '[]'::jsonb) INTO v_result
  FROM (
    SELECT id, type, title, body, link, source_type, source_id, is_read, created_at
    FROM notifications
    WHERE recipient_id = v_member_id
      AND (NOT p_unread_only OR is_read = false)
    ORDER BY created_at DESC
    LIMIT p_limit
  ) r;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_my_notifications TO authenticated;

-- ── RPC: mark_notification_read ──
CREATE OR REPLACE FUNCTION mark_notification_read(p_notification_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE notifications SET is_read = true, read_at = now()
  WHERE id = p_notification_id
    AND recipient_id = (SELECT id FROM members WHERE auth_id = auth.uid());
END;
$$;

GRANT EXECUTE ON FUNCTION mark_notification_read TO authenticated;

-- ── RPC: mark_all_notifications_read ──
CREATE OR REPLACE FUNCTION mark_all_notifications_read()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE notifications SET is_read = true, read_at = now()
  WHERE recipient_id = (SELECT id FROM members WHERE auth_id = auth.uid())
    AND is_read = false;
END;
$$;

GRANT EXECUTE ON FUNCTION mark_all_notifications_read TO authenticated;

-- ── RPC: get_notification_count ──
CREATE OR REPLACE FUNCTION get_notification_count()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM notifications
  WHERE recipient_id = (SELECT id FROM members WHERE auth_id = auth.uid())
    AND is_read = false;
  RETURN COALESCE(v_count, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION get_notification_count TO authenticated;

-- ── RPC: update_notification_preferences ──
CREATE OR REPLACE FUNCTION update_notification_preferences(p_prefs jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'auth_required'; END IF;

  INSERT INTO notification_preferences (member_id, in_app, email_digest, digest_frequency, muted_types, updated_at)
  VALUES (
    v_member_id,
    COALESCE((p_prefs->>'in_app')::boolean, true),
    COALESCE((p_prefs->>'email_digest')::boolean, true),
    COALESCE(p_prefs->>'digest_frequency', 'weekly'),
    COALESCE(ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_prefs->'muted_types','[]'::jsonb))), '{}'),
    now()
  )
  ON CONFLICT (member_id) DO UPDATE SET
    in_app = COALESCE((p_prefs->>'in_app')::boolean, notification_preferences.in_app),
    email_digest = COALESCE((p_prefs->>'email_digest')::boolean, notification_preferences.email_digest),
    digest_frequency = COALESCE(p_prefs->>'digest_frequency', notification_preferences.digest_frequency),
    muted_types = COALESCE(ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_prefs->'muted_types','[]'::jsonb))), notification_preferences.muted_types),
    updated_at = now();

  RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION update_notification_preferences TO authenticated;

-- ── Trigger: Assignment notifications ──
CREATE OR REPLACE FUNCTION notify_on_assignment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_title text;
  v_tribe_id int;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT bi.title INTO v_title FROM board_items bi WHERE bi.id = NEW.item_id;
    BEGIN
      SELECT pb.tribe_id INTO v_tribe_id
      FROM board_items bi JOIN project_boards pb ON pb.id = bi.board_id
      WHERE bi.id = NEW.item_id;
    EXCEPTION WHEN OTHERS THEN v_tribe_id := NULL;
    END;

    PERFORM create_notification(
      NEW.member_id,
      'assignment_new',
      'Novo card atribuído',
      'Você foi atribuído ao card "' || COALESCE(v_title, '?') || '" como ' || NEW.role,
      CASE WHEN v_tribe_id IS NOT NULL THEN '/tribe/' || v_tribe_id || '?tab=board' ELSE '/workspace' END,
      'board_item',
      NEW.item_id
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_assignment ON board_item_assignments;
CREATE TRIGGER trg_notify_assignment
  AFTER INSERT ON board_item_assignments
  FOR EACH ROW EXECUTE FUNCTION notify_on_assignment();

-- ── Trigger: Curation event notifications ──
CREATE OR REPLACE FUNCTION notify_on_curation_status_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_assignee record;
BEGIN
  -- Notify all assignees when curation_status changes
  IF NEW.curation_status IS DISTINCT FROM OLD.curation_status
    AND NEW.curation_status IS NOT NULL
    AND NEW.curation_status != 'draft' THEN

    FOR v_assignee IN
      SELECT bia.member_id FROM board_item_assignments bia WHERE bia.item_id = NEW.id
    LOOP
      PERFORM create_notification(
        v_assignee.member_id,
        'card_moved',
        'Status de curadoria alterado',
        '"' || NEW.title || '" agora está em: ' || NEW.curation_status,
        '/workspace',
        'board_item',
        NEW.id
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_curation_status ON board_items;
CREATE TRIGGER trg_notify_curation_status
  AFTER UPDATE OF curation_status ON board_items
  FOR EACH ROW EXECUTE FUNCTION notify_on_curation_status_change();
