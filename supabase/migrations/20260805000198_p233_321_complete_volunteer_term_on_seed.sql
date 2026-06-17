-- Symmetric companion to trg_complete_volunteer_term_on_cert (mig 20260805000018).
-- That trigger fires AFTER INSERT ON certificates and completes the matching
-- onboarding_progress.volunteer_term row. It cannot fire when the onboarding row is
-- SEEDED *after* the cert already exists (member signed earlier; the step row is created
-- later by a lazy seed / re-init path) — the documented out-of-scope case in mig …018.
-- This installs the inverse guard on the onboarding side, mirroring the existing
-- trg_vep_acceptance_auto_complete_on_seed pattern.
--
-- Note: onboarding_progress.updated_at defaults to now(), so the BEFORE INSERT path does
-- not set NEW.updated_at (the column default covers it) — same as the vep_acceptance precedent.
--
-- Rollback:
--   DROP TRIGGER IF EXISTS trg_complete_volunteer_term_on_seed ON public.onboarding_progress;
--   DROP FUNCTION IF EXISTS public._trg_complete_volunteer_term_on_seed();
--   -- Backfilled rows persist as completed with metadata.completed_via='p233_seed_backfill'.
--   -- To revert those: UPDATE public.onboarding_progress SET status='pending', completed_at=NULL,
--   --   metadata = metadata - 'completed_via' - 'cert_id' - 'verification_code' - 'backfilled_at' - 'migration'
--   --   WHERE metadata->>'completed_via' = 'p233_seed_backfill';

CREATE OR REPLACE FUNCTION public._trg_complete_volunteer_term_on_seed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $function$
DECLARE
  v_cert record;
BEGIN
  IF NEW.member_id IS NULL THEN RETURN NEW; END IF;

  SELECT c.id, c.issued_at, c.verification_code
    INTO v_cert
  FROM public.certificates c
  WHERE c.member_id = NEW.member_id
    AND c.type = 'volunteer_agreement'
    AND c.status = 'issued'
  ORDER BY c.issued_at DESC
  LIMIT 1;

  IF v_cert.id IS NOT NULL THEN
    NEW.status       := 'completed';
    NEW.completed_at := COALESCE(v_cert.issued_at, now());
    NEW.metadata     := COALESCE(NEW.metadata, '{}'::jsonb) || jsonb_build_object(
      'completed_via', 'cert_seed_guard',
      'cert_id', v_cert.id,
      'verification_code', v_cert.verification_code,
      'migration', '20260805000198'
    );
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_complete_volunteer_term_on_seed ON public.onboarding_progress;

CREATE TRIGGER trg_complete_volunteer_term_on_seed
BEFORE INSERT ON public.onboarding_progress
FOR EACH ROW
WHEN (NEW.step_key = 'volunteer_term' AND NEW.status = 'pending')
EXECUTE FUNCTION public._trg_complete_volunteer_term_on_seed();

COMMENT ON FUNCTION public._trg_complete_volunteer_term_on_seed() IS
  '#321 companion (mig 20260805000198): completes a freshly-seeded onboarding_progress.volunteer_term row at INSERT time when the member already has an issued volunteer_agreement cert. Closes the inverse gap of trg_complete_volunteer_term_on_cert (which fires cert-side and cannot re-fire when the step row is created after the cert). Mirrors trg_vep_acceptance_auto_complete_on_seed.';

-- Backfill: complete any volunteer_term rows already in pending state whose member has an
-- issued cert (catches rows seeded after the cert before this trigger existed — e.g. the
-- 2026-06-16 phantom). Idempotent; mirrors the backfill in mig …018.
DO $$
DECLARE
  v_affected int;
BEGIN
  WITH latest_cert_per_member AS (
    SELECT DISTINCT ON (c.member_id)
      c.member_id, c.id AS cert_id, c.issued_at, c.verification_code
    FROM public.certificates c
    WHERE c.type = 'volunteer_agreement' AND c.status = 'issued'
    ORDER BY c.member_id, c.issued_at DESC
  ),
  updated AS (
    UPDATE public.onboarding_progress op
    SET status = 'completed',
        completed_at = COALESCE(lcm.issued_at, now()),
        updated_at = now(),
        metadata = COALESCE(op.metadata, '{}'::jsonb) || jsonb_build_object(
          'completed_via', 'p233_seed_backfill',
          'cert_id', lcm.cert_id,
          'verification_code', lcm.verification_code,
          'backfilled_at', now(),
          'migration', '20260805000198'
        )
    FROM latest_cert_per_member lcm
    WHERE op.member_id = lcm.member_id
      AND op.step_key = 'volunteer_term'
      AND op.status = 'pending'
    RETURNING op.id, op.member_id, lcm.cert_id
  ),
  audit_insert AS (
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    SELECT NULL::uuid, 'p233_321_seed_backfill_volunteer_term_phantom', 'onboarding_progress',
      u.id, jsonb_build_object('onboarding_progress_id', u.id, 'member_id', u.member_id,
        'cert_id_linked', u.cert_id, 'migration', '20260805000198')
    FROM updated u
    RETURNING target_id
  )
  SELECT count(*) INTO v_affected FROM audit_insert;
  RAISE NOTICE '#321 seed-backfill: % phantom volunteer_term rows marked completed.', v_affected;
END$$;

-- Sanity: 0 pending vol_term rows may remain where an issued cert exists.
DO $$
DECLARE v_phantom_count int;
BEGIN
  SELECT count(*) INTO v_phantom_count
  FROM public.onboarding_progress op
  WHERE op.step_key = 'volunteer_term' AND op.status = 'pending'
    AND EXISTS (SELECT 1 FROM public.certificates c
                WHERE c.member_id = op.member_id AND c.type = 'volunteer_agreement' AND c.status = 'issued');
  IF v_phantom_count > 0 THEN
    RAISE EXCEPTION '#321 seed-guard sanity FAIL: % pending volunteer_term rows still have matching cert.', v_phantom_count;
  END IF;
  RAISE NOTICE '#321 seed-guard sanity OK: 0 pending volunteer_term rows with matching cert.';
END$$;

NOTIFY pgrst, 'reload schema';
