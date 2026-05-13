-- W4 + W5 / OPP-153.1 — pmo_liaison designation + project_charter notification hooks
-- a) extend _delivery_mode_for() with 2 new types (invite + approved)
-- b) trigger that creates notifications when project_charter chain transitions to 'approved'
-- c) RLS: pmo_liaison may read comments on project_charter documents

-- ── a) Extend delivery mode taxonomy ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
 RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE
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
    -- (end p153)
    WHEN 'engagement_renewal_d30'        THEN 'digest_weekly'
    WHEN 'engagement_renewal_d60_gp_aggregate' THEN 'digest_weekly'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    ELSE 'digest_weekly'
  END;
$function$;

-- ── b) Trigger: notify PMO liaisons + submitter when a project_charter chain transitions to 'approved' ──
CREATE OR REPLACE FUNCTION public.notify_project_charter_chain_approved()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $function$
DECLARE
  v_doc record;
  v_pmo record;
BEGIN
  IF NEW.status = 'approved' AND (OLD.status IS NULL OR OLD.status <> 'approved') THEN
    SELECT gd.id, gd.title, gd.doc_type, gd.initiative_id
    INTO v_doc
    FROM public.governance_documents gd
    WHERE gd.id = NEW.document_id AND gd.doc_type = 'project_charter';

    IF v_doc.id IS NULL THEN RETURN NEW; END IF;

    -- Notify all PMO liaisons (Eder etc.) in the host chapter (PMI-GO for TAPs)
    FOR v_pmo IN
      SELECT id FROM public.members
      WHERE 'pmo_liaison' = ANY(designations) AND is_active = true AND chapter = 'PMI-GO'
    LOOP
      PERFORM public.create_notification(
        v_pmo.id, 'project_charter_approved',
        'governance_document', v_doc.id,
        'TAP aprovado: ' || v_doc.title, NEW.closed_by
      );
    END LOOP;

    -- Notify submitter (GP do Núcleo)
    IF NEW.opened_by IS NOT NULL AND NEW.opened_by <> NEW.closed_by THEN
      PERFORM public.create_notification(
        NEW.opened_by, 'project_charter_approved',
        'governance_document', v_doc.id,
        'Seu TAP foi aprovado: ' || v_doc.title, NEW.closed_by
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_project_charter_chain_approved ON public.approval_chains;
CREATE TRIGGER trg_notify_project_charter_chain_approved
  AFTER UPDATE ON public.approval_chains
  FOR EACH ROW EXECUTE FUNCTION public.notify_project_charter_chain_approved();

-- ── c) Additive RLS: pmo_liaison may read comments on project_charter docs ──
DROP POLICY IF EXISTS document_comments_pmo_liaison_read ON public.document_comments;
CREATE POLICY document_comments_pmo_liaison_read ON public.document_comments
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND 'pmo_liaison' = ANY(m.designations)
        AND m.is_active = true
    )
    AND EXISTS (
      SELECT 1 FROM public.document_versions dv
      JOIN public.governance_documents gd ON gd.id = dv.document_id
      WHERE dv.id = document_comments.document_version_id
        AND gd.doc_type = 'project_charter'
    )
  );

COMMENT ON FUNCTION public.notify_project_charter_chain_approved IS
  'p153 OPP-153.1: notifies PMO liaisons + submitter when a project_charter chain is approved. Email dispatch via downstream cron / transactional_immediate delivery.';
