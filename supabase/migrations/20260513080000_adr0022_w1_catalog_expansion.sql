-- ADR-0022 W1 — catalog expansion to preserve send-notification-email V1 behavior.
--
-- The W1 EF refactor switches send-notification-email from a hardcoded
-- CRITICAL_TYPES array to filtering by `delivery_mode = 'transactional_immediate'`.
-- To avoid silent regression in email delivery for types currently in
-- CRITICAL_TYPES but not yet in the W1 catalog, this migration:
--
-- 1. Updates `_delivery_mode_for` helper to include the additional 9 types.
-- 2. Backfills existing notifications rows of those 9 types to
--    `transactional_immediate` so they continue to be picked up by the EF.
--
-- Catalog updates (also in docs/adr/ADR-0022-notification-types-catalog.json):
--   transactional_immediate:
--     governance_cr_new, governance_cr_vote, governance_cr_approved
--     webinar_status_confirmed, webinar_status_completed, webinar_status_cancelled
--     ip_ratification_gate_advanced, ip_ratification_chain_approved,
--     ip_ratification_awaiting_members
--     weekly_card_digest_member
--
-- Behavior change: `attendance_detractor` is in EF CRITICAL_TYPES but the
-- W1 catalog (Q1 PM decision) maps it to `suppress`. PM accepted this
-- tightening as part of ADR-0022 — detractor signal stays in-app, prevents
-- email noise to members already showing detractor pattern.
-- Backfill UPDATE in 20260513060000 already set existing detractor rows to
-- `suppress`. New rows route to suppress via _delivery_mode_for(). Net effect:
-- send-notification-email no longer emails detractor type after this lands.

CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $function$
  SELECT CASE p_type
    -- Mandatory transactional_immediate (W1 catalog)
    WHEN 'volunteer_agreement_signed'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_pending'  THEN 'transactional_immediate'
    WHEN 'system_alert'                  THEN 'transactional_immediate'
    WHEN 'certificate_ready'             THEN 'transactional_immediate'
    WHEN 'member_offboarded'             THEN 'transactional_immediate'
    -- Catalog expansion (preserve EF V1 behavior)
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
    -- In-app only (suppressed from email)
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    -- Default: digest_weekly
    ELSE 'digest_weekly'
  END;
$function$;

-- Backfill existing rows of the 10 newly-classified transactional_immediate
-- types (those not already covered by the original W1 backfill).
UPDATE public.notifications SET delivery_mode = 'transactional_immediate'
  WHERE type IN (
    'ip_ratification_gate_advanced',
    'ip_ratification_chain_approved',
    'ip_ratification_awaiting_members',
    'webinar_status_confirmed',
    'webinar_status_completed',
    'webinar_status_cancelled',
    'weekly_card_digest_member',
    'governance_cr_new',
    'governance_cr_vote',
    'governance_cr_approved'
  )
  AND delivery_mode <> 'transactional_immediate';

NOTIFY pgrst, 'reload schema';
