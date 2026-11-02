-- #2393, fatia 3 (ADR-0134, decisão do GP em 02/11/2026): aviso ao líder da vaga quando chega candidatura.
--
-- Quem escreve é um cron de hora em hora, não um trigger nem o worker:
--   - o worker grava candidatura linha a linha; um trigger daria N avisos no 1º lote de uma vaga, e uma falha
--     nele derrubaria a importação;
--   - o worker cobre só a importação; o cron lê a tabela e cobre todo escritor.
-- O cron agrupa por vaga e manda 1 aviso por (líder, vaga), com a contagem.
--
-- selection_applications.opening_alert_processed_at: quando o cron JÁ TRATOU a linha, com aviso ou sem. Ele
-- carimba toda linha que pegou na rodada, então a que chega durante a rodada fica para a próxima, e nenhuma é
-- tratada duas vezes. O estoque de hoje nasce carimbado pelo default now() da coluna, avaliado uma vez no
-- ALTER (Postgres 11+, sem reescrever a tabela e sem disparar trigger); o DROP DEFAULT logo depois faz a
-- candidatura nova nascer NULL. Sem isso, a 1ª rodada avisaria os líderes das vagas ativas com o estoque.
--
-- Conta como nova só candidatura de vaga ligada a uma iniciativa, não anonimizada, em 'submitted' ou
-- 'screening'. A que entra já aprovada, recusada ou desistente (baldes qualified e rejected do VEP) é
-- carimbada sem aviso. Refresh entre ciclos não cria linha.
--
-- Destinatários, calculados na hora pelo MESMO portão da leitura por vaga: membro ativo com
-- can_by_member(view_opening_applications, initiative da vaga) e sem conflito de interesse no ciclo da vaga.
-- Nunca lista fixa, nunca _v4_leader_member_ids_by_initiative (que não exige vínculo autoritativo).
-- rls_can_see_initiative depende de auth.uid() e não roda no cron; numa iniciativa confidencial o líder é
-- engajado, então o resultado é o mesmo.
--
-- O aviso não leva nome, e-mail nem dado de candidato (ADR-0134 §6): só a contagem e a vaga. Tipo
-- selection_opening_new_applications, digest_weekly (sino na hora, resumo de sábado), respeita as
-- preferências do membro e o suppress_all (não é aviso ao candidato).
-- O link aponta para /minhas-vagas, a tela da fatia 3: esta migration entra depois da tela no ar.

ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS opening_alert_processed_at timestamptz DEFAULT now();

ALTER TABLE public.selection_applications
  ALTER COLUMN opening_alert_processed_at DROP DEFAULT;

COMMENT ON COLUMN public.selection_applications.opening_alert_processed_at IS
  '#2393 (ADR-0134): quando o cron do aviso ao líder da vaga tratou a candidatura, com aviso ou sem. NULL = ainda não tratada. O estoque anterior à coluna nasceu carimbado.';

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
    ELSE 'digest_weekly'
  END;
$function$;

CREATE OR REPLACE FUNCTION public._selection_opening_new_applications_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_ids uuid[];
  v_grupo record;
  v_dest record;
  v_titulo text;
  v_corpo text;
  v_vagas int := 0;
  v_destinatarios int := 0;
  v_tratadas int := 0;
BEGIN
  -- O retrato desta rodada: só estas linhas são carimbadas no fim.
  SELECT array_agg(sa.id) INTO v_ids
  FROM public.selection_applications sa
  WHERE sa.opening_alert_processed_at IS NULL;

  IF v_ids IS NULL THEN
    RETURN jsonb_build_object('success', true, 'vagas', 0, 'destinatarios', 0, 'tratadas', 0);
  END IF;

  FOR v_grupo IN
    SELECT vo.id AS vaga_id, vo.opportunity_id, vo.title, vo.initiative_id, vo.cycle_id, count(*)::int AS n
    FROM public.selection_applications sa
    JOIN public.vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id
    WHERE sa.id = ANY (v_ids)
      AND vo.initiative_id IS NOT NULL
      AND sa.anonymized_at IS NULL
      AND sa.status IN ('submitted', 'screening')
    GROUP BY vo.id, vo.opportunity_id, vo.title, vo.initiative_id, vo.cycle_id
  LOOP
    v_vagas := v_vagas + 1;
    v_titulo := CASE WHEN v_grupo.n = 1 THEN '1 candidatura nova na sua vaga'
                     ELSE v_grupo.n || ' candidaturas novas na sua vaga' END;
    v_corpo := 'Vaga ' || v_grupo.opportunity_id || ': ' || COALESCE(v_grupo.title, '') || '. A lista está em Minhas vagas.';

    FOR v_dest IN
      SELECT m.id
      FROM public.members m
      WHERE m.is_active = true
        AND public.can_by_member(m.id, 'view_opening_applications', 'initiative', v_grupo.initiative_id)
        AND NOT public.selection_coi_recused(m.id, v_grupo.cycle_id)
    LOOP
      PERFORM public.create_notification(
        v_dest.id, 'selection_opening_new_applications', v_titulo, v_corpo,
        '/minhas-vagas?vaga=' || v_grupo.opportunity_id, 'vep_opportunity', v_grupo.vaga_id
      );
      v_destinatarios := v_destinatarios + 1;
    END LOOP;
  END LOOP;

  UPDATE public.selection_applications
  SET opening_alert_processed_at = now()
  WHERE id = ANY (v_ids)
    AND opening_alert_processed_at IS NULL;
  GET DIAGNOSTICS v_tratadas = ROW_COUNT;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'selection.opening_new_applications_cron_run', 'system', NULL,
    jsonb_build_object('vagas', v_vagas, 'destinatarios', v_destinatarios, 'tratadas', v_tratadas),
    jsonb_build_object('run_at', now(), 'source', '_selection_opening_new_applications_cron')
  );

  RETURN jsonb_build_object('success', true, 'vagas', v_vagas, 'destinatarios', v_destinatarios, 'tratadas', v_tratadas);
END;
$function$;

REVOKE ALL ON FUNCTION public._selection_opening_new_applications_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._selection_opening_new_applications_cron() TO service_role;

COMMENT ON FUNCTION public._selection_opening_new_applications_cron() IS
  '#2393 (ADR-0134): de hora em hora, 1 aviso por (líder, vaga) com a contagem de candidaturas novas, sem dado de candidato. Destinatários pelo portão da leitura por vaga.';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'selection-opening-new-applications-hourly') THEN
    PERFORM cron.unschedule('selection-opening-new-applications-hourly');
  END IF;
END $$;

SELECT cron.schedule(
  'selection-opening-new-applications-hourly',
  '23 * * * *',
  $cron$ SELECT public._selection_opening_new_applications_cron() $cron$
);

NOTIFY pgrst, 'reload schema';
