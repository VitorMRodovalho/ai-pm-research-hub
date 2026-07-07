-- PR-2: collapse the per-signing volunteer term alert into ONE daily digest email.
--
-- (a) _delivery_mode_for: volunteer_agreement_signed flips transactional_immediate -> suppress.
--     The per-signing rows still land in-app (bell) via sign_volunteer_agreement, but no longer
--     trigger a 1-a-1 email. New type volunteer_term_signed_digest is transactional_immediate so
--     the existing send-notification-email cron (jobid 9) delivers the ONE daily aggregate row.
-- (b) _volunteer_term_signed_digest_cron: once a day, if any term was signed in the last 24h,
--     insert ONE aggregate notification per target recipient (GP manage_platform + sede
--     voluntariado director). Same 3-recipient audience as the recipient fix (PR-1). 20h
--     idempotency guards against a double run. Piggybacks the jobid-59 daily-digest pattern.
-- (c) schedule the cron daily at 21:00 UTC (~18:00 BRT, end of day).
--
-- Net effect on Resend quota: on an activation/onboarding day (e.g. 19 signings today = 72 emails
-- across 13 wrong recipients) the term workflow drops to at most 3 emails/day (one digest each).

-- (a) delivery-mode routing. Reproduced verbatim from live with two edits (see comments below).
CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $function$
  SELECT CASE p_type
    -- PR-2 (email audit): the per-signing leadership alert is now in-app only; the daily
    -- digest (volunteer_term_signed_digest) carries the single aggregated email.
    WHEN 'volunteer_agreement_signed'    THEN 'suppress'
    WHEN 'volunteer_term_signed_digest'  THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_pending'  THEN 'transactional_immediate'
    WHEN 'system_alert'                  THEN 'transactional_immediate'
    WHEN 'certificate_ready'             THEN 'transactional_immediate'
    WHEN 'certificate_issued'            THEN 'transactional_immediate'
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
    -- #625 F3 (2026-06-11): radar de renovação de filiação
    WHEN 'affiliation_renewal_d7_urgent'  THEN 'transactional_immediate'
    WHEN 'affiliation_renewal_d30'        THEN 'digest_weekly'
    WHEN 'affiliation_verification_stale' THEN 'digest_weekly'
    -- #740 Wave 3c-i (B8): agreement rejected / reissued — member must re-sign, deliver immediately
    WHEN 'volunteer_agreement_rejected'  THEN 'transactional_immediate'
    WHEN 'volunteer_agreement_reissued'  THEN 'transactional_immediate'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    ELSE 'digest_weekly'
  END;
$function$;

-- (b) daily aggregator. Same 3-recipient audience as PR-1 (GP + sede voluntariado director),
-- one email/day via the existing jobid-9 cron (volunteer_term_signed_digest = transactional_immediate).
CREATE OR REPLACE FUNCTION public._volunteer_term_signed_digest_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_contracting_code text;
  v_count int;
  v_list text;
  v_body text;
  v_recipients int := 0;
BEGIN
  SELECT cr.chapter_code INTO v_contracting_code
  FROM chapter_registry cr
  WHERE cr.is_contracting_chapter = true AND cr.is_active = true
  LIMIT 1;
  v_contracting_code := COALESCE(v_contracting_code, 'GO');

  SELECT count(*),
         string_agg('- ' || m.name || ' (' || COALESCE(m.chapter, '—') || ')', E'\n' ORDER BY m.name)
    INTO v_count, v_list
  FROM certificates c
  JOIN members m ON m.id = c.member_id
  WHERE c.type = 'volunteer_agreement'
    AND c.status = 'issued'
    AND c.issued_at >= now() - interval '24 hours';

  IF COALESCE(v_count, 0) = 0 THEN
    RETURN jsonb_build_object('signings', 0, 'recipients', 0, 'skipped', 'no_signings');
  END IF;

  v_body := v_count || ' voluntário(s) assinaram o Termo de Voluntariado nas últimas 24h:'
    || E'\n\n' || v_list
    || E'\n\nAbra /admin/certificates para conferir e contra-assinar.';

  INSERT INTO notifications (recipient_id, type, title, body, link, delivery_mode)
  SELECT m.id, 'volunteer_term_signed_digest',
    'Termos de Voluntariado assinados (' || v_count || ')',
    v_body, '/admin/certificates',
    public._delivery_mode_for('volunteer_term_signed_digest')
  FROM members m
  WHERE m.is_active = true
    AND (public.can_by_member(m.id, 'manage_platform')
         OR ('voluntariado_director' = ANY(m.designations) AND m.chapter = 'PMI-' || v_contracting_code))
    AND NOT EXISTS (
      SELECT 1 FROM notifications n
      WHERE n.recipient_id = m.id
        AND n.type = 'volunteer_term_signed_digest'
        AND n.created_at >= now() - interval '20 hours'
    );
  GET DIAGNOSTICS v_recipients = ROW_COUNT;

  RETURN jsonb_build_object('signings', v_count, 'recipients', v_recipients);
END;
$function$;

REVOKE ALL ON FUNCTION public._volunteer_term_signed_digest_cron() FROM PUBLIC, anon, authenticated;

-- (c) schedule daily at 21:00 UTC (~18:00 BRT). cron.schedule upserts by name (pg_cron >= 1.4).
SELECT cron.schedule('term-signed-digest-daily', '0 21 * * *', $$SELECT public._volunteer_term_signed_digest_cron()$$);
