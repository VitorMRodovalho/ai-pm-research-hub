-- ============================================================================
-- ADR-0015 Phase 1 — events reader cutover (11th and final C3 table, part A)
--
-- Scope: 4 simpler reader RPCs with clean JOIN tribes → initiatives swap.
-- The 2 complex grid RPCs (get_attendance_grid + get_tribe_attendance_grid)
-- are deferred to Phase 1c — they mix eligibility logic based on
-- operational_role/designations with the tribe JOIN, requiring combined
-- ADR-0007/0011/0015 refactor that is too large for this commit.
--
-- Dual-write integrity: 270 rows — 150 both + 2 init-only + 118 neither.
-- 118 "neither" = unscoped events (geral, kickoff, external). Preserved
-- via COALESCE i.title fallback where semantic requires display name.
--
-- Changed RPCs (4):
--   1. get_meeting_detail            — LEFT JOIN initiatives
--   2. get_meeting_notes_compliance  — simplify hybrid to initiatives only
--   3. get_recent_events             — LEFT JOIN initiatives
--   4. list_meetings_with_notes      — drop tribes JOIN (already has initiatives)
--
-- NOT refactored this commit (Phase 1c):
--   - get_attendance_grid            — deep operational_role logic
--   - get_tribe_attendance_grid      — same
--
-- NOT refactored (writers — dual-write triggers sync):
--   - create_event, update_event, drop_event_instance (already V4-auth'd)
--
-- ADR: ADR-0015 Phase 1
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. get_meeting_detail — LEFT JOIN initiatives
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_meeting_detail(
  p_event_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
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
      'tribe_id', e.tribe_id,
      'tribe_name', i.title,  -- ADR-0015 Phase 1
      'duration_minutes', e.duration_minutes, 'time_start', e.time_start,
      'meeting_link', e.meeting_link,
      'youtube_url', e.youtube_url, 'recording_url', e.recording_url,
      'agenda_text', e.agenda_text,
      'minutes_text', e.minutes_text,
      'notes', e.notes
    ),
    'attendance', COALESCE((
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
  LEFT JOIN initiatives i ON i.id = e.initiative_id  -- ADR-0015 Phase 1
  WHERE e.id = p_event_id;

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('error', 'Event not found');
  END IF;

  RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. get_meeting_notes_compliance — simplify hybrid pattern
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_meeting_notes_compliance()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_result jsonb;
BEGIN
  WITH stats AS (
    SELECT
      e.tribe_id AS t_id,
      COALESCE(i.title, 'Gerais/sem tribo') AS group_name,  -- ADR-0015 Phase 1 (was: COALESCE(t.name, i.title, ...))
      count(*) FILTER (WHERE e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL) AS recorded,
      count(*) FILTER (
        WHERE (e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL)
          AND e.minutes_text IS NOT NULL
          AND length(trim(e.minutes_text)) >= 20
          AND lower(trim(e.minutes_text)) NOT IN ('teste', 'teste teste', 'test', 'placeholder', '-')
      ) AS with_minutes
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id  -- ADR-0015 Phase 1
    WHERE e.date <= current_date
    GROUP BY e.tribe_id, COALESCE(i.title, 'Gerais/sem tribo')
  )
  SELECT jsonb_build_object(
    'by_tribe', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'tribe_id', s.t_id,
          'tribe_name', s.group_name,
          'recorded', s.recorded,
          'with_minutes', s.with_minutes,
          'pct', CASE WHEN s.recorded > 0 THEN round(100.0 * s.with_minutes / s.recorded) ELSE 100 END
        ) ORDER BY CASE WHEN s.recorded > 0 THEN round(100.0 * s.with_minutes / s.recorded) ELSE 100 END ASC
      ) FROM stats s WHERE s.recorded > 0
    ), '[]'::jsonb),
    'total_recorded', (SELECT sum(recorded) FROM stats),
    'total_with_minutes', (SELECT sum(with_minutes) FROM stats),
    'overall_pct', CASE
      WHEN (SELECT sum(recorded) FROM stats) > 0
      THEN round(100.0 * (SELECT sum(with_minutes) FROM stats) / (SELECT sum(recorded) FROM stats))
      ELSE 100
    END
  ) INTO v_result;
  RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. get_recent_events — LEFT JOIN initiatives
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_recent_events(
  p_days_back integer DEFAULT 30,
  p_days_forward integer DEFAULT 7
)
RETURNS TABLE (
  id uuid,
  date date,
  type text,
  title text,
  tribe_id integer,
  tribe_name text,
  headcount bigint,
  duration_minutes integer,
  duration_actual integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id, e.date, e.type, e.title, e.tribe_id,
    i.title AS tribe_name,  -- ADR-0015 Phase 1
    (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present) AS headcount,
    e.duration_minutes, e.duration_actual
  FROM events e
  LEFT JOIN initiatives i ON i.id = e.initiative_id  -- ADR-0015 Phase 1
  WHERE e.date BETWEEN current_date - p_days_back AND current_date + p_days_forward
  ORDER BY e.date DESC;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. list_meetings_with_notes — drop redundant tribes JOIN (initiatives remains)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.list_meetings_with_notes(
  p_tribe_id integer DEFAULT NULL,
  p_type text DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_include_empty boolean DEFAULT false,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
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

  SELECT COALESCE(jsonb_agg(row_to_json(sub) ORDER BY sub.date DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      e.id, e.title, e.date, e.type, e.tribe_id,
      i.title AS tribe_name,  -- ADR-0015 Phase 1: derive from initiatives (was: tribes t)
      e.initiative_id,
      i.title AS initiative_name,
      e.youtube_url, e.recording_url,
      e.minutes_text IS NOT NULL AND length(trim(e.minutes_text)) >= 20 AS has_minutes,
      length(COALESCE(e.minutes_text, '')) AS minutes_length,
      e.agenda_text IS NOT NULL AS has_agenda,
      (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present = true) AS attendee_count
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id  -- single JOIN (was: tribes + initiatives)
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

NOTIFY pgrst, 'reload schema';

COMMIT;
