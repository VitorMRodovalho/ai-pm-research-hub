-- #2593, fatia C3b — aviso interno de convidado externo ainda sem convite, e certificado do convidado a partir do bloco.
--
-- Medido em 16/10/2026: um bloco com convidado externo, criado antes da C1, ficou 9 dias reservado e sem e-mail sem
-- que ninguém soubesse (o cron de pendências só olha reunião que já passou, para o XP); e issue_event_guest_certificate
-- não tem tela nem usa a pessoa do bloco, então o e-mail do convidado seria digitado de novo.
--
-- (1) _delivery_mode_for: 'agenda_guest_attention' => suppress (sino). Corpo = captura da C2 (20261011143731, md5
--     normalizado 21439e42 = vivo em 16/10) + uma linha; a pós-condição confere os outros tipos.
-- (2) _agenda_guest_attention_cron(): blocos com convidado externo de reuniões nos próximos 7 dias (no fuso do
--     evento, fora as canceladas) que ainda não receberam o convite: sem e-mail, ainda reservados, ou confirmados
--     sem aviso entregue. Avisa o dono do bloco e quem tem manage_event, um aviso por (pessoa, bloco) a cada 2 dias.
--     Cron agenda-guest-attention às 12:05 UTC.
-- (3) issue_agenda_guest_certificate(bloco): manage_event ou manage_platform; só bloco confirmado com convidado
--     externo, depois do início da reunião; usa o e-mail do vínculo do bloco e chama issue_event_guest_certificate
--     (que acha a pessoa pelo e-mail, a mesma que a C1 criou). Não manda e-mail; o PDF sai pelo gatilho (#2709).
--
-- Rollback: recriar _delivery_mode_for pela captura da C2; DROP das duas funções novas;
--   cron.unschedule('agenda-guest-attention').

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
    ELSE 'digest_weekly'
  END;
$function$;

-- ── (2) aviso de convidado ainda sem convite ─────────────────────────────────
CREATE OR REPLACE FUNCTION public._agenda_guest_attention_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_blocks   integer := 0;
  v_inserted integer := 0;
BEGIN
  IF public._request_is_rest_caller() THEN
    RAISE EXCEPTION 'Unauthorized: _agenda_guest_attention_cron is cron-only';
  END IF;

  SELECT count(*) INTO v_blocks FROM public._agenda_guest_attention_rows();

  INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode, created_at)
  SELECT m.id,
         'agenda_guest_attention',
         'Convidado externo da Reunião Geral ainda sem convite',
         CASE a.motivo
           WHEN 'sem_email' THEN format('O bloco "%s" na Reunião Geral de %s tem convidado externo sem e-mail. Sem o e-mail, o convite não sai: edite o bloco e informe o e-mail.', a.title, to_char(a.event_date, 'DD/MM/YYYY'))
           WHEN 'nao_confirmado' THEN format('O bloco "%s" na Reunião Geral de %s tem convidado externo e ainda está reservado. O convite só sai quando o bloco é confirmado, em Admin > Agenda Viva.', a.title, to_char(a.event_date, 'DD/MM/YYYY'))
           ELSE format('O bloco "%s" na Reunião Geral de %s está confirmado, mas o convite ao convidado externo não foi entregue. Confira em Admin > Agenda Viva.', a.title, to_char(a.event_date, 'DD/MM/YYYY'))
         END,
         '/admin/agenda-viva',
         'agenda_block',
         a.block_id,
         public._delivery_mode_for('agenda_guest_attention'),
         now()
  FROM public._agenda_guest_attention_rows() a
  JOIN public.members m ON m.is_active = true
   AND (m.id = a.owner_member_id OR public._can_anywhere(m.person_id, 'manage_event'))
  WHERE NOT EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.recipient_id = m.id AND n.type = 'agenda_guest_attention' AND n.source_id = a.block_id
      AND n.created_at >= now() - interval '2 days');
  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (NULL, 'agenda.guest_attention_cron_run', 'system', NULL,
          jsonb_build_object('blocks', v_blocks, 'notifications_inserted', v_inserted),
          jsonb_build_object('source', '_agenda_guest_attention_cron', 'issue', 2593));

  RETURN jsonb_build_object('blocks', v_blocks, 'notifications_inserted', v_inserted);
END;
$function$;

-- As linhas que precisam de atenção, num lugar só (o cron e a pós-condição leem daqui).
CREATE OR REPLACE FUNCTION public._agenda_guest_attention_rows()
 RETURNS TABLE (block_id uuid, owner_member_id uuid, title text, event_date date, motivo text)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT b.id, b.owner_member_id, b.title, e.date,
         CASE
           WHEN NOT EXISTS (SELECT 1 FROM public.person_external_links l
                            WHERE l.purpose = 'agenda_guest' AND l.source_id = b.id AND l.contact_email IS NOT NULL)
             THEN 'sem_email'
           WHEN b.status = 'reserved' THEN 'nao_confirmado'
           ELSE 'nao_avisado'
         END
  FROM public.event_agenda_blocks b
  JOIN public.events e ON e.id = b.event_id
  WHERE b.external_guest AND b.status IN ('reserved', 'confirmed') AND b.guest_notified_at IS NULL
    AND e.status IS DISTINCT FROM 'cancelled' AND e.time_start IS NOT NULL
    AND (e.date + e.time_start) AT TIME ZONE COALESCE(e.timezone, 'America/Sao_Paulo') > now()
    AND e.date <= (now() AT TIME ZONE COALESCE(e.timezone, 'America/Sao_Paulo'))::date + 7;
$function$;

REVOKE ALL ON FUNCTION public._agenda_guest_attention_cron() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._agenda_guest_attention_rows() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._agenda_guest_attention_cron() TO service_role;
GRANT EXECUTE ON FUNCTION public._agenda_guest_attention_rows() TO service_role;

SELECT cron.unschedule('agenda-guest-attention')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'agenda-guest-attention');

SELECT cron.schedule(
  'agenda-guest-attention',
  '5 12 * * *',
  $cron$SELECT public._agenda_guest_attention_cron();$cron$
);

-- ── (3) certificado do convidado a partir do bloco ───────────────────────────
CREATE OR REPLACE FUNCTION public.issue_agenda_guest_certificate(p_block_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_person uuid;
  v_b             record;
  v_email         text;
BEGIN
  SELECT p.id INTO v_caller_person FROM public.persons p WHERE p.auth_id = auth.uid();
  IF v_caller_person IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT b.id, b.status, b.external_guest, b.guest_name, b.guest_language, b.event_id, b.organization_id,
         (e.date + COALESCE(e.time_start, '00:00'::time)) AT TIME ZONE COALESCE(e.timezone, 'America/Sao_Paulo') AS start_at
    INTO v_b
  FROM public.event_agenda_blocks b
  JOIN public.events e ON e.id = b.event_id
  WHERE b.id = p_block_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'block_not_found');
  END IF;

  IF NOT (public.can(v_caller_person, 'manage_event', 'organization', v_b.organization_id)
          OR public.can(v_caller_person, 'manage_platform', 'organization', v_b.organization_id)) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_event or manage_platform at organization scope');
  END IF;

  IF NOT v_b.external_guest OR v_b.status <> 'confirmed' THEN
    RETURN jsonb_build_object('error', 'block_not_confirmed_external_guest');
  END IF;
  IF v_b.start_at > now() THEN
    RETURN jsonb_build_object('error', 'meeting_not_started');
  END IF;

  -- o e-mail DIGITADO para este bloco (vínculo), o mesmo do convite
  SELECT l.contact_email INTO v_email FROM public.person_external_links l
  WHERE l.purpose = 'agenda_guest' AND l.source_id = p_block_id
  ORDER BY l.updated_at DESC LIMIT 1;
  IF v_email IS NULL THEN
    RETURN jsonb_build_object('error', 'guest_email_missing');
  END IF;

  RETURN public.issue_event_guest_certificate(jsonb_build_object(
    'event_id', v_b.event_id,
    'guest_email', v_email,
    'guest_name', v_b.guest_name,
    'language', v_b.guest_language,
    'organization_id', v_b.organization_id,
    'consent_version', 'event-guest-agenda-viva-bloco'));
END;
$function$;

REVOKE ALL ON FUNCTION public.issue_agenda_guest_certificate(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.issue_agenda_guest_certificate(uuid) TO authenticated, service_role;

-- ── pós-condição ──────────────────────────────────────────────────────────────
DO $postcondition$
BEGIN
  IF public._delivery_mode_for('agenda_guest_attention') <> 'suppress'
     OR public._delivery_mode_for('agenda_block_confirmed') <> 'suppress'
     OR public._delivery_mode_for('tracker_pii_found') <> 'transactional_immediate'
     OR public._delivery_mode_for('volunteer_agreement_signed') <> 'suppress'
     OR public._delivery_mode_for('tipo_que_nao_existe') <> 'digest_weekly' THEN
    RAISE EXCEPTION '#2593 C3b: catálogo de entrega fora do esperado';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'agenda-guest-attention' AND schedule = '5 12 * * *' AND active) THEN
    RAISE EXCEPTION '#2593 C3b: o cron do aviso não ficou agendado';
  END IF;
  IF has_function_privilege('authenticated', 'public._agenda_guest_attention_cron()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public._agenda_guest_attention_rows()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.issue_agenda_guest_certificate(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '#2593 C3b: privilégio fora do esperado';
  END IF;
  -- service_role (a migration) não tem sessão: a RPC do certificado recusa sem gravar nada
  IF (public.issue_agenda_guest_certificate(gen_random_uuid())->>'error') IS DISTINCT FROM 'Not authenticated' THEN
    RAISE EXCEPTION '#2593 C3b: o certificado do bloco não recusou chamada sem sessão';
  END IF;
END
$postcondition$;
