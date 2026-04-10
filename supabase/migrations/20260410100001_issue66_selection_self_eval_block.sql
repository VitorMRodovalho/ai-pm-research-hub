-- ============================================================
-- Issue #66: Selection — block self-evaluation via DB trigger
-- A BEFORE INSERT/UPDATE trigger on selection_evaluations ensures that
-- no caller can evaluate their own application — regardless of which
-- RPC path is used (submit_evaluation or submit_interview_scores).
-- ============================================================

CREATE OR REPLACE FUNCTION _block_self_evaluation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_evaluator_email text;
  v_applicant_email text;
BEGIN
  -- Get evaluator email
  SELECT email INTO v_evaluator_email FROM members WHERE id = NEW.evaluator_id;

  -- Get applicant email
  SELECT email INTO v_applicant_email FROM selection_applications WHERE id = NEW.application_id;

  IF v_evaluator_email IS NOT NULL
     AND v_applicant_email IS NOT NULL
     AND lower(trim(v_evaluator_email)) = lower(trim(v_applicant_email)) THEN
    RAISE EXCEPTION 'Conflict of interest: evaluator (%) cannot evaluate their own application (%)',
      v_evaluator_email, v_applicant_email
      USING HINT = 'Self-evaluation is not allowed. Another committee member must evaluate this candidacy.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_self_evaluation ON selection_evaluations;
CREATE TRIGGER trg_block_self_evaluation
BEFORE INSERT OR UPDATE ON selection_evaluations
FOR EACH ROW
EXECUTE FUNCTION _block_self_evaluation();

-- Sanity check: log existing self-evaluations (if any) for visibility.
-- These should all have been corrected by the admin_audit_log repair, but
-- we verify no residual self-eval rows exist.
DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM selection_evaluations e
  JOIN members m ON m.id = e.evaluator_id
  JOIN selection_applications a ON a.id = e.application_id
  WHERE lower(trim(m.email)) = lower(trim(a.email));
  IF v_count > 0 THEN
    RAISE NOTICE 'WARNING: % residual self-evaluation row(s) exist in selection_evaluations. Review and correct manually.', v_count;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
