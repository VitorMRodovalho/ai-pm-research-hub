-- Bug fix: audit_events_changes ainda referenciava NEW.tribe_id,
-- mas events.tribe_id foi DROPADO em ADR-0015 Phase 3e (migration 20260428050000).
-- Toda write em events quebrava com "record 'new' has no field 'tribe_id'".
-- Mesmo bug que Fabrício encontrou via MCP em create_meeting_notes (chain de triggers).
-- Remove refs tribe_id; preserva backward-compat via legacy_tribe_id derivação JOIN initiatives.

CREATE OR REPLACE FUNCTION public.audit_events_changes()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor_id uuid;
  v_auth_id uuid;
  v_source text;
  v_changed_fields text[] := '{}';
  v_k text;
  v_changes jsonb;
  v_metadata jsonb;
  v_target_id uuid;
  v_action text;
  v_legacy_tribe_id int;
BEGIN
  BEGIN
    v_auth_id := auth.uid();
  EXCEPTION WHEN OTHERS THEN
    v_auth_id := NULL;
  END;

  IF v_auth_id IS NOT NULL THEN
    SELECT id INTO v_actor_id FROM public.members WHERE auth_id = v_auth_id LIMIT 1;
    v_source := CASE WHEN v_actor_id IS NULL THEN 'orphan_auth' ELSE 'user' END;
  ELSE
    v_actor_id := NULL;
    v_source := 'system';
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_action := 'event.created';
    v_target_id := NEW.id;
    v_changes := jsonb_build_object('new', to_jsonb(NEW));
    SELECT legacy_tribe_id INTO v_legacy_tribe_id FROM public.initiatives WHERE id = NEW.initiative_id;
    v_metadata := jsonb_build_object(
      'legacy_tribe_id', v_legacy_tribe_id,
      'date', NEW.date,
      'title', NEW.title,
      'initiative_id', NEW.initiative_id,
      'type', NEW.type,
      'source', v_source
    );
  ELSIF TG_OP = 'UPDATE' THEN
    v_action := 'event.updated';
    v_target_id := NEW.id;
    FOR v_k IN
      SELECT key FROM jsonb_each(to_jsonb(NEW))
      WHERE to_jsonb(NEW) -> key IS DISTINCT FROM to_jsonb(OLD) -> key
    LOOP
      v_changed_fields := array_append(v_changed_fields, v_k);
    END LOOP;
    IF array_length(v_changed_fields, 1) IS NULL THEN
      RETURN NEW;
    END IF;
    v_changes := jsonb_build_object(
      'old', to_jsonb(OLD),
      'new', to_jsonb(NEW),
      'changed_fields', to_jsonb(v_changed_fields)
    );
    SELECT legacy_tribe_id INTO v_legacy_tribe_id FROM public.initiatives WHERE id = NEW.initiative_id;
    v_metadata := jsonb_build_object(
      'legacy_tribe_id', v_legacy_tribe_id,
      'date', NEW.date,
      'title', NEW.title,
      'initiative_id', NEW.initiative_id,
      'type', NEW.type,
      'source', v_source
    );
  ELSIF TG_OP = 'DELETE' THEN
    v_action := 'event.deleted';
    v_target_id := OLD.id;
    v_changes := jsonb_build_object('old', to_jsonb(OLD));
    SELECT legacy_tribe_id INTO v_legacy_tribe_id FROM public.initiatives WHERE id = OLD.initiative_id;
    v_metadata := jsonb_build_object(
      'legacy_tribe_id', v_legacy_tribe_id,
      'date', OLD.date,
      'title', OLD.title,
      'initiative_id', OLD.initiative_id,
      'type', OLD.type,
      'source', v_source
    );
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_actor_id, v_action, 'event', v_target_id, v_changes, v_metadata);

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$function$;

NOTIFY pgrst, 'reload schema';
