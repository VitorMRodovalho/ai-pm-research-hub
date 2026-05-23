-- p228 #260 W2 Leaf 6: operational suppress_all bypass for candidate-facing selection types
--
-- PM Policy Matrix Amendment D D-sel-4 (#260, 2026-05-23). p227 audit Section
-- "Policy Matrix Proposal" raised the question: should candidate-facing
-- operational emails bypass `notify_delivery_mode_pref = 'suppress_all'`? PM
-- decision: YES for the 4 candidate-facing operational selection_* types;
-- NO for marketing/digest/internal non-critical messages.
--
-- Workflow-critical operational > opt-out preference. Rationale: candidate is
-- in active workflow; opt-out for promotional vs operational must be split.
-- Legal/UX rationale documented in ADR-0022 Amendment D D-sel-4.
--
-- Implementation:
--   1. SQL-side helper `_is_operational_candidate_facing(p_type text)` —
--      source-of-truth boolean classifier for the 4 types. Used by future
--      SQL-side audits / digest cron exclusion / contract tests.
--   2. EF-side parity: send-notification-email/index.ts now lifts the
--      suppress_all skip when the notification type is operational + candidate-
--      facing. Hardcoded Set in EF matches the SQL helper byte-for-byte;
--      update both sides in lock-step (contract test enforces).
--
-- Scope: ONLY the 4 candidate-facing operational types bypass:
--   - selection_termo_due           (post-VEP-Active onboarding term)
--   - selection_approved            (approval milestone)
--   - selection_interview_scheduled (interview details with calendar link)
--   - selection_cutoff_approved     (invite to book interview after objective phase)
--
-- All other types — including peer_review_requested (evaluator-facing),
-- selection_evaluation_complete, selection_interview_overdue, governance digest,
-- marketing — STILL respect suppress_all. PM D-sel-4 wording is candidate-facing-
-- specific; evaluator-facing operational types remain bound by opt-out.

CREATE OR REPLACE FUNCTION public._is_operational_candidate_facing(p_type text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
SET search_path TO ''
AS $function$
  SELECT p_type IN (
    'selection_termo_due',
    'selection_approved',
    'selection_interview_scheduled',
    'selection_cutoff_approved'
  );
$function$;

REVOKE ALL ON FUNCTION public._is_operational_candidate_facing(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._is_operational_candidate_facing(text) TO authenticated, service_role;

COMMENT ON FUNCTION public._is_operational_candidate_facing(text) IS
'p228 #260 W2 Leaf 6: source-of-truth classifier for candidate-facing operational '
'selection notification types that BYPASS notify_delivery_mode_pref=suppress_all '
'per PM Policy Matrix Amendment D D-sel-4. EF send-notification-email matches '
'this Set byte-for-byte (update both sides in lock-step — contract test enforces).';

NOTIFY pgrst, 'reload schema';
