-- =====================================================================================
-- #630: reconcile T4 weekly agenda after operational confirmation.
--
-- Operational source (Vitor, 2026-06-13):
--   T4 Cultura & Change: Wednesdays 18:00-20:00 BRT,
--   https://meet.google.com/kfv-qzqf-ejn
--
-- Scope:
--   1. Update tribe_meeting_slots for T4 to Wednesday 18:00-20:00.
--   2. Update the canonical tribe meeting link.
--   3. Seed missing weekly type='tribo' events linked to the research_tribe initiative
--      through 2026-07-31.
--
-- Idempotence:
--   Inserts skip any non-cancelled type='tribo' event for the same initiative/date.
-- =====================================================================================

DO $$
DECLARE
  v_tribe_id integer := 4;
  v_day_of_week integer := 3;
  v_time_start time := TIME '18:00';
  v_time_end time := TIME '20:00';
  v_duration_minutes integer := 120;
  v_meeting_link text := 'https://meet.google.com/kfv-qzqf-ejn';
  v_event_title text := 'Cultura & Change — Reunião Semanal';
  v_end_date date := DATE '2026-07-31';
BEGIN
  UPDATE public.tribes
  SET meeting_link = v_meeting_link,
      updated_at = now()
  WHERE id = v_tribe_id
    AND meeting_link IS DISTINCT FROM v_meeting_link;

  UPDATE public.tribe_meeting_slots
  SET is_active = false,
      updated_at = now()
  WHERE tribe_id = v_tribe_id
    AND is_active = true
    AND (
      day_of_week IS DISTINCT FROM v_day_of_week
      OR time_start IS DISTINCT FROM v_time_start
      OR time_end IS DISTINCT FROM v_time_end
    );

  UPDATE public.tribe_meeting_slots
  SET time_start = v_time_start,
      time_end = v_time_end,
      is_active = true,
      updated_at = now()
  WHERE tribe_id = v_tribe_id
    AND day_of_week = v_day_of_week;

  INSERT INTO public.tribe_meeting_slots (tribe_id, day_of_week, time_start, time_end, is_active)
  SELECT v_tribe_id, v_day_of_week, v_time_start, v_time_end, true
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.tribe_meeting_slots
    WHERE tribe_id = v_tribe_id
      AND day_of_week = v_day_of_week
  );

  UPDATE public.events e
  SET time_start = v_time_start,
      duration_minutes = v_duration_minutes,
      duration_actual = v_duration_minutes,
      meeting_link = v_meeting_link,
      title = v_event_title,
      type = 'tribo',
      nature = 'recorrente',
      timezone = 'America/Sao_Paulo',
      source = 'manual',
      updated_at = now()
  FROM public.initiatives i
  WHERE e.initiative_id = i.id
    AND i.legacy_tribe_id = v_tribe_id
    AND i.kind = 'research_tribe'
    AND e.date >= CURRENT_DATE
    AND e.date <= v_end_date
    AND EXTRACT(DOW FROM e.date)::integer = v_day_of_week
    AND COALESCE(e.status, 'scheduled') <> 'cancelled'
    AND e.type = 'tribo';

  INSERT INTO public.events (
    type, title, date, duration_minutes, duration_actual, meeting_link,
    recurrence_group, is_recorded, audience_level, source, curation_status,
    visibility, nature, time_start, organization_id, initiative_id, timezone, status
  )
  SELECT
    'tribo',
    v_event_title,
    occurrence.day::date,
    v_duration_minutes,
    v_duration_minutes,
    v_meeting_link,
    COALESCE(existing_group.recurrence_group, gen_random_uuid()),
    false,
    'tribe',
    'manual',
    'published',
    'all',
    'recorrente',
    v_time_start,
    COALESCE(i.organization_id, '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid),
    i.id,
    'America/Sao_Paulo',
    'scheduled'
  FROM public.initiatives i
  CROSS JOIN LATERAL generate_series(
    DATE '2026-06-13'
      + (((v_day_of_week - EXTRACT(DOW FROM DATE '2026-06-13')::integer + 7) % 7) * INTERVAL '1 day'),
    v_end_date,
    INTERVAL '7 days'
  ) AS occurrence(day)
  LEFT JOIN LATERAL (
    SELECT e.recurrence_group
    FROM public.events e
    WHERE e.initiative_id = i.id
      AND e.type = 'tribo'
      AND e.recurrence_group IS NOT NULL
      AND COALESCE(e.status, 'scheduled') <> 'cancelled'
    ORDER BY e.date DESC
    LIMIT 1
  ) existing_group ON true
  WHERE i.legacy_tribe_id = v_tribe_id
    AND i.kind = 'research_tribe'
    AND NOT EXISTS (
      SELECT 1
      FROM public.events e
      WHERE e.initiative_id = i.id
        AND e.date = occurrence.day::date
        AND e.type = 'tribo'
        AND COALESCE(e.status, 'scheduled') <> 'cancelled'
    );
END $$;

NOTIFY pgrst, 'reload schema';
