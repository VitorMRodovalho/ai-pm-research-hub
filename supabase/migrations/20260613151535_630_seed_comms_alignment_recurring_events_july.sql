-- =====================================================================================
-- #630: seed Communication team recurring alignment events through July.
--
-- Operational source (Vitor, 2026-06-13):
--   Alinhamento Comunicação | Núcleo IA
--   - Tuesdays, weekly, 19:30-20:30 BRT
--   - Thursdays, every 2 weeks, 19:30-20:30 BRT
--   - Meet: https://meet.google.com/nwg-nrwx-cqb
--
-- Scope:
--   Events are linked to the active workgroup initiative "Hub de Comunicação".
--   Thursday biweekly series is anchored on the next future Thursday from this session,
--   2026-06-18. If the external calendar uses the opposite week parity, apply a small
--   follow-up migration to shift the Thursday series.
--
-- Idempotence:
--   Inserts skip any non-cancelled event for the same initiative/date/time/title prefix.
-- =====================================================================================

DO $$
DECLARE
  v_initiative_id uuid := '9ea82b09-55c6-4cc3-ab7f-178518d0ab47';
  v_meeting_link text := 'https://meet.google.com/nwg-nrwx-cqb';
  v_title text := 'Alinhamento Comunicação | Núcleo IA';
  v_group_tuesday uuid;
  v_group_thursday uuid;
BEGIN
  SELECT COALESCE(
    (
      SELECT e.recurrence_group
      FROM public.events e
      WHERE e.initiative_id = v_initiative_id
        AND e.title = v_title || ' (terça)'
        AND e.recurrence_group IS NOT NULL
      ORDER BY e.date DESC
      LIMIT 1
    ),
    gen_random_uuid()
  )
  INTO v_group_tuesday;

  SELECT COALESCE(
    (
      SELECT e.recurrence_group
      FROM public.events e
      WHERE e.initiative_id = v_initiative_id
        AND e.title = v_title || ' (quinta quinzenal)'
        AND e.recurrence_group IS NOT NULL
      ORDER BY e.date DESC
      LIMIT 1
    ),
    gen_random_uuid()
  )
  INTO v_group_thursday;

  INSERT INTO public.events (
    type, title, date, duration_minutes, duration_actual, meeting_link,
    recurrence_group, is_recorded, audience_level, source, curation_status,
    visibility, nature, time_start, organization_id, initiative_id, timezone, status
  )
  SELECT
    'comms',
    v_title || ' (terça)',
    occurrence.day::date,
    60,
    60,
    v_meeting_link,
    v_group_tuesday,
    false,
    'initiative',
    'manual',
    'published',
    'leadership',
    'recorrente',
    TIME '19:30',
    COALESCE(i.organization_id, '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid),
    i.id,
    'America/Sao_Paulo',
    'scheduled'
  FROM public.initiatives i
  CROSS JOIN LATERAL generate_series(DATE '2026-06-16', DATE '2026-07-31', INTERVAL '7 days') AS occurrence(day)
  WHERE i.id = v_initiative_id
    AND i.kind = 'workgroup'
    AND NOT EXISTS (
      SELECT 1
      FROM public.events e
      WHERE e.initiative_id = i.id
        AND e.date = occurrence.day::date
        AND e.time_start = TIME '19:30'
        AND e.title = v_title || ' (terça)'
        AND COALESCE(e.status, 'scheduled') <> 'cancelled'
    );

  INSERT INTO public.events (
    type, title, date, duration_minutes, duration_actual, meeting_link,
    recurrence_group, is_recorded, audience_level, source, curation_status,
    visibility, nature, time_start, organization_id, initiative_id, timezone, status
  )
  SELECT
    'comms',
    v_title || ' (quinta quinzenal)',
    occurrence.day::date,
    60,
    60,
    v_meeting_link,
    v_group_thursday,
    false,
    'initiative',
    'manual',
    'published',
    'leadership',
    'recorrente',
    TIME '19:30',
    COALESCE(i.organization_id, '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid),
    i.id,
    'America/Sao_Paulo',
    'scheduled'
  FROM public.initiatives i
  CROSS JOIN LATERAL generate_series(DATE '2026-06-18', DATE '2026-07-31', INTERVAL '14 days') AS occurrence(day)
  WHERE i.id = v_initiative_id
    AND i.kind = 'workgroup'
    AND NOT EXISTS (
      SELECT 1
      FROM public.events e
      WHERE e.initiative_id = i.id
        AND e.date = occurrence.day::date
        AND e.time_start = TIME '19:30'
        AND e.title = v_title || ' (quinta quinzenal)'
        AND COALESCE(e.status, 'scheduled') <> 'cancelled'
    );
END $$;

NOTIFY pgrst, 'reload schema';
