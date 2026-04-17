-- ============================================================
-- Audit trigger on public.events
-- Captures INSERT/UPDATE/DELETE into admin_audit_log so we can
-- reconstitute "who changed X, when, what" post-hoc. Previously
-- event CRUD was invisible — bug 1 (Fabrício 16/Abr) exposed this.
--
-- Shape:
--   actor_id      = members.id resolved from auth.uid()
--   action        = 'event.created' | 'event.updated' | 'event.deleted'
--   target_type   = 'event'
--   target_id     = events.id
--   changes       = {new: ..., old: ..., changed_fields: [...]}
--   metadata      = {tribe_id, date, title, initiative_id, type, source}
--
-- Edge cases:
--   - auth.uid() NULL (backend / service_role): actor_id = NULL, metadata.source='system'
--   - Mapping auth_id → member.id. If no member found: actor_id NULL, metadata.source='orphan_auth'
--
-- Rollback: DROP TRIGGER + DROP FUNCTION.
-- ============================================================

CREATE OR REPLACE FUNCTION public.audit_events_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
    v_metadata := jsonb_build_object(
      'tribe_id', NEW.tribe_id,
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
    v_metadata := jsonb_build_object(
      'tribe_id', NEW.tribe_id,
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
    v_metadata := jsonb_build_object(
      'tribe_id', OLD.tribe_id,
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
$$;

DROP TRIGGER IF EXISTS trg_audit_events ON public.events;
CREATE TRIGGER trg_audit_events
AFTER INSERT OR UPDATE OR DELETE ON public.events
FOR EACH ROW EXECUTE FUNCTION public.audit_events_changes();

GRANT EXECUTE ON FUNCTION public.audit_events_changes() TO authenticated;
