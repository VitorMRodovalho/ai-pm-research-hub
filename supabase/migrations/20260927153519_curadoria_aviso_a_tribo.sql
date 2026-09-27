-- #2496: a tribo passa a ser avisada quando o item entra em curadoria.
--
-- Antes: na transicao para curation_pending, os participantes do card recebiam so card_moved
-- (digest_weekly), com o codigo cru do status e link /workspace; a lideranca da iniciativa nao
-- recebia nada; e quem tinha dois papeis no card recebia em dobro. Comite e revisores ja
-- recebiam aviso imediato (#186, #2444).
--
-- Depois:
--   1. tipo novo curation_submitted_to_tribe, imediato (_delivery_mode_for recriado a partir do
--      corpo vivo, com um WHEN a mais);
--   2. notify_on_curation_status_change avisa participantes + lideranca ativa, uma vez por
--      pessoa, com link para o board da tribo; o laco de card_moved deixa a transicao de
--      entrada para esse aviso e passa a usar DISTINCT.

CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE p_type
    -- PR-2 (email audit): the per-signing leadership alert is now in-app only; the daily
    -- digest (volunteer_term_signed_digest) carries the single aggregated email.
    WHEN 'volunteer_agreement_signed'    THEN 'suppress'
    WHEN 'volunteer_term_signed_digest'  THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_pending'  THEN 'transactional_immediate'
    WHEN 'system_alert'                  THEN 'transactional_immediate'
    -- #1169: ready is redundant with issued at the email layer (issued carries the single email);
    -- kept in-app only. Every ready-cert already fired an issued email (0 ready-without-issued/60d).
    WHEN 'certificate_ready'             THEN 'suppress'
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
    -- #2325 (2026-09-16): o LEMBRETE de que o termo segue aberto. Tipo proprio, separado de
    -- `selection_termo_due` (que anuncia a ABERTURA, no aceite do VEP, e e alvo de replay).
    -- Nasceu porque a cobranca saia como `system`, que o catalogo manda suprimir: 26 avisos a
    -- 16 pessoas que nunca deixaram a plataforma. Catalogado de proposito em vez de cair no
    -- ELSE: o ELSE e `digest_weekly`, que carimba como entregue o que nao renderiza (#2286).
    WHEN 'volunteer_term_pending'        THEN 'transactional_immediate'
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
    -- #2013 (2026-08-26): o teto de lembretes de reagendamento foi atingido e o caso vira
    -- trabalho de gente. Imediato de proposito: e o unico aviso, e o digest semanal so
    -- entrega a quem tem OUTRO conteudo na semana (#2010).
    WHEN 'selection_reschedule_escalated' THEN 'transactional_immediate'
    -- #186 (2026-06-05): curation committee broadcast when an item enters curation_pending
    WHEN 'curation_item_submitted'       THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d30'        THEN 'digest_weekly'
    WHEN 'engagement_renewal_d60_gp_aggregate' THEN 'digest_weekly'
    -- #625 F3 (2026-06-11): radar de renovação de filiação
    WHEN 'affiliation_renewal_d7_urgent'  THEN 'transactional_immediate'
    WHEN 'affiliation_renewal_d30'        THEN 'digest_weekly'
    WHEN 'affiliation_verification_stale' THEN 'digest_weekly'
    -- #1855 (2026-08-18): faixa de filiacao ja VENCIDA. Catalogado de proposito, e nao deixado
    -- cair no ELSE, pelo mesmo motivo registrado no bloco 5b da #625: o ELSE e um default de
    -- conveniencia e um dia muda. digest_weekly porque o PM decidiu 'so lembrete, mesmo tom'.
    WHEN 'affiliation_renewal_expired'    THEN 'digest_weekly'
    -- #2152 (2026-09-03): a verificacao ficou atras do VEP. Vai para a diretoria, nao para o
    -- membro, e no mesmo modo da faixa irma de verificacao obsoleta: e trabalho de fila, nao
    -- urgencia. Catalogado em vez de cair no ELSE, pelo motivo registrado acima.
    WHEN 'affiliation_vep_divergence'     THEN 'digest_weekly'
    -- #1224 PR2 (2026-07-09): one-time onboarding nudge when the PMI enrichment cannot resolve
    -- an entry chapter (profile_private / no_fetch / not_affiliated / ambiguous-no-choice).
    WHEN 'entry_chapter_action_needed'    THEN 'transactional_immediate'
    -- #740 Wave 3c-i (B8): agreement rejected / reissued — member must re-sign, deliver immediately
    WHEN 'volunteer_agreement_rejected'  THEN 'transactional_immediate'
    WHEN 'volunteer_agreement_reissued'  THEN 'transactional_immediate'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    -- #2285 (2026-09-14): o detector de contas nao ligadas passou a ter cron. Catalogado de
    -- proposito, e nao deixado cair no ELSE, pelo mesmo motivo registrado acima para #625,
    -- #1855 e #2152. Aqui o ELSE e pior que um default inconveniente: digest_weekly monta as
    -- secoes por lista branca de tipos e carimba como entregue o que nao renderizou (#2286).
    WHEN 'unlinked_accounts_detected'     THEN 'transactional_immediate'
    -- #2444 (2026-09-24): rodizio de pareceristas da curadoria. Imediato de proposito: a
    -- designacao e o lembrete sao o que da dono ao parecer; o digest semanal chegaria depois do
    -- prazo de 7 dias. O vencido vai para quem gere a plataforma, tambem imediato: e decisao.
    WHEN 'curation_review_assigned'       THEN 'transactional_immediate'
    WHEN 'curation_review_overdue'        THEN 'transactional_immediate'
    -- #2496 (2026-09-27): aviso a tribo (participantes do card e lideranca da iniciativa) de que o
    -- item entrou em curadoria. Imediato de proposito: caia em card_moved (digest_weekly), com o
    -- codigo cru do status e link generico, e nenhuma das 3 pessoas da tribo recebeu e-mail.
    WHEN 'curation_submitted_to_tribe'    THEN 'transactional_immediate'
    -- #2444 (2026-09-24): a revisao do lider e a devolucao ao autor. Imediatos de proposito: caiam no
    -- ELSE (digest_weekly) e, medido, leader_review_requested nunca gerou uma linha sequer; sem aviso,
    -- 16 cards ficaram parados em leader_review desde maio.
    WHEN 'leader_review_requested'        THEN 'transactional_immediate'
    WHEN 'leader_review_returned'         THEN 'transactional_immediate'
    -- #2454 (2026-09-24): falha de acesso ao Drive. Imediatos: a pessoa esta sem acesso a pasta da
    -- iniciativa agora (e nao sabia: 3 casos medidos), e a falha da conta de servico e acao do
    -- administrador do Workspace.
    WHEN 'drive_access_action_needed'     THEN 'transactional_immediate'
    WHEN 'drive_access_admin_needed'      THEN 'transactional_immediate'
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
  v_assignee      record;
  v_curator       record;
  v_recipient     record;
  v_initiative_id uuid;
  v_tribe_id      integer;
  v_link          text;
  v_prazo         text;
BEGIN
  -- Notify all assignees when curation_status changes.
  -- #2496: a ENTRADA em curadoria tem aviso proprio (bloco no fim), e cada pessoa recebe uma vez
  -- mesmo com dois papeis no card (autor e colaborador geravam duas linhas).
  IF NEW.curation_status IS DISTINCT FROM OLD.curation_status
    AND NEW.curation_status IS NOT NULL
    AND NEW.curation_status != 'draft'
    AND NEW.curation_status != 'curation_pending' THEN

    FOR v_assignee IN
      SELECT DISTINCT bia.member_id FROM board_item_assignments bia WHERE bia.item_id = NEW.id
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

  -- #2496: aviso a TRIBO na mesma transicao. Vai uma vez para cada pessoa ativa entre os
  -- participantes do card e a lideranca ativa da iniciativa do board, com link para o board da
  -- tribo (ou para a pagina da iniciativa), e o prazo do parecer quando ele ja existe.
  IF NEW.curation_status = 'curation_pending'
     AND OLD.curation_status IS DISTINCT FROM 'curation_pending' THEN
    SELECT pb.initiative_id, i.legacy_tribe_id
      INTO v_initiative_id, v_tribe_id
    FROM project_boards pb
    LEFT JOIN initiatives i ON i.id = pb.initiative_id
    WHERE pb.id = NEW.board_id;

    v_link := CASE
      WHEN v_tribe_id IS NOT NULL      THEN '/tribe/' || v_tribe_id || '?tab=board'
      WHEN v_initiative_id IS NOT NULL THEN '/initiative/' || v_initiative_id
      ELSE '/workspace'
    END;
    v_prazo := to_char(NEW.curation_due_at AT TIME ZONE 'America/Sao_Paulo', 'DD/MM');

    FOR v_recipient IN
      SELECT r.member_id
      FROM (
        SELECT bia.member_id FROM board_item_assignments bia WHERE bia.item_id = NEW.id
        UNION
        SELECT m.id FROM engagements e JOIN members m ON m.person_id = e.person_id
        WHERE v_initiative_id IS NOT NULL
          AND e.initiative_id = v_initiative_id
          AND e.status = 'active'
          AND e.role = 'leader'
      ) r
      JOIN members mr ON mr.id = r.member_id
      WHERE mr.member_status = 'active'
    LOOP
      PERFORM create_notification(
        v_recipient.member_id,
        'curation_submitted_to_tribe',
        'Seu trabalho entrou em curadoria',
        '"' || NEW.title || '" entrou na curadoria.'
          || CASE WHEN v_prazo IS NOT NULL THEN ' Prazo do parecer: ' || v_prazo || '.' ELSE '' END
          || ' O andamento aparece no card, na etapa Curadoria.',
        v_link,
        'board_item',
        NEW.id
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$function$;
