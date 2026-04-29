-- Phase B'' batch 18.4: upsert_event_minutes V3 researcher 72h sa-bypass → V4 manage_event
-- V3: IF role='researcher' AND NOT is_superadmin AND beyond_72h THEN exception
-- V4: replace `NOT is_superadmin` with `NOT can_by_member('manage_event')`
-- Auth gate _can_manage_event already in place (separate concern)
-- Impact: V3=0 (no researcher who is also sa), V4=0 (no researcher with engagement-based manage_event)
-- Pure refactor with no current effect; semantic-preserving
CREATE OR REPLACE FUNCTION public.upsert_event_minutes(p_event_id uuid, p_text text DEFAULT NULL::text, p_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_event record;
  v_old_text text;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_event FROM events WHERE id = p_event_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Event not found'; END IF;

  IF NOT _can_manage_event(p_event_id) THEN RAISE EXCEPTION 'Unauthorized'; END IF;

  -- Researcher timeframe: can only edit within 72h of event date (V4 manage_event holders bypass)
  IF v_caller.operational_role = 'researcher'
     AND NOT public.can_by_member(v_caller.id, 'manage_event'::text)
     AND v_event.date + interval '72 hours' < now() THEN
    RAISE EXCEPTION 'Edit window expired — researchers can edit within 72h of the event. Contact your tribe leader.';
  END IF;

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

  UPDATE events SET
    minutes_text = COALESCE(p_text, minutes_text),
    minutes_url = COALESCE(p_url, minutes_url),
    minutes_posted_at = CASE WHEN v_old_text IS NULL OR length(trim(COALESCE(v_old_text,''))) = 0 THEN now() ELSE minutes_posted_at END,
    minutes_posted_by = CASE WHEN v_old_text IS NULL OR length(trim(COALESCE(v_old_text,''))) = 0 THEN v_caller.id ELSE minutes_posted_by END,
    minutes_edited_at = CASE WHEN v_old_text IS NOT NULL AND length(trim(v_old_text)) > 0 THEN now() ELSE minutes_edited_at END,
    updated_at = now()
  WHERE id = p_event_id;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller.id, 'event.minutes_updated', 'event', p_event_id,
    jsonb_build_object('has_text', p_text IS NOT NULL, 'has_url', p_url IS NOT NULL,
      'is_edit', v_old_text IS NOT NULL AND length(trim(COALESCE(v_old_text,''))) > 0));

  RETURN jsonb_build_object('success', true);
END;
$function$;
