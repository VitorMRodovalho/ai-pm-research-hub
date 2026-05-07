-- p118 follow-up: admin button para criar próxima Reunião Geral quinzenal
-- Resolve gap operacional: events de type='geral' precisavam ser inseridas manualmente,
-- ninguém criou após 2026-04-23, e a HomepageHero retornava "Sem reuniões próximas"
-- mesmo com a live acontecendo.

CREATE OR REPLACE FUNCTION public.create_next_geral_meeting(
  p_meeting_link text,
  p_youtube_url text DEFAULT NULL,
  p_title text DEFAULT NULL,
  p_interval_days integer DEFAULT 14
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_last_date date;
  v_next_date date;
  v_event_id uuid;
  v_recurrence uuid := '8ef692c1-8cae-486c-ab7b-2d3536188ef5';
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Forbidden: only authorized managers can create general meetings';
  END IF;

  IF p_meeting_link IS NULL OR length(trim(p_meeting_link)) = 0 THEN
    RAISE EXCEPTION 'meeting_link required';
  END IF;

  SELECT MAX(date) INTO v_last_date FROM public.events WHERE type = 'geral';
  v_last_date := COALESCE(v_last_date, CURRENT_DATE);
  v_next_date := GREATEST(v_last_date + p_interval_days, CURRENT_DATE);

  INSERT INTO public.events (
    type, title, date, time_start, duration_minutes,
    meeting_link, youtube_url,
    visibility, audience_level,
    recurrence_group, source,
    created_by, created_at, updated_at
  ) VALUES (
    'geral',
    COALESCE(p_title, 'Reunião Geral — ' || to_char(v_next_date, 'YYYY-MM-DD')),
    v_next_date, '19:30', 90,
    p_meeting_link, p_youtube_url,
    'all', 'all',
    v_recurrence, 'manual',
    auth.uid(), now(), now()
  ) RETURNING id INTO v_event_id;

  RETURN jsonb_build_object(
    'event_id', v_event_id,
    'date', v_next_date,
    'meeting_link', p_meeting_link,
    'youtube_url', p_youtube_url,
    'title', COALESCE(p_title, 'Reunião Geral — ' || to_char(v_next_date, 'YYYY-MM-DD'))
  );
END;
$$;

COMMENT ON FUNCTION public.create_next_geral_meeting(text, text, text, integer) IS
'Cria próximo evento geral quinzenal (max(last_geral_date)+interval, never past). Gated por can_by_member(manage_event). Reutiliza recurrence_group canônico 8ef692c1.';

GRANT EXECUTE ON FUNCTION public.create_next_geral_meeting(text, text, text, integer) TO authenticated;
