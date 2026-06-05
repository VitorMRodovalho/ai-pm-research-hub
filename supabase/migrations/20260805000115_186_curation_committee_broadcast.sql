-- =====================================================================
-- #186 — Broadcast to the curation committee when an item enters curation
-- =====================================================================
-- BUG: when an item transitions to curation_status='curation_pending' (via
--   submit_for_curation() or the p196 auto-submit safety-net trigger), NOBODY
--   on the curation committee is notified. The only curation-status notifier
--   (notify_on_curation_status_change) loops solely over board_item_assignments,
--   so the canonical "submit without naming curators" path notifies nobody — the
--   7-day SLA silently depends on curators manually polling /admin/curatorship.
--
-- FIX (PM decision 2026-06-05 = immediate email + in-app to the curators):
--   (1) new notification type 'curation_item_submitted' → transactional_immediate
--       in _delivery_mode_for (immediate email; create_notification also inserts
--       the in-app row + respects notification_preferences mute/in_app).
--   (2) notify_on_curation_status_change broadcasts to every ACTIVE member with
--       V4 curate_content authority on the curation_pending TRANSITION (idempotent:
--       fires once, guarded by OLD.curation_status IS DISTINCT FROM 'curation_pending').
--       Links to /admin/curatorship. Covers BOTH submit_for_curation and the p196
--       auto-submit path (both flow through this AFTER-UPDATE trigger).
--
-- SCOPE LOCK: both functions reproduced byte-equivalent from their live bodies +
--   the targeted additions. _delivery_mode_for keeps its historical WHEN catalog
--   (adr-0022 parity); only one WHEN added. notifications.type has no CHECK
--   constraint (new type is free).
--
-- INVARIANTS: check_schema_invariants() unaffected.
-- ROLLBACK: drop the 'curation_item_submitted' WHEN from _delivery_mode_for and
--   the curate_content broadcast block from notify_on_curation_status_change.
-- CROSS-REF: #186, p196 (auto-submit trigger), ADR-0022 (delivery modes), ADR-0007 (can()).
-- =====================================================================

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
    WHEN 'selection_termo_due'           THEN 'transactional_immediate'
    -- p228 #260 W2 Leaf 1 (2026-05-23): Selection funnel Policy Matrix
    WHEN 'selection_approved'            THEN 'transactional_immediate'
    WHEN 'selection_interview_scheduled' THEN 'transactional_immediate'
    WHEN 'peer_review_requested'         THEN 'transactional_immediate'
    WHEN 'selection_evaluation_complete' THEN 'suppress'
    WHEN 'selection_interview_noshow'    THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 2 (2026-05-23): admin reminder for overdue interviews
    WHEN 'selection_interview_overdue'   THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 4 (2026-05-23): candidate invite to book interview after
    -- objective evaluations cleared + research_score >= cycle cutoff.
    WHEN 'selection_cutoff_approved'     THEN 'transactional_immediate'
    -- (end p228)
    -- #186 (2026-06-05): curation committee broadcast when an item enters curation_pending
    WHEN 'curation_item_submitted'       THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d30'        THEN 'digest_weekly'
    WHEN 'engagement_renewal_d60_gp_aggregate' THEN 'digest_weekly'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    ELSE 'digest_weekly'
  END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_on_curation_status_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_assignee record;
  v_curator  record;
BEGIN
  -- Notify all assignees when curation_status changes
  IF NEW.curation_status IS DISTINCT FROM OLD.curation_status
    AND NEW.curation_status IS NOT NULL
    AND NEW.curation_status != 'draft' THEN

    FOR v_assignee IN
      SELECT bia.member_id FROM board_item_assignments bia WHERE bia.item_id = NEW.id
    LOOP
      PERFORM create_notification(
        v_assignee.member_id,
        'card_moved',
        'Status de curadoria alterado',
        '"' || NEW.title || '" agora está em: ' || NEW.curation_status,
        '/workspace',
        'board_item',
        NEW.id
      );
    END LOOP;
  END IF;

  -- #186: broadcast to the curation committee on the curation_pending TRANSITION.
  -- Covers submit_for_curation() and the p196 auto-submit path (both update curation_status).
  IF NEW.curation_status = 'curation_pending'
     AND OLD.curation_status IS DISTINCT FROM 'curation_pending' THEN
    FOR v_curator IN
      SELECT m.id
      FROM members m
      WHERE m.member_status = 'active'
        AND public.can_by_member(m.id, 'curate_content')
    LOOP
      PERFORM create_notification(
        v_curator.id,
        'curation_item_submitted',
        'Nova peça para curadoria',
        '"' || NEW.title || '" entrou na fila de curadoria.',
        '/admin/curatorship',
        'board_item',
        NEW.id
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$function$;

NOTIFY pgrst, 'reload schema';
