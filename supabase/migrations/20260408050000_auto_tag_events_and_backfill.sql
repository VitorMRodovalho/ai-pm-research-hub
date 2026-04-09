-- Auto-tag events by type + cycle on INSERT
-- Also backfills existing events missing type-based system tags

-- 1. Trigger function
CREATE OR REPLACE FUNCTION auto_tag_event_by_type()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_tag_name text;
  v_tag_id uuid;
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
    IF v_tag_id IS NOT NULL THEN
      INSERT INTO event_tag_assignments (event_id, tag_id)
      VALUES (NEW.id, v_tag_id)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_tag_event ON events;
CREATE TRIGGER trg_auto_tag_event
  AFTER INSERT ON events
  FOR EACH ROW
  EXECUTE FUNCTION auto_tag_event_by_type();

-- 2. Backfill: assign type-based tags to events missing them
WITH type_tag_map AS (
  SELECT 'geral' as event_type, 'general_meeting' as tag_name
  UNION ALL SELECT 'tribo', 'tribe_meeting'
  UNION ALL SELECT 'kickoff', 'kickoff'
  UNION ALL SELECT 'lideranca', 'leadership_meeting'
  UNION ALL SELECT 'entrevista', 'interview'
  UNION ALL SELECT 'evento_externo', 'external_event'
  UNION ALL SELECT 'webinar', 'webinar'
)
INSERT INTO event_tag_assignments (event_id, tag_id)
SELECT e.id, t.id
FROM events e
JOIN type_tag_map m ON m.event_type = e.type
JOIN tags t ON t.name = m.tag_name
WHERE NOT EXISTS (
  SELECT 1 FROM event_tag_assignments eta WHERE eta.event_id = e.id AND eta.tag_id = t.id
)
ON CONFLICT DO NOTHING;

-- 3. Backfill: assign ciclo_3 tag to all cycle 3 events
INSERT INTO event_tag_assignments (event_id, tag_id)
SELECT e.id, t.id
FROM events e
CROSS JOIN tags t
WHERE t.name = 'ciclo_3'
  AND e.date >= '2026-03-05'
  AND NOT EXISTS (
    SELECT 1 FROM event_tag_assignments eta WHERE eta.event_id = e.id AND eta.tag_id = t.id
  )
ON CONFLICT DO NOTHING;
