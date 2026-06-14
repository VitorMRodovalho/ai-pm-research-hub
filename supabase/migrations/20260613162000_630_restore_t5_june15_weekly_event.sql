-- #630 follow-up: restore T5 2026-06-15 weekly tribe event.
--
-- Context:
--   The confirmed operational cadence for Tribo 5 - Talentos & Upskilling is every
--   Monday 18:00-19:30 BRT through July (#630). The reconciliation contract expects
--   seven active Monday tribe events between 2026-06-13 and 2026-07-31.
--
--   Live audit on 2026-06-13 found the 2026-06-15 occurrence already present but
--   status='cancelled', reducing the active count to six. This migration restores
--   only that occurrence to the confirmed scheduled cadence.

DO $$
DECLARE
  v_initiative_id uuid;
  v_recurrence_group uuid;
BEGIN
  SELECT id
  INTO v_initiative_id
  FROM public.initiatives
  WHERE legacy_tribe_id = 5
    AND kind = 'research_tribe'
  LIMIT 1;

  IF v_initiative_id IS NULL THEN
    RAISE EXCEPTION 'T5 research_tribe initiative not found';
  END IF;

  SELECT recurrence_group
  INTO v_recurrence_group
  FROM public.events
  WHERE initiative_id = v_initiative_id
    AND type = 'tribo'
    AND date >= DATE '2026-06-22'
    AND date <= DATE '2026-07-31'
    AND recurrence_group IS NOT NULL
  ORDER BY date
  LIMIT 1;

  UPDATE public.events
  SET status = 'scheduled',
      title = 'Reunião Semanal Tribo (Talentos & Upskilling)',
      type = 'tribo',
      nature = 'recorrente',
      date = DATE '2026-06-15',
      time_start = TIME '18:00',
      duration_minutes = 90,
      duration_actual = 90,
      meeting_link = 'https://meet.google.com/dxm-gpdt-gez',
      recurrence_group = COALESCE(recurrence_group, v_recurrence_group),
      audience_level = 'tribe',
      source = 'manual',
      curation_status = 'published',
      visibility = 'all',
      timezone = 'America/Sao_Paulo',
      initiative_id = v_initiative_id,
      updated_at = now()
  WHERE initiative_id = v_initiative_id
    AND date = DATE '2026-06-15'
    AND type = 'tribo';

  IF NOT FOUND THEN
    INSERT INTO public.events (
      type, title, date, duration_minutes, duration_actual, meeting_link,
      recurrence_group, is_recorded, audience_level, source, curation_status,
      visibility, nature, time_start, organization_id, initiative_id, timezone, status
    )
    SELECT
      'tribo',
      'Reunião Semanal Tribo (Talentos & Upskilling)',
      DATE '2026-06-15',
      90,
      90,
      'https://meet.google.com/dxm-gpdt-gez',
      COALESCE(v_recurrence_group, gen_random_uuid()),
      false,
      'tribe',
      'manual',
      'published',
      'all',
      'recorrente',
      TIME '18:00',
      COALESCE(i.organization_id, '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid),
      i.id,
      'America/Sao_Paulo',
      'scheduled'
    FROM public.initiatives i
    WHERE i.id = v_initiative_id;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
