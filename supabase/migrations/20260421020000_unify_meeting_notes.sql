-- Migration: Unify meeting notes — expand permissions + edit history
-- Rollback: DROP columns minutes_edited_at, minutes_edit_history from events;
--           Re-create _can_manage_event without researcher check;
--           Re-create upsert_event_minutes without edit history/timeframe logic.

-- ============================================================
-- WS6: Add edit tracking columns to events
-- ============================================================

ALTER TABLE events ADD COLUMN IF NOT EXISTS minutes_edited_at timestamptz;
ALTER TABLE events ADD COLUMN IF NOT EXISTS minutes_edit_history jsonb DEFAULT '[]'::jsonb;

-- ============================================================
-- WS1: Expand _can_manage_event — researchers can manage own tribe events
-- ============================================================

CREATE OR REPLACE FUNCTION public._can_manage_event(p_event_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_caller record; v_event record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_caller.is_superadmin THEN RETURN true; END IF;
  IF v_caller.operational_role IN ('manager', 'deputy_manager') THEN RETURN true; END IF;
  SELECT * INTO v_event FROM events WHERE id = p_event_id;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_caller.operational_role = 'tribe_leader' AND v_event.tribe_id = v_caller.tribe_id THEN RETURN true; END IF;
  IF v_caller.operational_role = 'researcher' AND v_event.tribe_id = v_caller.tribe_id THEN RETURN true; END IF;
  IF v_event.created_by = v_caller.id THEN RETURN true; END IF;
  RETURN false;
END; $$;

-- ============================================================
-- WS6: Update upsert_event_minutes — edit history + researcher timeframe
-- ============================================================

CREATE OR REPLACE FUNCTION public.upsert_event_minutes(p_event_id uuid, p_text text DEFAULT NULL, p_url text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_caller record;
  v_event record;
  v_old_text text;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_event FROM events WHERE id = p_event_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Event not found'; END IF;

  -- Permission check via _can_manage_event
  IF NOT _can_manage_event(p_event_id) THEN RAISE EXCEPTION 'Unauthorized'; END IF;

  -- Researcher timeframe: can only edit within 72h of event date
  IF v_caller.operational_role = 'researcher'
     AND NOT v_caller.is_superadmin
     AND v_event.date + interval '72 hours' < now() THEN
    RAISE EXCEPTION 'Edit window expired — researchers can edit within 72h of the event. Contact your tribe leader.';
  END IF;

  -- Save edit history if there was previous content
  v_old_text := v_event.minutes_text;
  IF v_old_text IS NOT NULL AND length(trim(v_old_text)) > 0 AND p_text IS NOT NULL THEN
    UPDATE events SET
      minutes_edit_history = COALESCE(minutes_edit_history, '[]'::jsonb) || jsonb_build_object(
        'edited_by', v_caller.id,
        'edited_by_name', v_caller.name,
        'edited_at', now(),
        'previous_text_hash', encode(sha256(convert_to(v_old_text, 'UTF8')), 'hex'),
        'previous_length', length(v_old_text)
      )
    WHERE id = p_event_id;
  END IF;

  -- Update the event
  UPDATE events SET
    minutes_text = COALESCE(p_text, minutes_text),
    minutes_url = COALESCE(p_url, minutes_url),
    minutes_posted_at = CASE WHEN v_old_text IS NULL OR length(trim(COALESCE(v_old_text,''))) = 0 THEN now() ELSE minutes_posted_at END,
    minutes_posted_by = CASE WHEN v_old_text IS NULL OR length(trim(COALESCE(v_old_text,''))) = 0 THEN v_caller.id ELSE minutes_posted_by END,
    minutes_edited_at = CASE WHEN v_old_text IS NOT NULL AND length(trim(v_old_text)) > 0 THEN now() ELSE minutes_edited_at END,
    updated_at = now()
  WHERE id = p_event_id;

  -- Audit log
  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller.id, 'event.minutes_updated', 'event', p_event_id,
    jsonb_build_object('has_text', p_text IS NOT NULL, 'has_url', p_url IS NOT NULL,
      'is_edit', v_old_text IS NOT NULL AND length(trim(COALESCE(v_old_text,''))) > 0));

  RETURN jsonb_build_object('success', true);
END; $$;
