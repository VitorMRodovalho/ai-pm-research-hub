-- Fix 2 triggers latentes com refs NEW.tribe_id em tabelas onde coluna
-- foi droppada em ADR-0015 Phase 3 (Phase 3d project_boards, Phase 3e events).
-- Bloqueavam writes em events + board_items (incluindo via MCP).
-- Pattern: derivar legacy_tribe_id via JOIN initiatives.

-- (1) auto_tag_event_by_type: events.tribe_id → derivação via initiative_id
CREATE OR REPLACE FUNCTION public.auto_tag_event_by_type()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_tag_name text;
  v_tag_id uuid;
  v_legacy_tribe_id int;
BEGIN
  v_tag_name := CASE NEW.type
    WHEN 'geral' THEN 'general_meeting'
    WHEN 'tribo' THEN 'tribe_meeting'
    WHEN 'kickoff' THEN 'kickoff'
    WHEN 'lideranca' THEN 'leadership_meeting'
    WHEN 'entrevista' THEN 'interview'
    WHEN 'evento_externo' THEN 'external_event'
    WHEN 'webinar' THEN 'webinar'
    ELSE NULL
  END;

  IF v_tag_name IS NOT NULL THEN
    SELECT id INTO v_tag_id FROM tags WHERE name = v_tag_name LIMIT 1;
    IF v_tag_id IS NOT NULL THEN
      INSERT INTO event_tag_assignments (event_id, tag_id)
      VALUES (NEW.id, v_tag_id)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  IF NEW.date >= '2026-03-05' THEN
    SELECT id INTO v_tag_id FROM tags WHERE name = 'ciclo_3' LIMIT 1;
  ELSIF NEW.date >= '2025-07-01' THEN
    SELECT id INTO v_tag_id FROM tags WHERE name = 'ciclo_2' LIMIT 1;
  ELSE
    v_tag_id := NULL;
  END IF;
  IF v_tag_id IS NOT NULL THEN
    INSERT INTO event_tag_assignments (event_id, tag_id)
    VALUES (NEW.id, v_tag_id)
    ON CONFLICT DO NOTHING;
  END IF;

  -- ADR-0015: derivar legacy_tribe_id via JOIN initiatives (events.tribe_id dropado Phase 3e)
  IF NEW.initiative_id IS NOT NULL THEN
    SELECT legacy_tribe_id INTO v_legacy_tribe_id
    FROM public.initiatives WHERE id = NEW.initiative_id;
    IF v_legacy_tribe_id IS NOT NULL THEN
      SELECT id INTO v_tag_id FROM tags WHERE name = 'tribe_' || v_legacy_tribe_id LIMIT 1;
      IF v_tag_id IS NOT NULL THEN
        INSERT INTO event_tag_assignments (event_id, tag_id)
        VALUES (NEW.id, v_tag_id)
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

-- (2) notify_leader_on_review: board_items.tribe_id → via project_boards → initiative_id
CREATE OR REPLACE FUNCTION public.notify_leader_on_review()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_leader_id uuid;
  v_actor_id uuid;
  v_legacy_tribe_id int;
BEGIN
  IF NEW.curation_status = 'leader_review' AND (OLD.curation_status IS NULL OR OLD.curation_status != 'leader_review') THEN
    -- ADR-0015: board_items.tribe_id dropado Phase 3d; derivar via project_boards → initiative → legacy_tribe_id
    SELECT i.legacy_tribe_id INTO v_legacy_tribe_id
    FROM public.project_boards pb
    JOIN public.initiatives i ON i.id = pb.initiative_id
    WHERE pb.id = NEW.board_id;

    IF v_legacy_tribe_id IS NOT NULL THEN
      SELECT m.id INTO v_leader_id FROM public.members m
      WHERE m.tribe_id = v_legacy_tribe_id
        AND m.operational_role = 'tribe_leader'
        AND m.is_active = true
      LIMIT 1;

      SELECT id INTO v_actor_id FROM public.members WHERE auth_id = auth.uid();

      IF v_leader_id IS NOT NULL THEN
        PERFORM create_notification(
          v_leader_id, 'leader_review_requested', 'board_item', NEW.id, NEW.title, v_actor_id,
          'Card pronto para revisao do lider'
        );
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

NOTIFY pgrst, 'reload schema';
