-- p228 #260 W2 Leaf 1: ADR-0022 catalog + helper parity for 6 selection_* types
--
-- PM Policy Matrix ratified 2026-05-23 (#260 comment 4525886931). Audit doc:
-- docs/audit/SELECTION_NOTIFICATIONS_W2_AUDIT_P227.md. Pre-p228 state: ADR-0022
-- catalog had ZERO selection_* entries; helper had only `selection_termo_due`
-- (added p159, 2026-05-14). All other selection_* types fell through to ELSE
-- → `digest_weekly`, mis-routing 4 candidate-facing approval/interview rows in
-- the 90d window.
--
-- This migration brings 6 EXISTING selection_* types under helper coverage.
-- Two future types (`selection_interview_overdue`, `selection_cutoff_approved`)
-- are out of scope here — they ship in W2 Leaf 2 + Leaf 4.
--
-- Behavior change matrix (forward-only — existing rows handled by W2 Leaf 5 replay):
--   selection_termo_due           → transactional_immediate  (was: explicit, p159)
--   selection_approved            → transactional_immediate  (was: ELSE digest_weekly)
--   selection_interview_scheduled → transactional_immediate  (was: ELSE digest_weekly)
--   peer_review_requested         → transactional_immediate  (was: ELSE digest_weekly,
--                                                              hardcoded at INSERT site
--                                                              `dispatch_peer_review_invitations`)
--   selection_evaluation_complete → suppress                 (was: ELSE digest_weekly;
--                                                              admin-facing, dashboard-only)
--   selection_interview_noshow    → digest_weekly (explicit) (was: ELSE digest_weekly;
--                                                              made explicit for parity)
--
-- Catalog source of truth: docs/adr/ADR-0022-notification-types-catalog.json (bumped
-- to W1.4). Contract test tests/contracts/adr-0022-delivery-mode.test.mjs enforces
-- helper ↔ catalog parity + extends to lock the 6 selection_* policy decisions.

CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
SET search_path TO ''
AS $function$
  SELECT CASE p_type
    WHEN 'volunteer_agreement_signed'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_pending'  THEN 'transactional_immediate'
    WHEN 'system_alert'                  THEN 'transactional_immediate'
    WHEN 'certificate_ready'             THEN 'transactional_immediate'
    WHEN 'member_offboarded'             THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_advanced'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_chain_approved'   THEN 'transactional_immediate'
    WHEN 'ip_ratification_awaiting_members' THEN 'transactional_immediate'
    WHEN 'webinar_status_confirmed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_completed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_cancelled'      THEN 'transactional_immediate'
    WHEN 'weekly_card_digest_member'     THEN 'transactional_immediate'
    WHEN 'governance_cr_new'             THEN 'transactional_immediate'
    WHEN 'governance_cr_vote'            THEN 'transactional_immediate'
    WHEN 'governance_cr_approved'        THEN 'transactional_immediate'
    WHEN 'sponsor_finance_entry_logged'  THEN 'transactional_immediate'
    WHEN 'governance_manual_proposed'    THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d7_urgent'  THEN 'transactional_immediate'
    -- p153 OPP-153.1: project_charter (TAP) notifications
    WHEN 'project_charter_invite'        THEN 'transactional_immediate'
    WHEN 'project_charter_approved'      THEN 'transactional_immediate'
    -- p159 S#1 T1 (2026-05-14): selection_termo_due é o "email principal" pós-VEP-Active
    -- (termo + próximos passos + Lorena signatária). Não pode esperar digest semanal.
    WHEN 'selection_termo_due'           THEN 'transactional_immediate'
    -- p228 #260 W2 Leaf 1 (2026-05-23): PM Policy Matrix ratified for selection funnel.
    -- selection_approved / selection_interview_scheduled / peer_review_requested are
    -- transactional_immediate; selection_evaluation_complete is suppress (admin-only,
    -- surfaced via dashboard); selection_interview_noshow stays digest_weekly explicit
    -- for catalog parity and forward-drift detection.
    WHEN 'selection_approved'            THEN 'transactional_immediate'
    WHEN 'selection_interview_scheduled' THEN 'transactional_immediate'
    WHEN 'peer_review_requested'         THEN 'transactional_immediate'
    WHEN 'selection_evaluation_complete' THEN 'suppress'
    WHEN 'selection_interview_noshow'    THEN 'digest_weekly'
    -- (end p228)
    WHEN 'engagement_renewal_d30'        THEN 'digest_weekly'
    WHEN 'engagement_renewal_d60_gp_aggregate' THEN 'digest_weekly'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    ELSE 'digest_weekly'
  END;
$function$;

NOTIFY pgrst, 'reload schema';
