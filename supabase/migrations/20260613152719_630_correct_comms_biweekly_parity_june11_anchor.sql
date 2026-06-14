-- =====================================================================================
-- #630: correct Communication team Thursday biweekly parity.
--
-- Operational correction (Vitor, 2026-06-13):
--   The Communication team had its biweekly Thursday alignment on 2026-06-11.
--   Therefore the next future occurrences through July are 2026-06-25, 2026-07-09,
--   and 2026-07-23. The initial seed anchored the series at 2026-06-18; this
--   migration removes only that wrong future parity and inserts the corrected dates.
--
-- Scope:
--   Initiative/workgroup "Hub de Comunicação" only.
--   Title: "Alinhamento Comunicação | Núcleo IA (quinta quinzenal)".
-- =====================================================================================

DO $$
DECLARE
  v_initiative_id uuid := '9ea82b09-55c6-4cc3-ab7f-178518d0ab47';
  v_meeting_link text := 'https://meet.google.com/nwg-nrwx-cqb';
  v_title text := 'Alinhamento Comunicação | Núcleo IA (quinta quinzenal)';
  v_group_thursday uuid;
BEGIN
  SELECT COALESCE(
    (
      SELECT e.recurrence_group
      FROM public.events e
      WHERE e.initiative_id = v_initiative_id
        AND e.title = v_title
        AND e.recurrence_group IS NOT NULL
      ORDER BY e.date DESC
      LIMIT 1
    ),
    gen_random_uuid()
  )
  INTO v_group_thursday;

  DELETE FROM public.events e
  WHERE e.initiative_id = v_initiative_id
    AND e.title = v_title
    AND e.date IN (DATE '2026-06-18', DATE '2026-07-02', DATE '2026-07-16', DATE '2026-07-30')
    AND e.time_start = TIME '19:30'
    AND COALESCE(e.status, 'scheduled') = 'scheduled';

  INSERT INTO public.events (
    type, title, date, duration_minutes, duration_actual, meeting_link,
    recurrence_group, is_recorded, audience_level, source, curation_status,
    visibility, nature, time_start, organization_id, initiative_id, timezone, status
  )
  SELECT
    'comms',
    v_title,
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
  CROSS JOIN LATERAL generate_series(DATE '2026-06-25', DATE '2026-07-31', INTERVAL '14 days') AS occurrence(day)
  WHERE i.id = v_initiative_id
    AND i.kind = 'workgroup'
    AND NOT EXISTS (
      SELECT 1
      FROM public.events e
      WHERE e.initiative_id = i.id
        AND e.date = occurrence.day::date
        AND e.time_start = TIME '19:30'
        AND e.title = v_title
        AND COALESCE(e.status, 'scheduled') <> 'cancelled'
    );
END $$;

NOTIFY pgrst, 'reload schema';
