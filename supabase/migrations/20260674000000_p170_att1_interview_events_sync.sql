-- p170 ATT-1 — Sync selection_interviews → events row (single source of truth)
--
-- Context: p169 found root cause of /attendance pollution = sistemas paralelos:
--   • selection_interviews (portal selecao) created via schedule_interview() RPC + 3 outros paths
--   • events (calendar) created via calendar_import EF (independente, sem link de volta)
-- p169 commit 8ce1476 cobriu sintoma (UI hide + trigger audience). ATT-1 cobre causa raiz:
-- trigger AFTER INSERT/UPDATE on selection_interviews que cria/sincroniza events row.
--
-- Cobre TODOS os 4 paths de escrita de selection_interviews:
--   1. schedule_interview()                — admin/lead manual via portal seleção
--   2. mirror_sibling_interview()          — admin mirror dual_track (notes contém '[Espelhado' → SKIP)
--   3. sync_calendar_booking_to_interview()— webhook Apps Script (já tem calendar_event_id; sync existing)
--   4. import_historical_interviews()      — bulk legacy (já populado; backfill cobre)
--
-- Idempotência:
--   • Se selection_interviews.calendar_event_id ≠ NULL: linka via calendar_event_id (sem duplicar)
--   • Else: linka via (selection_application_id, date, time_start proximity) — calendar_import rows
--   • Mirror rows (notes contém '[Espelhado'): NÃO cria events row (data-only mirror)
--   • scheduled_at NULL: NÃO cria events row (pending interview sem agenda)
--
-- Status mapping (selection_interviews.status → events.status):
--   • scheduled  → scheduled
--   • completed  → completed
--   • cancelled  → cancelled
--   • noshow     → cancelled  (events.status só tem 3 valores)
--   • rescheduled→ cancelled  (a interview "antiga" cancelada; nova row separada criará novo event)
--   • pending    → scheduled  (placeholder; será atualizado quando scheduled_at chegar)
--
-- audience_level/visibility já forçados pra 'leadership' via trg_interview_audience_private (p169).
--
-- Rollback:
--   DROP TRIGGER IF EXISTS trg_sync_interview_to_event ON public.selection_interviews;
--   DROP FUNCTION IF EXISTS public._trg_sync_interview_to_event();
--   DROP FUNCTION IF EXISTS public._sync_interview_to_event(uuid);

-- ============================================================
-- Helper: idempotent sync de 1 selection_interview → events row
-- ============================================================
CREATE OR REPLACE FUNCTION public._sync_interview_to_event(p_interview_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_interview record;
  v_app       record;
  v_event_id  uuid;
  v_event_status text;
  v_event_date date;
  v_event_time time;
  v_interviewer_ids uuid[];
BEGIN
  SELECT * INTO v_interview FROM public.selection_interviews WHERE id = p_interview_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT a.*, c.cycle_code AS cycle_code
    INTO v_app
    FROM public.selection_applications a
    LEFT JOIN public.selection_cycles c ON c.id = a.cycle_id
   WHERE a.id = v_interview.application_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  -- Status mapping (events.status CHECK = scheduled/cancelled/completed)
  v_event_status := CASE v_interview.status
    WHEN 'completed'   THEN 'completed'
    WHEN 'cancelled'   THEN 'cancelled'
    WHEN 'noshow'      THEN 'cancelled'
    WHEN 'rescheduled' THEN 'cancelled'
    ELSE 'scheduled'  -- scheduled, pending
  END;

  -- Pre-compute date/time in BRT (events.date is date, time_start is time without tz)
  IF v_interview.scheduled_at IS NOT NULL THEN
    v_event_date := (v_interview.scheduled_at AT TIME ZONE 'America/Sao_Paulo')::date;
    v_event_time := (v_interview.scheduled_at AT TIME ZONE 'America/Sao_Paulo')::time;
  END IF;

  -- Try to find existing events row (idempotent linking)
  -- (1) Most reliable: calendar_event_id match
  IF v_interview.calendar_event_id IS NOT NULL AND v_interview.calendar_event_id <> '' THEN
    SELECT id INTO v_event_id
      FROM public.events
     WHERE calendar_event_id = v_interview.calendar_event_id
       AND type = 'entrevista'
     LIMIT 1;
  END IF;

  -- (2) Fallback: same application + same date + time_start within 5min window
  --     (catches calendar_import rows that p169 backfill linked via title parsing)
  IF v_event_id IS NULL AND v_event_date IS NOT NULL THEN
    SELECT id INTO v_event_id
      FROM public.events
     WHERE selection_application_id = v_interview.application_id
       AND type = 'entrevista'
       AND date  = v_event_date
       AND (
         time_start IS NULL
         OR ABS(EXTRACT(EPOCH FROM (time_start - v_event_time))) <= 300  -- ±5 min
       )
     ORDER BY (time_start IS NULL) ASC, ABS(EXTRACT(EPOCH FROM (COALESCE(time_start, v_event_time) - v_event_time))) ASC
     LIMIT 1;
  END IF;

  v_interviewer_ids := NULLIF(v_interview.interviewer_ids, ARRAY[]::uuid[]);

  IF v_event_id IS NOT NULL THEN
    -- Sync existing event with latest interview data
    UPDATE public.events
       SET status                   = v_event_status,
           date                     = COALESCE(v_event_date, date),
           time_start               = COALESCE(v_event_time, time_start),
           duration_minutes         = COALESCE(v_interview.duration_minutes, duration_minutes),
           invited_member_ids       = COALESCE(v_interviewer_ids, invited_member_ids),
           selection_application_id = COALESCE(selection_application_id, v_interview.application_id),
           calendar_event_id        = COALESCE(calendar_event_id, NULLIF(v_interview.calendar_event_id, '')),
           updated_at               = now()
     WHERE id = v_event_id;
    RETURN v_event_id;
  END IF;

  -- Skip create if: no schedule, or is a mirrored (notes-marked) row
  IF v_interview.scheduled_at IS NULL THEN
    RETURN NULL;
  END IF;
  IF v_interview.notes IS NOT NULL AND v_interview.notes ILIKE '%[Espelhado%' THEN
    RETURN NULL;
  END IF;

  -- Create new events row sincronizado
  INSERT INTO public.events (
    type, title, date, time_start, duration_minutes, status,
    audience_level, visibility, nature, source,
    calendar_event_id, invited_member_ids, selection_application_id,
    organization_id, created_at, updated_at
  ) VALUES (
    'entrevista',
    'Entrevista — ' || COALESCE(v_app.applicant_name, 'Candidato')
      || COALESCE(' (' || v_app.cycle_code || ')', ''),
    v_event_date,
    v_event_time,
    COALESCE(v_interview.duration_minutes, 30),
    v_event_status,
    'leadership',   -- também forçado por trg_interview_audience_private
    'leadership',
    'entrevista_selecao',
    'selection_portal',
    NULLIF(v_interview.calendar_event_id, ''),
    v_interviewer_ids,
    v_interview.application_id,
    v_interview.organization_id,
    now(), now()
  )
  RETURNING id INTO v_event_id;

  RETURN v_event_id;
END;
$function$;

COMMENT ON FUNCTION public._sync_interview_to_event(uuid) IS
  'p170 ATT-1 — idempotent sync de selection_interviews → events row. Cobre todos os 4 paths de write. Skip para mirror (notes [Espelhado) e scheduled_at NULL. Status mapping noshow/rescheduled → cancelled (events.status CHECK só tem 3 valores).';

-- ============================================================
-- Trigger wrapper + binding
-- ============================================================
CREATE OR REPLACE FUNCTION public._trg_sync_interview_to_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Defensive: never let sync error break the parent INSERT/UPDATE (orphan event preferable to lost interview)
  BEGIN
    PERFORM public._sync_interview_to_event(NEW.id);
  EXCEPTION WHEN OTHERS THEN
    -- Log to data_anomaly_log so we can investigate without breaking parent op
    BEGIN
      INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
      VALUES (
        'interview_event_sync_error',
        'warning',
        'Failed to sync selection_interview to events row',
        jsonb_build_object(
          'interview_id', NEW.id,
          'application_id', NEW.application_id,
          'error', SQLERRM,
          'sqlstate', SQLSTATE
        )
      );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_sync_interview_to_event ON public.selection_interviews;
CREATE TRIGGER trg_sync_interview_to_event
  AFTER INSERT OR UPDATE OF scheduled_at, status, duration_minutes, calendar_event_id, interviewer_ids
  ON public.selection_interviews
  FOR EACH ROW
  EXECUTE FUNCTION public._trg_sync_interview_to_event();

COMMENT ON TRIGGER trg_sync_interview_to_event ON public.selection_interviews IS
  'p170 ATT-1 — AFTER INSERT/UPDATE sync events row. Idempotente (linka existing por calendar_event_id ou app_id+date+time). Skip mirror + scheduled_at NULL. Errors swallowed → data_anomaly_log.';

-- ============================================================
-- Backfill: para selection_interviews sem events row, criar agora
-- ============================================================
DO $$
DECLARE
  v_row record;
  v_event_id uuid;
  v_created int := 0;
  v_linked  int := 0;
  v_skipped int := 0;
BEGIN
  FOR v_row IN
    SELECT id, application_id, scheduled_at, notes
      FROM public.selection_interviews
     WHERE scheduled_at IS NOT NULL
       AND (notes IS NULL OR notes NOT ILIKE '%[Espelhado%')
     ORDER BY scheduled_at DESC NULLS LAST
  LOOP
    v_event_id := public._sync_interview_to_event(v_row.id);
    IF v_event_id IS NOT NULL THEN
      -- Distinguish create vs link: check if created_at within last 5sec
      IF EXISTS (
        SELECT 1 FROM public.events
         WHERE id = v_event_id AND created_at > (now() - interval '5 seconds')
      ) THEN
        v_created := v_created + 1;
      ELSE
        v_linked := v_linked + 1;
      END IF;
    ELSE
      v_skipped := v_skipped + 1;
    END IF;
  END LOOP;

  RAISE NOTICE 'p170 ATT-1 backfill: created=%, linked=%, skipped=%', v_created, v_linked, v_skipped;
END $$;

NOTIFY pgrst, 'reload schema';
