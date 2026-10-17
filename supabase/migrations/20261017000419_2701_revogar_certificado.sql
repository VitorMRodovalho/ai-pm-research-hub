-- #2701 — revogar certificado: função própria, auditada, com aviso ao membro.
--
-- Medido em 16/10/2026: 5 certificados revogados (4 alumni_recognition, 1 excellence), todos gravados direto no
-- banco pelo GP entre 03/07 e 19/08; 1 deles sem linha em admin_audit_log. A tela não tinha botão desde a #2702
-- (chamava revoke_certificate, que não existia, e dizia "Revogado"), e o MCP não revogava. verify_certificate já
-- responde valid=false para status diferente de 'issued'; nenhuma linha de gamification_points aponta para
-- certificado, então revogar não tem estorno.
--
-- Decisões do GP em 16/10/2026: função + botão + MCP; portão manage_member (o mesmo do distrato e da
-- contra-assinatura); o membro recebe aviso no sino com o motivo, sem e-mail.
--
-- (1) _delivery_mode_for: 'certificate_revoked' => suppress (sino). Corpo = vivo em 16/10 (captura da C3b,
--     20261016163628) + uma linha; a pós-condição confere outros tipos.
-- (2) revoke_certificate(p_certificate_id, p_reason): manage_member; motivo obrigatório (até 500); só status
--     'issued'; o Termo de Voluntariado segue pelo distrato (reject_certificate), que também solta o engajamento;
--     grava revoked_at/by/reason, linha 'certificate_revoked' em admin_audit_log e o aviso ao membro.
--
-- Rollback: recriar _delivery_mode_for pela captura da C3b; DROP FUNCTION public.revoke_certificate(uuid, text).

-- ── (1) catálogo de entrega ──────────────────────────────────────────────────
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
    -- #2580 C1 (2026-10-08): no sino na hora; o e-mail sai no resumo diario da gestao. `suppress` e nao
    -- digest_weekly: o resumo semanal so le digest_weekly, entao nao ha carimbo sem renderizar (#2286).
    WHEN 'unlinked_accounts_detected'     THEN 'suppress'
    -- #2580 C: o resumo diario da gestao e um e-mail proprio.
    WHEN 'management_daily_digest'        THEN 'transactional_immediate'
    -- #2444 (2026-09-24): rodizio de pareceristas da curadoria. Imediato de proposito: a
    -- designacao e o lembrete sao o que da dono ao parecer; o digest semanal chegaria depois do
    -- prazo de 7 dias. O vencido vai para quem gere a plataforma, tambem imediato: e decisao.
    WHEN 'curation_review_assigned'       THEN 'transactional_immediate'
    WHEN 'curation_review_overdue'        THEN 'transactional_immediate'
    -- #2496 (2026-09-27): aviso a tribo (participantes do card e lideranca da iniciativa) de que o
    -- item entrou em curadoria. Imediato de proposito: caia em card_moved (digest_weekly), com o
    -- codigo cru do status e link generico, e nenhuma das 3 pessoas da tribo recebeu e-mail.
    WHEN 'curation_submitted_to_tribe'    THEN 'transactional_immediate'
    -- #2621 (2026-10-09): a DECISAO da curadoria volta para a mesma audiencia do aviso de entrada
    -- (participantes do card e lideranca ativa da iniciativa). Imediatos de proposito: devolucao e
    -- rejeicao nao avisavam ninguem, e o primeiro parecer real da plataforma passou mudo; no ELSE
    -- (digest_weekly) o pedido de ajuste chegaria dias depois, com o prazo do autor correndo.
    WHEN 'curation_decision_returned'     THEN 'transactional_immediate'
    WHEN 'curation_decision_rejected'     THEN 'transactional_immediate'
    WHEN 'curation_decision_approved'     THEN 'transactional_immediate'
    -- #2495 (2026-09-27): piloto do wiki vivo (ADR-0129, emenda 2). Imediatos de proposito: a
    -- lideranca publica na hora e o comite audita em 14 dias; um aviso que chegasse no digest
    -- semanal comeria metade do prazo. O vencido vai para quem gere a plataforma.
    WHEN 'wiki_review_requested'          THEN 'transactional_immediate'
    WHEN 'wiki_page_decision'             THEN 'transactional_immediate'
    WHEN 'wiki_audit_requested'           THEN 'transactional_immediate'
    WHEN 'wiki_audit_overdue'             THEN 'transactional_immediate'
    -- #2495 fase B2 (2026-09-29): "Sugerir melhoria". Imediatos pelo mesmo motivo dos avisos do wiki
    -- acima: a sugestao vai a quem decide sobre a pagina, e a resposta volta a quem sugeriu; um aviso
    -- no digest semanal chegaria depois de a pessoa ter esquecido o que sugeriu.
    WHEN 'wiki_suggestion_received'       THEN 'transactional_immediate'
    WHEN 'wiki_suggestion_decision'       THEN 'transactional_immediate'
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
    -- Varredura de dado pessoal no tracker publico (10/10/2026). Imediato de proposito: o dado segue publico
    -- enquanto ninguem age, e no ELSE (digest_weekly) o e-mail chegaria em ate sete dias.
    WHEN 'tracker_pii_found'              THEN 'transactional_immediate'
    -- #2593 (C2, decisão do GP 11/10/2026): o dono do bloco da Agenda Viva sabe pelo sino, não por e-mail, quando
    -- a coordenação confirma ou cancela o bloco dele. Catalogados para não cair no ELSE (digest_weekly), que
    -- mandaria um resumo semanal de algo que só serve na hora.
    WHEN 'agenda_block_confirmed'         THEN 'suppress'
    WHEN 'agenda_block_cancelled'         THEN 'suppress'
    -- #2593 (C3b, 16/10/2026): convidado externo de reunião próxima que ainda não recebeu o convite (sem e-mail,
    -- bloco reservado ou convite não entregue). No sino do dono e da coordenação; o cron repete a cada 2 dias
    -- enquanto durar. Catalogado para não cair no ELSE (digest_weekly), que chegaria depois da reunião.
    WHEN 'agenda_guest_attention'         THEN 'suppress'
    -- #2701 (16/10/2026): certificado revogado; o membro sabe pelo sino, com o motivo. Decisão do GP: sem e-mail.
    WHEN 'certificate_revoked'            THEN 'suppress'
    ELSE 'digest_weekly'
  END;
$function$;

-- ── (2) revogar ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.revoke_certificate(p_certificate_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cert      record;
  v_reason    text := left(btrim(COALESCE(p_reason, '')), 500);
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'not_authorized', 'required', 'manage_member');
  END IF;
  IF v_reason = '' THEN
    RETURN jsonb_build_object('error', 'reason_required');
  END IF;

  SELECT * INTO v_cert FROM public.certificates WHERE id = p_certificate_id FOR UPDATE;
  IF v_cert.id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_found');
  END IF;
  -- o Termo de Voluntariado tem caminho próprio (distrato), que também solta o termo do engajamento
  IF v_cert.type = 'volunteer_agreement' THEN
    RETURN jsonb_build_object('error', 'use_reject_for_agreement');
  END IF;
  IF v_cert.status IS DISTINCT FROM 'issued' THEN
    RETURN jsonb_build_object('error', 'not_revocable', 'status', v_cert.status);
  END IF;

  UPDATE public.certificates
     SET status = 'revoked', revoked_at = now(), revoked_by = v_caller_id,
         revoked_reason = v_reason, updated_at = now()
   WHERE id = p_certificate_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'certificate_revoked', 'certificate', p_certificate_id,
    jsonb_build_object('verification_code', v_cert.verification_code, 'reason', v_reason,
      'type', v_cert.type, 'cycle', v_cert.cycle, 'member_id', v_cert.member_id,
      'previous_status', v_cert.status));

  -- decisão do GP: o membro sabe pelo sino, com o motivo; sem e-mail (_delivery_mode_for => suppress)
  INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
  VALUES (v_cert.member_id, 'certificate_revoked',
    'Certificado revogado',
    'Seu certificado "' || v_cert.title || '" foi revogado em '
      || to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY') || '. Motivo: ' || v_reason
      || '. A verificação pública deste certificado passa a responder que ele não é válido.',
    '/gamification', 'certificate', p_certificate_id,
    public._delivery_mode_for('certificate_revoked'));

  RETURN jsonb_build_object('success', true, 'certificate_id', p_certificate_id, 'status', 'revoked');
END;
$function$;
REVOKE ALL ON FUNCTION public.revoke_certificate(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_certificate(uuid, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- ── pós-condição ─────────────────────────────────────────────────────────────
DO $postcondition$
BEGIN
  IF public._delivery_mode_for('certificate_revoked') IS DISTINCT FROM 'suppress'
     OR public._delivery_mode_for('agenda_guest_attention') IS DISTINCT FROM 'suppress'
     OR public._delivery_mode_for('volunteer_agreement_rejected') IS DISTINCT FROM 'transactional_immediate'
     OR public._delivery_mode_for('tipo_que_nao_existe_2701') IS DISTINCT FROM 'digest_weekly' THEN
    RAISE EXCEPTION '#2701: o catálogo de entrega não ficou como esperado';
  END IF;
  IF has_function_privilege('anon', 'public.revoke_certificate(uuid, text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.revoke_certificate(uuid, text)', 'EXECUTE') THEN
    RAISE EXCEPTION '#2701: privilégio fora do esperado';
  END IF;
  -- a migration não tem sessão: a revogação recusa sem gravar nada
  IF (public.revoke_certificate(gen_random_uuid(), 'x')->>'error') IS DISTINCT FROM 'not_authenticated' THEN
    RAISE EXCEPTION '#2701: a revogação não recusou chamada sem sessão';
  END IF;
END
$postcondition$;
