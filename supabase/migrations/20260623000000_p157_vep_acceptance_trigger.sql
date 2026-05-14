-- p157 #2: VEP→Termo automation — AFTER UPDATE trigger on vep_status_raw='Active'
--
-- Problem: PMI VEP recruiter side flips a candidate to "Active" (accepted into the VEP) but the
-- Núcleo side has no signal. The candidate's onboarding step `vep_acceptance` (canonical step
-- order 4 of 7, label "Aceitar posição no VEP") stays pending forever and they're never nudged
-- to sign the Termo de Voluntário. Confirmed via p157 prep query: of 25 candidates currently with
-- vep_status_raw='Active' AND status='approved', 6 have vep_acceptance pending and 8 have no row
-- at all (pre-#1 approvals where canonical seed wasn't applied). Both cohorts are blocked.
--
-- This migration installs:
-- 1) Trigger function process_vep_acceptance_transition() — idempotent: marks vep_acceptance as
--    completed for the member, INSERTs the row if missing, and nudges with selection_termo_due
--    notification ONLY when the change actually happened AND volunteer_term is still pending
--    (avoid noise + avoid pushing toward a non-existent step).
-- 2) Trigger trg_vep_acceptance_on_active — fires on every UPDATE of vep_status_raw when new
--    value is 'Active'. Worker pmi-vep-sync refreshes the row on every poll (resume_url SAS Azure
--    48h TTL — memory feedback_pmi_vep_ingest_logic_canonical.md), so even no-change writes are
--    expected. Function body is idempotent so re-fires are no-ops.
-- 3) Backfill — handles the 14 existing rows in the current state (6 pending + 8 missing).
--
-- Out of scope (known gap, documented for follow-up):
-- * vep_status_raw='Active' BEFORE Núcleo approval AND Núcleo approval happens between worker
--   polls: the trigger doesn't fire on selection_applications.status changes, so vep_acceptance
--   stays pending until next worker poll (≤24h typically). Acceptable for current cadence; if
--   it becomes painful, second trigger ON UPDATE OF status with WHEN status='approved' + check
--   vep_status_raw='Active' would close it.
-- * Members with completely missing canonical onboarding (pre-#1 approvals, 8 of the 25 here):
--   this migration INSERTs vep_acceptance specifically. Other canonical steps stay missing.
--   That's a broader retrofit (backlog: "retrofit canonical onboarding for legacy-seeded
--   members") — separate migration.

CREATE OR REPLACE FUNCTION public.process_vep_acceptance_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id     uuid;
  v_marked        boolean := false;
  v_term_pending  boolean;
BEGIN
  -- Find member by email (case-insensitive). May not exist if VEP flipped Active before Núcleo
  -- approval created the member row — silent no-op in that case (caught when status='approved'
  -- triggers canonical seed + next worker poll re-fires this trigger).
  SELECT id INTO v_member_id
  FROM public.members
  WHERE lower(email) = lower(NEW.email)
  LIMIT 1;

  IF v_member_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Idempotent mark-or-insert: only treat as a real transition (v_marked) when row count
  -- changes. Subsequent worker polls hit "already completed" path and no-op cleanly.
  UPDATE public.onboarding_progress
  SET    status       = 'completed',
         completed_at = now(),
         updated_at   = now()
  WHERE  member_id = v_member_id
    AND  step_key  = 'vep_acceptance'
    AND  status    = 'pending';

  IF FOUND THEN
    v_marked := true;
  ELSE
    -- Row may be missing entirely (pre-#1 approval — canonical seed didn't include vep_acceptance).
    -- Insert as completed so dashboard shows it correctly. Skip if a row already exists in any
    -- status (e.g. 'completed' from prior trigger fire or manual UI mark).
    INSERT INTO public.onboarding_progress
      (application_id, member_id, step_key, status, completed_at, metadata)
    SELECT NEW.id, v_member_id, 'vep_acceptance', 'completed', now(), '{}'::jsonb
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.onboarding_progress
      WHERE member_id = v_member_id AND step_key = 'vep_acceptance'
    );

    IF FOUND THEN v_marked := true; END IF;
  END IF;

  -- Nudge candidate to sign Termo only if (a) we actually transitioned just now and (b) the
  -- volunteer_term step is still pending. If volunteer_term row is missing (8 of the 25 current
  -- cases) we skip the notification — pushing toward a non-existent step would confuse the user.
  IF v_marked THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.onboarding_progress
      WHERE member_id = v_member_id
        AND step_key  = 'volunteer_term'
        AND status    = 'pending'
    ) INTO v_term_pending;

    IF v_term_pending THEN
      PERFORM public.create_notification(
        v_member_id,
        'selection_termo_due',
        'Termo de Voluntário disponível para assinatura',
        'Sua aceitação no VEP foi confirmada. Acesse seu onboarding para assinar o Termo de Voluntário e seguir para a próxima etapa.',
        '/onboarding',
        'selection_application',
        NEW.id
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.process_vep_acceptance_transition() IS
  'AFTER UPDATE trigger function on selection_applications.vep_status_raw. When VEP recruiter marks Active, marks the candidate''s vep_acceptance onboarding step as completed (idempotent — UPDATE pending OR INSERT if missing) and nudges with selection_termo_due notification when volunteer_term is still pending. p157 #2 (2026-05-14).';

DROP TRIGGER IF EXISTS trg_vep_acceptance_on_active ON public.selection_applications;
CREATE TRIGGER trg_vep_acceptance_on_active
AFTER UPDATE OF vep_status_raw ON public.selection_applications
FOR EACH ROW
WHEN (NEW.vep_status_raw = 'Active')
EXECUTE FUNCTION public.process_vep_acceptance_transition();

COMMENT ON TRIGGER trg_vep_acceptance_on_active ON public.selection_applications IS
  'Fires on any UPDATE that touches vep_status_raw and leaves it = Active. Worker pmi-vep-sync refreshes the row on every poll (resume_url SAS 48h TTL) so no-change writes also fire this — function body is idempotent. p157 #2.';

-- ─── Backfill ─────────────────────────────────────────────────────────────
-- Current state (verified pre-migration): 25 Active VEP candidates, all status=approved,
-- all members matched. 6 have vep_acceptance pending, 8 have no vep_acceptance row, 11 already
-- completed. Backfill closes the first two cohorts.

-- 1) UPDATE the 6 pending → completed.
UPDATE public.onboarding_progress op
SET    status       = 'completed',
       completed_at = now(),
       updated_at   = now()
FROM   public.selection_applications a
JOIN   public.members m ON lower(m.email) = lower(a.email)
WHERE  op.member_id  = m.id
  AND  op.step_key   = 'vep_acceptance'
  AND  op.status     = 'pending'
  AND  a.vep_status_raw = 'Active'
  AND  a.status         = 'approved';

-- 2) INSERT vep_acceptance=completed for the 8 missing (no canonical row).
INSERT INTO public.onboarding_progress
  (application_id, member_id, step_key, status, completed_at, metadata)
SELECT a.id, m.id, 'vep_acceptance', 'completed', now(), '{}'::jsonb
FROM   public.selection_applications a
JOIN   public.members m ON lower(m.email) = lower(a.email)
WHERE  a.vep_status_raw = 'Active'
  AND  a.status         = 'approved'
  AND  NOT EXISTS (
    SELECT 1 FROM public.onboarding_progress op
    WHERE op.member_id = m.id AND op.step_key = 'vep_acceptance'
  );

-- 3) Notifications backfill — for the 14 affected (6+8), send selection_termo_due IF
--    volunteer_term is still pending AND we haven't sent this notification before (dedup by
--    recipient_id + type + source_id). create_notification respects notification_preferences.
DO $backfill$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT DISTINCT a.id AS application_id, m.id AS member_id
    FROM   public.selection_applications a
    JOIN   public.members m ON lower(m.email) = lower(a.email)
    WHERE  a.vep_status_raw = 'Active'
      AND  a.status         = 'approved'
      AND  EXISTS (
        SELECT 1 FROM public.onboarding_progress op_t
        WHERE op_t.member_id = m.id
          AND op_t.step_key  = 'volunteer_term'
          AND op_t.status    = 'pending'
      )
      AND  NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = m.id
          AND n.type         = 'selection_termo_due'
          AND n.source_id    = a.id
      )
  LOOP
    PERFORM public.create_notification(
      r.member_id,
      'selection_termo_due',
      'Termo de Voluntário disponível para assinatura',
      'Sua aceitação no VEP foi confirmada. Acesse seu onboarding para assinar o Termo de Voluntário e seguir para a próxima etapa.',
      '/onboarding',
      'selection_application',
      r.application_id
    );
  END LOOP;
END
$backfill$;

NOTIFY pgrst, 'reload schema';
