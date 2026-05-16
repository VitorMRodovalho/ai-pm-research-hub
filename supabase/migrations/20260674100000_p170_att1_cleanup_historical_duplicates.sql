-- p170 ATT-1 cleanup — historical interview duplicates
--
-- Context: backfill em 20260674000000 criou 8 events rows novos com source='selection_portal'
-- para selection_interviews vindas de import_historical_interviews (p150-ish), que tinham
-- scheduled_at placeholder = '2026-04-02 01:24:55.90214+00' (now() na hora do import) porque
-- o regex parser do "Realizado X/Y H:MMam" não casou no formato real.
--
-- Cada uma dessas 8 interviews tem um events row real (calendar_import) com a data correta
-- (Jan 28 - Feb 03, 2026). Resultado do backfill: DUPLICATA.
--
-- Cleanup:
--   1. Identificar pares: selection_portal event (placeholder) + calendar_import event (real)
--      pareados por selection_application_id
--   2. UPDATE selection_interviews.scheduled_at ← calendar_import event.date+time
--   3. DELETE selection_portal event duplicado (placeholder)
--   4. Trigger fires no UPDATE → re-sync com calendar_import event (idempotent, link existing)
--
-- Para Alexandre Meirelles (2 calendar_import events Jan 29 + Jan 31): pick o MAIS TARDIO
-- (Jan 31) como o real (provavelmente o earlier foi reschedule cancelado).
--
-- Rollback: não trivial (perderíamos histórico de dates). Faça snapshot antes:
--   CREATE TEMP TABLE rollback_p170_att1_cleanup AS
--   SELECT id, scheduled_at FROM selection_interviews WHERE scheduled_at = '2026-04-02 01:24:55.90214+00';

DO $$
DECLARE
  v_pair record;
  v_real_date date;
  v_real_time time;
  v_real_event_id uuid;
  v_dup_event_id uuid;
  v_fixed int := 0;
  v_deleted int := 0;
BEGIN
  FOR v_pair IN
    SELECT DISTINCT si.id AS interview_id, si.application_id, sa.applicant_name
      FROM public.selection_interviews si
      JOIN public.selection_applications sa ON sa.id = si.application_id
      JOIN public.events e_dup ON e_dup.selection_application_id = si.application_id
                                AND e_dup.type='entrevista'
                                AND e_dup.source = 'selection_portal'
                                AND e_dup.date = '2026-04-01'  -- placeholder date in BRT
     WHERE EXISTS (
       SELECT 1 FROM public.events e_real
        WHERE e_real.selection_application_id = si.application_id
          AND e_real.type='entrevista'
          AND e_real.source = 'calendar_import'
     )
  LOOP
    -- Find the real event (prefer latest date for ambiguous cases like Alexandre Meirelles)
    SELECT id, date, time_start
      INTO v_real_event_id, v_real_date, v_real_time
      FROM public.events
     WHERE selection_application_id = v_pair.application_id
       AND type='entrevista'
       AND source = 'calendar_import'
     ORDER BY date DESC, time_start DESC NULLS LAST
     LIMIT 1;

    -- Find the duplicate selection_portal event for this app_id
    SELECT id INTO v_dup_event_id
      FROM public.events
     WHERE selection_application_id = v_pair.application_id
       AND type='entrevista'
       AND source = 'selection_portal'
       AND date = '2026-04-01'
     LIMIT 1;

    IF v_real_event_id IS NULL OR v_dup_event_id IS NULL THEN
      CONTINUE;
    END IF;

    -- Step 1: fix selection_interview's scheduled_at (also fires trigger → re-sync with real event)
    UPDATE public.selection_interviews
       SET scheduled_at = (v_real_date::text || ' ' || v_real_time::text || '-03:00')::timestamptz,
           calendar_event_id = COALESCE(calendar_event_id, (
             SELECT calendar_event_id FROM public.events WHERE id = v_real_event_id
           ))
     WHERE id = v_pair.interview_id;
    v_fixed := v_fixed + 1;

    -- Step 2: delete the duplicate selection_portal event
    DELETE FROM public.events WHERE id = v_dup_event_id;
    v_deleted := v_deleted + 1;
  END LOOP;

  RAISE NOTICE 'p170 ATT-1 cleanup: interviews_fixed=%, duplicate_events_deleted=%', v_fixed, v_deleted;
END $$;

NOTIFY pgrst, 'reload schema';
