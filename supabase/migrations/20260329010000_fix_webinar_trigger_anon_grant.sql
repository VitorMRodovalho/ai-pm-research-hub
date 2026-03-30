-- Fix: notify_webinar_status_change trigger referenced non-existent columns
-- (fixed_tribe_id, selected_tribe_id) instead of tribe_id
-- Also: grant anon access to list_webinars_v2 for public /webinars page

CREATE OR REPLACE FUNCTION public.notify_webinar_status_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_recipient uuid;
  v_notif_type text;
  v_body text;
  v_link text;
  v_actor_id uuid;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  v_notif_type := 'webinar_status_' || NEW.status;
  v_link := '/admin/webinars';

  SELECT id INTO v_actor_id FROM members WHERE auth_id = auth.uid();

  INSERT INTO webinar_lifecycle_events (webinar_id, action, actor_id, old_status, new_status)
  VALUES (NEW.id, 'status_change', v_actor_id, OLD.status, NEW.status);

  v_body := CASE NEW.status
    WHEN 'confirmed' THEN 'Webinar "' || NEW.title || '" confirmado. Preparar logística e campanha de divulgação.'
    WHEN 'completed' THEN 'Webinar "' || NEW.title || '" realizado. Preparar follow-up, replay e materiais.'
    WHEN 'cancelled' THEN 'Webinar "' || NEW.title || '" cancelado.'
    ELSE 'Webinar "' || NEW.title || '" — status alterado para ' || NEW.status || '.'
  END;

  -- Notify organizer
  IF NEW.organizer_id IS NOT NULL AND NEW.organizer_id IS DISTINCT FROM v_actor_id THEN
    PERFORM create_notification(
      NEW.organizer_id, v_notif_type,
      'Webinar: ' || NEW.title, v_body, v_link,
      'webinar', NEW.id
    );
  END IF;

  -- Notify co-managers
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

  -- Notify comms team on confirm/complete
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

  -- Notify tribe leader (FIXED: use tribe_id, not fixed_tribe_id/selected_tribe_id)
  IF NEW.tribe_id IS NOT NULL AND NEW.status IN ('confirmed', 'completed', 'cancelled') THEN
    FOR v_recipient IN
      SELECT id FROM members
      WHERE tribe_id = NEW.tribe_id
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
$function$;

-- Allow public /webinars page to fetch webinar list without auth
GRANT EXECUTE ON FUNCTION public.list_webinars_v2(text, text, integer) TO anon;
