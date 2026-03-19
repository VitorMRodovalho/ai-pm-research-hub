-- GC-095: Create Event Form ↔ Event Governance Schema Alignment
-- DROP old create_event (pre-governance) + CREATE expanded version
-- Per D10: always DROP+CREATE, never CREATE OR REPLACE for signature changes

DROP FUNCTION IF EXISTS public.create_event(text, text, date, integer, integer, text);

CREATE FUNCTION public.create_event(
  p_type text, p_title text, p_date date, p_duration_minutes integer DEFAULT 90,
  p_tribe_id integer DEFAULT NULL, p_meeting_link text DEFAULT NULL,
  p_nature text DEFAULT 'recorrente', p_visibility text DEFAULT 'all',
  p_agenda_text text DEFAULT NULL, p_agenda_url text DEFAULT NULL,
  p_external_attendees text[] DEFAULT NULL, p_invited_member_ids uuid[] DEFAULT NULL,
  p_audience_level text DEFAULT NULL
)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_member record; v_event_id uuid; v_audience text;
BEGIN
  SELECT * INTO v_member FROM members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member IS NULL THEN RETURN json_build_object('success', false, 'error', 'Unauthorized'); END IF;

  -- Type validation
  IF p_type NOT IN ('geral','tribo','lideranca','kickoff','comms','parceria','entrevista','1on1','evento_externo','webinar') THEN
    RETURN json_build_object('success', false, 'error', 'Invalid event type: ' || p_type);
  END IF;

  -- Nature validation
  IF p_nature NOT IN ('kickoff','recorrente','avulsa','encerramento','workshop','entrevista_selecao') THEN
    p_nature := 'avulsa';
  END IF;

  -- Visibility: auto-enforce for sensitive types
  IF p_type IN ('parceria','entrevista','1on1') THEN
    p_visibility := 'gp_only';
  ELSIF p_visibility NOT IN ('all','leadership','gp_only') THEN
    p_visibility := 'all';
  END IF;

  -- Tribe required for tribe events
  IF p_type = 'tribo' AND p_tribe_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'tribe_id required for tribe events');
  END IF;

  -- Role check
  IF v_member.is_superadmin IS NOT TRUE THEN
    IF v_member.operational_role IN ('manager', 'deputy_manager') THEN
      NULL;
    ELSIF v_member.operational_role = 'tribe_leader' THEN
      IF p_type NOT IN ('tribo') THEN
        RETURN json_build_object('success', false, 'error', 'Leaders can only create tribe events');
      END IF;
      IF p_tribe_id IS DISTINCT FROM v_member.tribe_id THEN
        RETURN json_build_object('success', false, 'error', 'Can only create events for your own tribe');
      END IF;
      p_external_attendees := NULL;
      p_invited_member_ids := NULL;
    ELSE
      RETURN json_build_object('success', false, 'error', 'Insufficient permissions');
    END IF;
  END IF;

  v_audience := COALESCE(p_audience_level,
    CASE p_type WHEN 'tribo' THEN 'tribe' WHEN 'lideranca' THEN 'leadership' WHEN 'comms' THEN 'leadership' ELSE 'all' END
  );

  INSERT INTO events (type, title, date, duration_minutes, tribe_id, audience_level, meeting_link,
    nature, visibility, agenda_text, agenda_url, external_attendees, invited_member_ids, created_by)
  VALUES (p_type, p_title, p_date, p_duration_minutes, p_tribe_id, v_audience, p_meeting_link,
    p_nature, p_visibility, p_agenda_text, p_agenda_url, p_external_attendees, p_invited_member_ids, v_member.id)
  RETURNING id INTO v_event_id;

  IF p_agenda_text IS NOT NULL OR p_agenda_url IS NOT NULL THEN
    UPDATE events SET agenda_posted_at = now(), agenda_posted_by = v_member.id WHERE id = v_event_id;
  END IF;

  RETURN json_build_object('success', true, 'event_id', v_event_id);
END; $$;

SELECT pg_notify('pgrst', 'reload schema');
