-- ============================================================================
-- p233 — #321 / Gap A of #230 reframe:
--   complete onboarding_progress.volunteer_term when matching cert is issued
-- ADR: ADR-0006 (Person + Engagement) / ADR-0007 (Authority)
--
-- Purpose:
--   sign_volunteer_agreement() (mig 20260415020000 + p219 fixes) inserts a
--   certificates row of type='volunteer_agreement' but does NOT atomically mark
--   the corresponding onboarding_progress.volunteer_term row as completed.
--   Result: phantom-pending volunteer_term steps on member dashboards even
--   when the cert already exists. Live evidence at p230 audit (2026-05-23):
--   30 of 38 pending volunteer_term rows have a matching cert (88% phantom rate).
--
--   This migration:
--   (1) Installs an AFTER INSERT trigger on certificates that — when a row of
--       type='volunteer_agreement' is inserted (WHEN clause) — UPDATEs the
--       matching onboarding_progress row (by member_id + step_key) to
--       status='completed', completed_at = NEW.issued_at. Idempotent via
--       status != 'completed' guard.
--   (2) Backfills the currently-phantom rows in-tx using each member's latest
--       issued vol_agreement cert's issued_at as completed_at (historical
--       accuracy). Audits each row.
--
-- Scope:
--   - Trigger scope: type='volunteer_agreement' ONLY (WHEN clause) + member_id
--     NOT NULL (body guard, defense-in-depth).
--   - Sibling triggers on certificates (trg_auto_remove_designation_on_cert,
--     trg_certificate_pdf_autogen) continue to run independently.
--
-- Out of scope (per issue #321):
--   - Gap B (4 active + 7 inactive without cert) — handled by #322.
--   - Gap C (study_group_* catalog config) — handled by #323.
--   - Stale-term re-nudge cron — deferred per #230 reframe.
--   - check_schema_invariants() new invariant — PM call per issue body (may
--     be too strict during in-flight signing windows where the step row is
--     created in the same tx as cert mint; current trigger handles that
--     atomically but external paths may not — defer until Gap B+C ship).
--
-- Rollback:
--   DROP TRIGGER IF EXISTS trg_complete_volunteer_term_on_cert ON public.certificates;
--   DROP FUNCTION IF EXISTS public._trg_complete_volunteer_term_on_cert();
--   -- Backfilled rows persist as completed with metadata.completed_via='p233_backfill'.
--   -- To revert: UPDATE public.onboarding_progress SET status='pending',
--   --   completed_at=NULL, metadata = metadata - 'completed_via' - 'cert_id'
--   --     - 'verification_code' - 'backfilled_at' - 'migration'
--   --   WHERE metadata->>'completed_via' = 'p233_backfill';
-- ============================================================================

-- ════════════════════════════════════════════════════════════════════════
-- (1) FORWARD-FIX trigger
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._trg_complete_volunteer_term_on_cert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $function$
DECLARE
  v_rows_affected int;
BEGIN
  -- Defense-in-depth: WHEN clause already gates type, but member_id NULL is
  -- a paranoid guard (column is NOT NULL but trigger should never panic).
  IF NEW.member_id IS NULL THEN RETURN NEW; END IF;

  -- Atomic completion of matching onboarding_progress row.
  -- Idempotent: WHERE status != 'completed' skips already-done rows.
  -- Single-row update via UNIQUE (member_id, step_key) index.
  UPDATE public.onboarding_progress
  SET
    status = 'completed',
    completed_at = COALESCE(NEW.issued_at, now()),
    updated_at = now(),
    metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
      'completed_via', 'cert_trigger',
      'cert_id', NEW.id,
      'verification_code', NEW.verification_code,
      'migration', '20260805000018'
    )
  WHERE member_id = NEW.member_id
    AND step_key = 'volunteer_term'
    AND status != 'completed';

  GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

  -- Audit only when we actually flipped a row (avoids noisy audit on no-op).
  IF v_rows_affected > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (
      NEW.issued_by,
      'onboarding.volunteer_term_completed_on_cert',
      'certificate',
      NEW.id,
      jsonb_build_object(
        'member_id', NEW.member_id,
        'cert_id', NEW.id,
        'verification_code', NEW.verification_code,
        'rows_affected', v_rows_affected,
        'completed_at', COALESCE(NEW.issued_at, now()),
        'migration', '20260805000018'
      )
    );
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_complete_volunteer_term_on_cert ON public.certificates;

CREATE TRIGGER trg_complete_volunteer_term_on_cert
AFTER INSERT ON public.certificates
FOR EACH ROW
WHEN (NEW.type = 'volunteer_agreement')
EXECUTE FUNCTION public._trg_complete_volunteer_term_on_cert();

COMMENT ON FUNCTION public._trg_complete_volunteer_term_on_cert() IS
  '#321 (p233 / Gap A of #230 reframe): atomically marks onboarding_progress.volunteer_term as completed when a volunteer_agreement certificate is inserted for the member. Gated by WHEN clause (type) + body guard (member_id NOT NULL). Idempotent via status!=completed guard. Audits when rows_affected > 0.';

-- ════════════════════════════════════════════════════════════════════════
-- (2) BACKFILL: phantom-pending vol_term rows where matching cert exists
-- ════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_affected int;
  v_affected_ids uuid[];
BEGIN
  WITH latest_cert_per_member AS (
    SELECT DISTINCT ON (c.member_id)
      c.member_id,
      c.id AS cert_id,
      c.issued_at,
      c.verification_code
    FROM public.certificates c
    WHERE c.type = 'volunteer_agreement'
      AND c.status = 'issued'
    ORDER BY c.member_id, c.issued_at DESC
  ),
  updated AS (
    UPDATE public.onboarding_progress op
    SET
      status = 'completed',
      completed_at = COALESCE(lcm.issued_at, now()),
      updated_at = now(),
      metadata = COALESCE(op.metadata, '{}'::jsonb) || jsonb_build_object(
        'completed_via', 'p233_backfill',
        'cert_id', lcm.cert_id,
        'verification_code', lcm.verification_code,
        'backfilled_at', now(),
        'migration', '20260805000018'
      )
    FROM latest_cert_per_member lcm
    WHERE op.member_id = lcm.member_id
      AND op.step_key = 'volunteer_term'
      AND op.status = 'pending'
    RETURNING op.id, op.member_id, lcm.cert_id
  ),
  audit_insert AS (
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    SELECT
      NULL::uuid AS actor_id,
      'p233_321_backfill_volunteer_term_phantom' AS action,
      'onboarding_progress' AS target_type,
      u.id AS target_id,
      jsonb_build_object(
        'onboarding_progress_id', u.id,
        'member_id', u.member_id,
        'cert_id_linked', u.cert_id,
        'migration', '20260805000018'
      )
    FROM updated u
    RETURNING target_id
  )
  SELECT count(*), array_agg(target_id) INTO v_affected, v_affected_ids FROM audit_insert;

  RAISE NOTICE '#321 backfill: % phantom volunteer_term rows marked completed. IDs: %', v_affected, v_affected_ids;
END$$;

-- ════════════════════════════════════════════════════════════════════════
-- SANITY check: 0 pending vol_term should remain where matching cert exists
-- ════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_phantom_count int;
BEGIN
  SELECT count(*) INTO v_phantom_count
  FROM public.onboarding_progress op
  WHERE op.step_key = 'volunteer_term'
    AND op.status = 'pending'
    AND EXISTS (
      SELECT 1 FROM public.certificates c
      WHERE c.member_id = op.member_id
        AND c.type = 'volunteer_agreement'
        AND c.status = 'issued'
    );

  IF v_phantom_count > 0 THEN
    RAISE EXCEPTION '#321 sanity FAIL: % pending volunteer_term rows still have matching cert. Backfill query failed.', v_phantom_count;
  END IF;
  RAISE NOTICE '#321 sanity OK: 0 pending volunteer_term rows with matching cert.';
END$$;

NOTIFY pgrst, 'reload schema';
