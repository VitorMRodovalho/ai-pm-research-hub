-- p159 Sessão #1 T3: edge case trigger — VEP Active BEFORE Núcleo approval
--
-- Discovery (p157 #2 header documented gap, p159 priorização aprovada): existing trigger
-- `trg_vep_acceptance_on_active` fires only on UPDATE OF selection_applications.vep_status_raw.
-- When admin_update_application or finalize_decisions seeds vep_acceptance as pending AND the
-- VEP is already Active at that moment (recruiter marked Active before Núcleo approved), the
-- seed inserts pending row but the existing trigger doesn't fire (no UPDATE of vep_status_raw
-- happened in this transaction). Result: vep_acceptance stays pending until the next worker
-- poll re-asserts vep_status_raw (max ~24h delay).
--
-- This BEFORE INSERT trigger closes the gap at seed-time. When a new vep_acceptance pending
-- row is being inserted on onboarding_progress AND the linked selection_application's
-- vep_status_raw is already 'Active', mutate NEW row to status='completed' before insert.
-- Idempotent: subsequent worker polls of the existing trigger see the row already completed,
-- UPDATE matches 0 rows.
--
-- Notification (selection_termo_due) intentionally NOT fired here — let the worker-poll
-- trigger (`trg_vep_acceptance_on_active`) handle it on next poll. Reason: keeps this trigger
-- minimal + reuses existing notification path with same dedup rules. Acceptable: max 24h
-- delay for the term notification email.

CREATE OR REPLACE FUNCTION public._trg_vep_acceptance_auto_complete_on_seed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.selection_applications
    WHERE id = NEW.application_id
      AND vep_status_raw = 'Active'
  ) THEN
    NEW.status       := 'completed';
    NEW.completed_at := now();
  END IF;
  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public._trg_vep_acceptance_auto_complete_on_seed() IS
  'BEFORE INSERT trigger on onboarding_progress (vep_acceptance + pending). When the linked selection_applications row has vep_status_raw=Active at seed-time, mutates NEW to completed. Closes the edge case where VEP Active precedes Núcleo approval. Notification termo_due handled by trg_vep_acceptance_on_active on next worker poll. p159 S#1 T3 (2026-05-14).';

DROP TRIGGER IF EXISTS trg_vep_acceptance_auto_complete_on_seed ON public.onboarding_progress;
CREATE TRIGGER trg_vep_acceptance_auto_complete_on_seed
BEFORE INSERT ON public.onboarding_progress
FOR EACH ROW
WHEN (NEW.step_key = 'vep_acceptance' AND NEW.status = 'pending')
EXECUTE FUNCTION public._trg_vep_acceptance_auto_complete_on_seed();

COMMENT ON TRIGGER trg_vep_acceptance_auto_complete_on_seed ON public.onboarding_progress IS
  'Closes p157 #2 edge case: VEP Active before Núcleo approval. Sibling to trg_vep_acceptance_on_active (UPDATE-driven). p159 S#1 T3.';

NOTIFY pgrst, 'reload schema';
