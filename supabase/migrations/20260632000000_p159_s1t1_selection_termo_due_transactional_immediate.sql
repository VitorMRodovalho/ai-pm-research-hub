-- p159 Sessão #1 T1: selection_termo_due → transactional_immediate
--
-- PM clarification 14/05: candidato recebe email DEPOIS de VEP→Active. selection_termo_due
-- (criado pelo p157 #2 trigger) é o "email principal" com termo + próximos passos + Lorena
-- como signatária do termo. delivery_mode atual = digest_weekly (fallback ELSE) → email
-- espera até 1 semana, atrita com expectativa PM.
--
-- selection_approved é deixado em digest_weekly (PM clarification: by-design — bell in-app
-- imediato é suficiente; email canônico vem com termo_due).
--
-- Audit (p159 close, 14/05): 13 selection_termo_due rows hoje (todas via backfill p157 #2),
-- 0 com email_sent_at populated. Mudança terá efeito a partir do próximo selection_termo_due
-- criado pelo trigger.

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
    -- (end p153)
    -- p159 S#1 T1 (2026-05-14): selection_termo_due é o "email principal" pós-VEP-Active
    -- (termo + próximos passos + Lorena signatária). Não pode esperar digest semanal.
    WHEN 'selection_termo_due'           THEN 'transactional_immediate'
    -- (end p159)
    WHEN 'engagement_renewal_d30'        THEN 'digest_weekly'
    WHEN 'engagement_renewal_d60_gp_aggregate' THEN 'digest_weekly'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    ELSE 'digest_weekly'
  END;
$function$;

NOTIFY pgrst, 'reload schema';
