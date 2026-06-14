-- =====================================================================================
-- #630: reconcile confirmed tribe weekly agenda and seed recurring events through July.
--
-- Operational source (Vitor, 2026-06-13):
--   T1 Radar Tecnologico: Mondays 19:00-21:00 BRT, https://meet.google.com/zxs-txmk-tiz
--   T2 Agentes Autonomos: Mondays 19:30-21:00 BRT, https://meet.google.com/kdb-ydes-xif
--   T5 Talentos & Upskilling: Mondays 18:00 BRT, https://meet.google.com/dxm-gpdt-gez
--   T6 ROI & Portfolio: Wednesdays 18:30-20:00 BRT, https://meet.google.com/dgz-koyy-erw
--   T7 Governanca & Trustworthy AI: Tuesdays 20:00 BRT, link unchanged from current DB
--   T8 Inclusao & Colaboracao & Comunicacao: Thursdays 20:30-22:00 BRT,
--      https://meet.google.com/xjo-ugzc-mmk
--
-- Scope:
--   1. Reconcile manual tribe_meeting_slots to the confirmed source.
--   2. Update future scheduled tribe events through 2026-07-31 when the slot changed.
--   3. Insert missing weekly type='tribo' events, linked to the research_tribe initiative.
--   4. Leave T4 untouched: no confirmed operational source was provided.
--
-- Idempotence:
--   Inserts skip any non-cancelled type='tribo' event for the same initiative/date.
-- =====================================================================================

DO $$
DECLARE
  v_end_date date := DATE '2026-07-31';
BEGIN
  CREATE TEMP TABLE _p630_target_tribe_slots (
    tribe_id integer PRIMARY KEY,
    day_of_week integer NOT NULL,
    time_start time NOT NULL,
    time_end time NOT NULL,
    duration_minutes integer NOT NULL,
    meeting_link text,
    event_title text NOT NULL
  ) ON COMMIT DROP;

  INSERT INTO _p630_target_tribe_slots (
    tribe_id, day_of_week, time_start, time_end, duration_minutes, meeting_link, event_title
  ) VALUES
    (1, 1, TIME '19:00', TIME '21:00', 120, 'https://meet.google.com/zxs-txmk-tiz', 'Acompanhamento Semanal - Radar Tecnológico'),
    (2, 1, TIME '19:30', TIME '21:00',  90, 'https://meet.google.com/kdb-ydes-xif', 'Agentes Autônomos — Reunião Semanal'),
    (5, 1, TIME '18:00', TIME '19:30',  90, 'https://meet.google.com/dxm-gpdt-gez', 'Reunião Semanal Tribo (Talentos & Upskilling)'),
    (6, 3, TIME '18:30', TIME '20:00',  90, 'https://meet.google.com/dgz-koyy-erw', 'ROI & Portfólio — Reunião Semanal'),
    (7, 2, TIME '20:00', TIME '21:00',  60, NULL,                                      'Governança & Trustworthy AI — Reunião Semanal'),
    (8, 4, TIME '20:30', TIME '22:00',  90, 'https://meet.google.com/xjo-ugzc-mmk', 'Inclusão & Colaboração & Comunicação — Reunião Semanal');

  -- Keep the canonical tribe-level meeting link aligned where the confirmed source includes it.
  UPDATE public.tribes t
  SET meeting_link = target.meeting_link,
      updated_at = now()
  FROM _p630_target_tribe_slots target
  WHERE t.id = target.tribe_id
    AND target.meeting_link IS NOT NULL
    AND t.meeting_link IS DISTINCT FROM target.meeting_link;

  -- Deactivate active manual slots that conflict with the confirmed source.
  UPDATE public.tribe_meeting_slots slot
  SET is_active = false,
      updated_at = now()
  FROM _p630_target_tribe_slots target
  WHERE slot.tribe_id = target.tribe_id
    AND slot.is_active = true
    AND (
      slot.day_of_week IS DISTINCT FROM target.day_of_week
      OR slot.time_start IS DISTINCT FROM target.time_start
      OR slot.time_end IS DISTINCT FROM target.time_end
    );

  -- Update an existing row for the confirmed weekday if present.
  UPDATE public.tribe_meeting_slots slot
  SET time_start = target.time_start,
      time_end = target.time_end,
      is_active = true,
      updated_at = now()
  FROM _p630_target_tribe_slots target
  WHERE slot.tribe_id = target.tribe_id
    AND slot.day_of_week = target.day_of_week;

  -- Insert the confirmed slot if the tribe had no row for that weekday.
  INSERT INTO public.tribe_meeting_slots (tribe_id, day_of_week, time_start, time_end, is_active)
  SELECT target.tribe_id, target.day_of_week, target.time_start, target.time_end, true
  FROM _p630_target_tribe_slots target
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.tribe_meeting_slots slot
    WHERE slot.tribe_id = target.tribe_id
      AND slot.day_of_week = target.day_of_week
  );

  -- Align already-created future scheduled tribe meetings with the confirmed cadence.
  UPDATE public.events e
  SET time_start = target.time_start,
      duration_minutes = target.duration_minutes,
      duration_actual = target.duration_minutes,
      meeting_link = COALESCE(target.meeting_link, e.meeting_link),
      title = target.event_title,
      type = 'tribo',
      nature = 'recorrente',
      timezone = 'America/Sao_Paulo',
      source = 'manual',
      updated_at = now()
  FROM public.initiatives i
  JOIN _p630_target_tribe_slots target ON target.tribe_id = i.legacy_tribe_id
  WHERE e.initiative_id = i.id
    AND i.kind = 'research_tribe'
    AND e.date >= CURRENT_DATE
    AND e.date <= v_end_date
    AND EXTRACT(DOW FROM e.date)::integer = target.day_of_week
    AND COALESCE(e.status, 'scheduled') <> 'cancelled'
    AND e.type = 'tribo';

  -- Seed missing weekly occurrences through the end of July.
  INSERT INTO public.events (
    type, title, date, duration_minutes, duration_actual, meeting_link,
    recurrence_group, is_recorded, audience_level, source, curation_status,
    visibility, nature, time_start, organization_id, initiative_id, timezone, status
  )
  SELECT
    'tribo',
    target.event_title,
    occurrence.day::date,
    target.duration_minutes,
    target.duration_minutes,
    COALESCE(target.meeting_link, t.meeting_link),
    COALESCE(existing_group.recurrence_group, gen_random_uuid()),
    false,
    'tribe',
    'manual',
    'published',
    'all',
    'recorrente',
    target.time_start,
    COALESCE(i.organization_id, '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid),
    i.id,
    'America/Sao_Paulo',
    'scheduled'
  FROM _p630_target_tribe_slots target
  JOIN public.tribes t ON t.id = target.tribe_id
  JOIN public.initiatives i ON i.legacy_tribe_id = target.tribe_id AND i.kind = 'research_tribe'
  CROSS JOIN LATERAL generate_series(
    DATE '2026-06-13'
      + (((target.day_of_week - EXTRACT(DOW FROM DATE '2026-06-13')::integer + 7) % 7) * INTERVAL '1 day'),
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
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.events e
    WHERE e.initiative_id = i.id
      AND e.date = occurrence.day::date
      AND e.type = 'tribo'
      AND COALESCE(e.status, 'scheduled') <> 'cancelled'
  );
END $$;

NOTIFY pgrst, 'reload schema';
