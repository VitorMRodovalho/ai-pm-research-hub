-- =====================================================================================
-- #2621 item 0 -- toda decisao da curadoria avisa autor, coautores e lideranca da iniciativa
--
-- MEDIDO em 2026-10-09: o primeiro parecer real registrado na plataforma (uma devolucao para
-- ajuste, rodada 1) nao gerou notificacao para ninguem. Causa no codigo:
--   - submit_curation_review nao chama create_notification em nenhum ramo; na devolucao e na
--     rejeicao so acrescenta o parecer a descricao do card e volta curation_status para 'draft';
--   - notify_on_curation_status_change exclui a volta para 'draft' por construcao;
--   - a aprovacao chegava, mas como card_moved (digest_weekly) com o codigo cru "published".
--
-- O QUE MUDA
--   1. notify_on_curation_status_change: o bloco do aviso a tribo (#2496), que so cobria a
--      ENTRADA em curadoria, passa a cobrir toda SAIDA de curation_pending, para a mesma
--      audiencia (participantes do card UNION lideranca ativa da iniciativa, so pessoas
--      ativas, uma linha por pessoa). Um tipo por decisao:
--        curation_pending -> draft, card arquivado  => curation_decision_rejected (com o motivo)
--        curation_pending -> draft                  => curation_decision_returned (com o parecer)
--        curation_pending -> published              => curation_decision_approved
--      O parecer vem do curation_review_log gravado NA MESMA TRANSACAO (completed_at = now()),
--      cortado em 400 chars. Saida de curation_pending SEM registro de decisao nesta transacao
--      (ex.: update_board_item com curation_status em p_fields) nao e decisao da curadoria: nao
--      gera aviso de decisao; a saida manual para 'published' segue no card_moved generico.
--      O bloco generico card_moved deixa de mandar o "published" cru da aprovacao registrada.
--   2. _delivery_mode_for: os 3 tipos novos como transactional_immediate (fora do catalogo
--      cairiam no digest semanal). Catalogo ADR-0022 atualizado no mesmo commit.
--
-- Os dois corpos foram montados sobre o CORPO VIVO: md5 normalizado do vivo igual ao da captura
-- mais nova (notify_on_curation_status_change: 20260927153519; _delivery_mode_for:
-- 20261008140102), conferido em 2026-10-09 via _audit_list_public_function_bodies().
-- CREATE OR REPLACE preserva os grants; nenhuma assinatura muda; o gatilho
-- trg_notify_curation_status (AFTER UPDATE OF curation_status ON board_items) nao muda.
-- ROLLBACK: reaplicar as capturas 20260927153519 (gatilho) e 20261008140102 (helper).
-- =====================================================================================

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
  v_kind          text;
  v_type          text;
  v_titulo        text;
  v_corpo         text;
  v_rodada        integer;
  v_parecer       text;
BEGIN
  -- #2496 + #2621: classe da transicao, calculada antes dos blocos porque o aviso generico
  -- precisa saber se a saida de curation_pending e uma aprovacao registrada.
  -- A classificacao segue o que submit_curation_review grava: devolucao e rejeicao voltam para
  -- 'draft', e so a rejeicao arquiva o card; a aprovacao passa por publish_board_item_from_curation.
  v_kind := CASE
    WHEN NEW.curation_status = 'curation_pending'
         AND OLD.curation_status IS DISTINCT FROM 'curation_pending'          THEN 'entrada'
    WHEN OLD.curation_status = 'curation_pending'
         AND NEW.curation_status = 'published'                                THEN 'aprovado'
    WHEN OLD.curation_status = 'curation_pending'
         AND NEW.curation_status = 'draft' AND NEW.status = 'archived'        THEN 'rejeitado'
    WHEN OLD.curation_status = 'curation_pending'
         AND NEW.curation_status = 'draft'                                    THEN 'devolvido'
  END;

  -- O parecer vem do registro que submit_curation_review gravou NESTA transacao: completed_at e o
  -- now() da transacao do RPC, e este gatilho roda dentro dela, entao a igualdade e exata. Sem esse
  -- registro a saida nao foi decisao da curadoria (caminho manual) e nao vira aviso de decisao.
  -- Se um dia este aviso sair da transacao (fila, job), o filtro deixa de achar a linha.
  IF v_kind IN ('aprovado', 'rejeitado', 'devolvido') THEN
    SELECT crl.review_round,
           nullif(btrim(regexp_replace(crl.feedback_notes, '\s+', ' ', 'g')), '')
      INTO v_rodada, v_parecer
    FROM curation_review_log crl
    WHERE crl.board_item_id = NEW.id
      AND crl.completed_at = now()
      AND crl.decision = CASE v_kind
                           WHEN 'aprovado'  THEN 'approved'
                           WHEN 'rejeitado' THEN 'rejected'
                           ELSE 'returned_for_revision'
                         END
    ORDER BY crl.completed_at DESC, crl.id
    LIMIT 1;

    IF NOT FOUND THEN
      v_kind := NULL;
    END IF;

    -- Cortado em 400 caracteres: o texto inteiro segue no card.
    IF length(v_parecer) > 400 THEN
      v_parecer := left(v_parecer, 400) || '…';
    END IF;
    IF v_parecer IS NOT NULL AND v_parecer !~ '[.!?…]$' THEN
      v_parecer := v_parecer || '.';
    END IF;
  END IF;

  -- Notify all assignees when curation_status changes.
  -- #2496: a ENTRADA em curadoria tem aviso proprio (bloco no fim), e cada pessoa recebe uma vez
  -- mesmo com dois papeis no card (autor e colaborador geravam duas linhas).
  -- #2621: a APROVACAO registrada (v_kind = 'aprovado') tem aviso proprio no bloco do fim; aqui
  -- ela so mandava o codigo cru do status ("agora esta em: published").
  IF NEW.curation_status IS DISTINCT FROM OLD.curation_status
    AND NEW.curation_status IS NOT NULL
    AND NEW.curation_status != 'draft'
    AND v_kind IS DISTINCT FROM 'aprovado'
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

  -- #2496: aviso a TRIBO na ENTRADA em curadoria. #2621: e em toda DECISAO que tira o item da
  -- curadoria, para a mesma audiencia: devolvido para ajuste (com o parecer), rejeitado (com o
  -- motivo) e aprovado. Antes, devolucao e rejeicao voltavam para 'draft', que o bloco generico
  -- exclui por construcao, e o primeiro parecer real da plataforma passou mudo.
  -- Vai uma vez para cada pessoa ativa entre os participantes do card e a lideranca ativa da
  -- iniciativa do board, com link para o board da tribo (ou para a pagina da iniciativa).
  IF v_kind IS NOT NULL THEN
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

    v_type := CASE v_kind
      WHEN 'entrada'   THEN 'curation_submitted_to_tribe'
      WHEN 'devolvido' THEN 'curation_decision_returned'
      WHEN 'rejeitado' THEN 'curation_decision_rejected'
      WHEN 'aprovado'  THEN 'curation_decision_approved'
    END;

    v_titulo := CASE v_kind
      WHEN 'entrada'   THEN 'Seu trabalho entrou em curadoria'
      WHEN 'devolvido' THEN 'A curadoria pediu ajustes no seu trabalho'
      WHEN 'rejeitado' THEN 'A curadoria não aprovou seu trabalho'
      WHEN 'aprovado'  THEN 'Seu trabalho foi aprovado pela curadoria'
    END;

    v_corpo := CASE v_kind
      WHEN 'entrada' THEN
        '"' || NEW.title || '" entrou na curadoria.'
          || CASE WHEN v_prazo IS NOT NULL THEN ' Prazo do parecer: ' || v_prazo || '.' ELSE '' END
          || ' O andamento aparece no card, na etapa Curadoria.'
      WHEN 'devolvido' THEN
        '"' || NEW.title || '" voltou da curadoria com pedido de ajuste'
          || CASE WHEN v_rodada IS NOT NULL THEN ' (rodada ' || v_rodada || ')' ELSE '' END || '.'
          || CASE WHEN v_parecer IS NOT NULL THEN ' Parecer: ' || v_parecer ELSE '' END
          || ' O parecer completo está no card. Depois de ajustar, envie de novo para a curadoria pelo card.'
      WHEN 'rejeitado' THEN
        '"' || NEW.title || '" não foi aprovado pela curadoria'
          || CASE WHEN v_rodada IS NOT NULL THEN ' (rodada ' || v_rodada || ')' ELSE '' END
          || ' e foi arquivado.'
          || CASE WHEN v_parecer IS NOT NULL THEN ' Motivo: ' || v_parecer ELSE '' END
          || ' O parecer completo está no card.'
      WHEN 'aprovado' THEN
        '"' || NEW.title || '" foi aprovado pela curadoria e entrou no quadro de publicações.'
          || ' O andamento aparece no card.'
    END;

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
        v_type,
        v_titulo,
        v_corpo,
        v_link,
        'board_item',
        NEW.id
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$function$;

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
    ELSE 'digest_weekly'
  END;
$function$;
