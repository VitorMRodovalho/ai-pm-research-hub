-- ============================================================
-- Issue #68: Meeting notes UX — backend for /meetings page
-- Adds full-text search index + RPCs for the dedicated meetings view
-- ============================================================

-- 1. Full-text search index on minutes_text + title + agenda
CREATE INDEX IF NOT EXISTS idx_events_minutes_fts ON events
USING GIN (
  to_tsvector('portuguese',
    coalesce(title, '') || ' ' ||
    coalesce(minutes_text, '') || ' ' ||
    coalesce(agenda_text, '')
  )
);

-- 2. RPC: list all events with meeting notes, filterable by tribe/type/search
CREATE OR REPLACE FUNCTION public.list_meetings_with_notes(
  p_tribe_id int DEFAULT NULL,       -- NULL = all tribes
  p_type text DEFAULT NULL,          -- NULL = all types; 'geral', 'tribo', 'kickoff', 'lideranca'
  p_search text DEFAULT NULL,        -- full-text search in title + minutes + agenda
  p_include_empty boolean DEFAULT false, -- if true, include events without minutes
  p_limit int DEFAULT 100,
  p_offset int DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_total int;
  v_rows jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- Count total (for pagination)
  SELECT count(*) INTO v_total
  FROM events e
  WHERE (p_tribe_id IS NULL OR e.tribe_id = p_tribe_id)
    AND (p_type IS NULL OR e.type = p_type)
    AND (p_include_empty OR (e.minutes_text IS NOT NULL AND length(trim(e.minutes_text)) >= 20))
    AND (
      p_search IS NULL OR p_search = ''
      OR to_tsvector('portuguese',
           coalesce(e.title, '') || ' ' ||
           coalesce(e.minutes_text, '') || ' ' ||
           coalesce(e.agenda_text, '')
         ) @@ plainto_tsquery('portuguese', p_search)
    );

  -- Fetch rows
  SELECT coalesce(jsonb_agg(row_to_json(sub) ORDER BY sub.date DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      e.id, e.title, e.date, e.type, e.tribe_id,
      t.name as tribe_name,
      e.youtube_url, e.recording_url,
      e.minutes_text IS NOT NULL AND length(trim(e.minutes_text)) >= 20 as has_minutes,
      length(coalesce(e.minutes_text, '')) as minutes_length,
      e.agenda_text IS NOT NULL as has_agenda,
      (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present = true) as attendee_count
    FROM events e
    LEFT JOIN tribes t ON t.id = e.tribe_id
    WHERE (p_tribe_id IS NULL OR e.tribe_id = p_tribe_id)
      AND (p_type IS NULL OR e.type = p_type)
      AND (p_include_empty OR (e.minutes_text IS NOT NULL AND length(trim(e.minutes_text)) >= 20))
      AND (
        p_search IS NULL OR p_search = ''
        OR to_tsvector('portuguese',
             coalesce(e.title, '') || ' ' ||
             coalesce(e.minutes_text, '') || ' ' ||
             coalesce(e.agenda_text, '')
           ) @@ plainto_tsquery('portuguese', p_search)
      )
    ORDER BY e.date DESC
    LIMIT p_limit
    OFFSET p_offset
  ) sub;

  RETURN jsonb_build_object(
    'meetings', v_rows,
    'total', v_total,
    'limit', p_limit,
    'offset', p_offset
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_meetings_with_notes(int, text, text, boolean, int, int) TO authenticated;

-- 3. RPC: get full meeting detail (minutes + attendance + action items)
CREATE OR REPLACE FUNCTION public.get_meeting_detail(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT jsonb_build_object(
    'event', jsonb_build_object(
      'id', e.id, 'title', e.title, 'date', e.date, 'type', e.type,
      'tribe_id', e.tribe_id, 'tribe_name', t.name,
      'duration_minutes', e.duration_minutes, 'time_start', e.time_start,
      'meeting_link', e.meeting_link,
      'youtube_url', e.youtube_url, 'recording_url', e.recording_url,
      'agenda_text', e.agenda_text,
      'minutes_text', e.minutes_text,
      'notes', e.notes
    ),
    'attendance', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'member_id', a.member_id,
        'member_name', m.name,
        'present', a.present,
        'excused', a.excused
      ) ORDER BY m.name)
      FROM attendance a
      JOIN members m ON m.id = a.member_id
      WHERE a.event_id = e.id
    ), '[]'::jsonb),
    'attendee_count', (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present = true)
  ) INTO v_result
  FROM events e
  LEFT JOIN tribes t ON t.id = e.tribe_id
  WHERE e.id = p_event_id;

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('error', 'Event not found');
  END IF;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_meeting_detail(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
