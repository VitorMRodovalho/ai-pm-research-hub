-- WHAT: Trigger central that advances selection_applications.status when a
--       selection_interviews row is inserted or its status/conducted_at flips.
--       Closes the gap between the calendar webhook (#116), manual schedule,
--       mark_interview_status, and submit_interview_scores — all of which
--       touch selection_interviews but don't reliably advance the parent app.
-- WHY:  PM-reported 2026-05-24 (#251 reopened p240): Luíse Quintana +
--       William Junio (researcher) + 8 others in cycle4-2026 were labelled
--       'Aguardando Entrevista' in /admin/selection despite having completed
--       interviews + submitted interview evals. Root cause: mark_interview_status
--       has precondition status IN ('interview_scheduled','interview_done')
--       that silently no-ops when the row is still 'interview_pending'; and
--       submit_interview_scores only advances when ALL interviewers submitted.
--       Most cycle4 interview rows came in via webhook (status='scheduled'
--       direct INSERT) and the app status never moved off 'interview_pending'.
-- ROLLBACK: DROP TRIGGER trg_sync_interview_to_app_status; DROP FUNCTION
--           public._trg_sync_interview_to_app_status();
--           Reverse backfill via audit rows action='p240_251_backfill_*' if needed.

CREATE OR REPLACE FUNCTION public._trg_sync_interview_to_app_status() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_app_status text;
BEGIN
  SELECT status INTO v_app_status
  FROM public.selection_applications
  WHERE id = NEW.application_id;

  -- Terminal / locked statuses: trigger never overwrites these.
  -- (PM directive 2026-05-24: trigger nunca toca terminal.)
  IF v_app_status IS NULL OR v_app_status IN (
    'approved', 'rejected', 'converted', 'withdrawn', 'cancelled', 'waitlist', 'final_eval'
  ) THEN
    RETURN NEW;
  END IF;

  -- Evidence: interview conducted (conducted_at set OR status='completed') → interview_done
  IF NEW.conducted_at IS NOT NULL OR NEW.status = 'completed' THEN
    UPDATE public.selection_applications
       SET status = 'interview_done', updated_at = now()
     WHERE id = NEW.application_id
       AND status IN ('screening', 'objective_eval', 'objective_cutoff', 'interview_pending', 'interview_scheduled');
    RETURN NEW;
  END IF;

  -- Evidence: interview scheduled/rescheduled (not yet conducted) → interview_scheduled
  IF NEW.status IN ('scheduled', 'rescheduled') THEN
    UPDATE public.selection_applications
       SET status = 'interview_scheduled', updated_at = now()
     WHERE id = NEW.application_id
       AND status IN ('screening', 'objective_eval', 'objective_cutoff', 'interview_pending');
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$func$;

REVOKE EXECUTE ON FUNCTION public._trg_sync_interview_to_app_status() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_sync_interview_to_app_status ON public.selection_interviews;
CREATE TRIGGER trg_sync_interview_to_app_status
AFTER INSERT OR UPDATE OF status, conducted_at ON public.selection_interviews
FOR EACH ROW EXECUTE FUNCTION public._trg_sync_interview_to_app_status();

-- Backfill cycle4-2026 + cycle3-2026-b2 (PM-approved scope 2026-05-24).
-- Idempotent: only writes when target_status differs from current.
WITH cy AS (
  SELECT id FROM public.selection_cycles
  WHERE cycle_code IN ('cycle4-2026', 'cycle3-2026-b2')
),
fix AS (
  SELECT a.id,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM public.selection_evaluations e
        WHERE e.application_id = a.id
          AND e.evaluation_type = 'interview'
          AND e.submitted_at IS NOT NULL
      ) THEN 'interview_done'
      WHEN EXISTS (
        SELECT 1 FROM public.selection_interviews i
        WHERE i.application_id = a.id
          AND (i.conducted_at IS NOT NULL OR i.status = 'completed')
      ) THEN 'interview_done'
      WHEN EXISTS (
        SELECT 1 FROM public.selection_interviews i
        WHERE i.application_id = a.id
          AND i.status IN ('scheduled', 'rescheduled')
      ) THEN 'interview_scheduled'
      ELSE a.status
    END AS target_status
  FROM public.selection_applications a
  JOIN cy ON cy.id = a.cycle_id
  WHERE a.status NOT IN (
    'approved', 'rejected', 'converted', 'withdrawn', 'cancelled', 'waitlist', 'final_eval'
  )
)
UPDATE public.selection_applications a
   SET status = f.target_status, updated_at = now()
  FROM fix f
 WHERE f.id = a.id
   AND f.target_status <> a.status;

-- Audit trail for the backfill — admin_audit_log canonical (PM-app touches).
INSERT INTO public.admin_audit_log (action, actor_id, target_type, target_id, metadata, created_at)
SELECT
  'p240_251_backfill_interview_status' AS action,
  NULL AS actor_id,
  'selection_application' AS target_type,
  a.id AS target_id,
  jsonb_build_object(
    'reason', 'p240_251_interview_status_transition_backfill',
    'migration', '20260805000025',
    'new_status', a.status,
    'cycle_code', c.cycle_code
  ) AS metadata,
  now() AS created_at
FROM public.selection_applications a
JOIN public.selection_cycles c ON c.id = a.cycle_id
WHERE c.cycle_code IN ('cycle4-2026', 'cycle3-2026-b2')
  AND a.updated_at >= now() - interval '5 seconds'
  AND a.status IN ('interview_scheduled', 'interview_done');

-- Sanity DO block: fail-loud if backfill missed any goal-metric row.
DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE c.cycle_code IN ('cycle4-2026', 'cycle3-2026-b2')
    AND a.status = 'interview_pending'
    AND EXISTS (
      SELECT 1 FROM public.selection_evaluations e
      WHERE e.application_id = a.id
        AND e.evaluation_type = 'interview'
        AND e.submitted_at IS NOT NULL
    );
  IF v_count > 0 THEN
    RAISE EXCEPTION 'p240 #251 backfill drift: % rows still in interview_pending with submitted interview eval', v_count;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
