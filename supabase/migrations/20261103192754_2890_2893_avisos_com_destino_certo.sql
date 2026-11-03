-- Onboarding, onda 0, PR-5 (#2890, #2893): dois avisos com destino errado.
--   1. respond_re_engagement: o aviso de resposta ao convite de retorno linkava /admin/members/re-engagement, rota que
--      nao existe. Passa a linkar a ficha de quem respondeu, e o INSERT passa a ler o modo do catalogo;
--   2. notify_offboard_cascade: os lideres a avisar do desligamento vinham de members.tribe_id (campo legado). Passam
--      a vir dos vinculos: lider ou co-lider ativo de cada iniciativa em que a pessoa tinha vinculo;
--   3. _delivery_mode_for cataloga re_engagement_accepted e re_engagement_declined com o modo que ja usavam.
--
-- Os corpos partem das capturas mais novas: respond_re_engagement de 20260686000000, notify_offboard_cascade de
-- 20260513070000 e _delivery_mode_for de 20261103151033, com so estas mudancas; o md5 do corpo vivo e conferido
-- contra elas antes do apply. CREATE OR REPLACE mantem a ACL e o gatilho trg_notify_offboard_cascade.
--
-- Ordem no desligamento, lida nas duas assinaturas vigentes de admin_offboard_member (20260803233204 e
-- 20260805000375): o UPDATE de members, que dispara o gatilho, vem antes do UPDATE que encerra os vinculos. A clausula
-- revoked_at >= now() cobre a ordem inversa, se um caminho futuro a usar.
--
-- ROLLBACK: reaplicar os tres corpos das capturas citadas acima.

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
    -- #740 Wave 3c-i (B8): agreement rejected / reissued: member must re-sign, deliver immediately
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
    -- #2782 (24/10/2026): pedido de capítulo ou de organização pelo formulário da home, para quem gere a plataforma
    -- (manage_platform). Imediato de propósito: a home promete resposta em até 5 dias úteis, e no ELSE (digest_weekly)
    -- o aviso chegaria no sábado. O aviso não leva nome, e-mail, telefone nem a mensagem de quem pediu.
    WHEN 'partner_lead_received'          THEN 'transactional_immediate'
    -- #2393 fatia 3 (02/11/2026): candidaturas novas na vaga do líder. No sino na hora e no resumo de sábado,
    -- sem e-mail imediato: o líder age em dias (ADR-0134 §8), e o 1º lote de uma vaga não vira rajada.
    -- Explícito, e não deixado no ELSE, para o modo não mudar se o ELSE mudar. Sem nome de candidato.
    WHEN 'selection_opening_new_applications' THEN 'digest_weekly'
    -- Onboarding, onda 0, PR-2 (#2891, 03/11/2026): os avisos do pedido de tribo e o de boas-vindas ao vinculo
    -- gravavam 'transactional_immediate' literal no proprio INSERT e caiam no ELSE (digest_weekly) para quem perguntasse
    -- ao catalogo. Catalogados com o modo que ja usam. tribe_request_expired e novo (#2888): quem pediu sabe na hora que
    -- o pedido passou do prazo e que isso nao e uma recusa.
    WHEN 'tribe_request'                  THEN 'transactional_immediate'
    WHEN 'tribe_request_reviewed'         THEN 'transactional_immediate'
    WHEN 'tribe_request_nudge'            THEN 'transactional_immediate'
    WHEN 'tribe_request_expired_gp'       THEN 'transactional_immediate'
    WHEN 'tribe_request_expired'          THEN 'transactional_immediate'
    WHEN 'engagement_welcome'             THEN 'transactional_immediate'
    -- Onda 0 PR-5 (#2890, 03/11/2026): a resposta ao convite de retorno, para quem gere a plataforma. O INSERT nao
    -- declarava o modo e caia no default da coluna (digest_weekly), que o resumo semanal renderiza no balde
    -- other_notifications (#2286). Catalogados com o mesmo modo, para nao depender do default nem do ELSE.
    WHEN 're_engagement_accepted'         THEN 'digest_weekly'
    WHEN 're_engagement_declined'         THEN 'digest_weekly'
    ELSE 'digest_weekly'
  END;
$function$;

CREATE OR REPLACE FUNCTION public.respond_re_engagement(p_pipeline_id uuid, p_response text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_pipeline record;
BEGIN
  IF p_response NOT IN ('accepted','declined') THEN
    RETURN jsonb_build_object('error','Invalid response: must be accepted or declined');
  END IF;

  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;

  SELECT * INTO v_pipeline FROM public.re_engagement_pipeline WHERE id = p_pipeline_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Pipeline entry not found'); END IF;

  -- Self-action only: caller must be the pipeline subject
  IF v_pipeline.member_id <> v_caller.id THEN
    RETURN jsonb_build_object('error','Unauthorized: only the invited member can respond');
  END IF;

  IF v_pipeline.state <> 'invited' THEN
    RETURN jsonb_build_object('error','Cannot respond from state: ' || v_pipeline.state::text);
  END IF;

  UPDATE public.re_engagement_pipeline SET
    state = p_response::public.re_engagement_state,
    responded_at = now(),
    response = p_response,
    response_note = p_note
  WHERE id = p_pipeline_id;

  -- Notify managers about response
  -- Onda 0 PR-5 (#2890): o link ia para /admin/members/re-engagement, rota que nao existe (caia em [id].astro com o
  -- id "re-engagement"). Passa a ser a ficha de quem respondeu. O modo de entrega passa a vir do catalogo, com o
  -- mesmo digest_weekly que o default da coluna dava.
  INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
  SELECT mgr.id,
         CASE WHEN p_response = 'accepted' THEN 're_engagement_accepted' ELSE 're_engagement_declined' END,
         COALESCE(v_caller.name,'Alumni') || ' ' ||
           CASE WHEN p_response = 'accepted' THEN 'aceitou o convite de retorno' ELSE 'declinou o convite de retorno' END,
         COALESCE(p_note, NULL),
         '/admin/members/' || v_caller.id::text,
         're_engagement_pipeline', p_pipeline_id,
         public._delivery_mode_for(CASE WHEN p_response = 'accepted' THEN 're_engagement_accepted' ELSE 're_engagement_declined' END)
  FROM public.members mgr
  WHERE mgr.is_active = true AND mgr.operational_role IN ('manager','deputy_manager');

  -- Audit log
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id, 're_engagement.' || p_response, 're_engagement_pipeline', p_pipeline_id,
    jsonb_build_object('response', p_response, 'cycle_code', v_pipeline.cycle_code),
    jsonb_strip_nulls(jsonb_build_object('note_excerpt', LEFT(p_note, 200)))
  );

  RETURN jsonb_build_object('success', true, 'pipeline_id', p_pipeline_id, 'response', p_response);
END $function$
;

CREATE OR REPLACE FUNCTION public.notify_offboard_cascade()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor         uuid;
  v_title         text;
  v_body          text;
  v_link          text;
  v_stakeholders  uuid[];
BEGIN
  IF NEW.member_status NOT IN ('alumni','observer','inactive') THEN
    RETURN NEW;
  END IF;

  v_actor := NEW.offboarded_by;

  v_title := CASE NEW.member_status
    WHEN 'alumni'   THEN COALESCE(NEW.name,'Membro') || ' saiu da equipe (alumni)'
    WHEN 'observer' THEN COALESCE(NEW.name,'Membro') || ' passou a observador(a)'
    WHEN 'inactive' THEN COALESCE(NEW.name,'Membro') || ' foi desativado(a)'
  END;
  v_body := NULLIF(TRIM(COALESCE(NEW.status_change_reason,'')), '');
  v_link := '/admin/members/' || NEW.id::text;

  SELECT array_agg(DISTINCT m.id)
  INTO v_stakeholders
  FROM public.members m
  WHERE m.is_active = true
    AND m.id <> NEW.id
    AND m.id IS DISTINCT FROM v_actor
    AND (
      m.operational_role IN ('manager','deputy_manager')
      -- Onda 0 PR-5 (#2893): o lider vinha do campo legado members.tribe_id, e quem esta numa iniciativa so por
      -- vinculo ficava sem aviso. Passa a vir dos vinculos (ADR-0080): lider ou co-lider ativo (kind volunteer) de
      -- qualquer iniciativa em que a pessoa tinha vinculo ate esta transacao. "Ate esta transacao" porque um caminho
      -- que encerre os vinculos antes de mudar o status, na mesma transacao, nao pode apagar os lideres a avisar;
      -- revoked_at >= now() pega so o que foi encerrado nesta transacao.
      OR EXISTS (
        SELECT 1
        FROM public.engagements le
        JOIN public.engagements pe ON pe.initiative_id = le.initiative_id
        WHERE le.person_id = m.person_id
          AND le.kind = 'volunteer'
          AND le.role IN ('leader','co_leader')
          AND le.status = 'active'
          AND pe.person_id = NEW.person_id
          AND pe.initiative_id IS NOT NULL
          AND (pe.status = 'active' OR pe.revoked_at >= now())
      )
    );

  IF v_stakeholders IS NOT NULL AND cardinality(v_stakeholders) > 0 THEN
    INSERT INTO public.notifications
      (recipient_id, type, title, body, link, source_type, source_id, actor_id, delivery_mode)
    SELECT rid, 'member_offboarded', v_title, v_body, v_link, 'member', NEW.id, v_actor,
           public._delivery_mode_for('member_offboarded')
    FROM unnest(v_stakeholders) AS rid;
  END IF;

  PERFORM public.detect_orphan_assignees_from_offboards(NEW.id);

  RETURN NEW;
END;
$function$;

NOTIFY pgrst, 'reload schema';
