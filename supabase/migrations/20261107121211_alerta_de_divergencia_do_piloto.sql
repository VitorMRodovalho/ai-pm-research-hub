-- #2393 (emenda de 06/11/2026 à ADR-0134 §4): o alerta de divergência da candidatura piloto chega a quem decide.
--
-- A emenda trocou controle por auditoria: o líder da vaga avalia a objetiva com 1 pessoa de fora, e uma divergência
-- grande entre as duas notas é o sinal. O detector por candidatura (#2542) já gravava o alerta high_variance, mas
-- nenhuma tela nem aviso o lia. Esta migration:
-- 1. _trg_evaluation_divergence: na candidatura piloto, o alerta NOVO (não havia um aberto daquela parte) avisa a
--    gestão (quem tem manage_platform) na hora, sem nome de candidato, com o link do painel;
-- 2. _delivery_mode_for: o tipo selection_pilot_divergence é imediato, explícito e registrado no catálogo da ADR-0022;
-- 3. get_selection_dashboard: cada linha piloto leva divergence_types, as partes com alerta aberto, para o selo do
--    painel. Só a gestão vê linha piloto; para os demais, e na avaliação geral, sai NULL.
-- O resto das três funções fica igual, byte a byte (gerado de 20261002180015_2542_detector_de_divergencia_por_candidatura.sql, 20261104205503_avaliador_do_piloto.sql e 20261102202621_marcador_de_piloto_fila_e_avaliacao.sql).

-- ── 1. O detector avisa a gestão ──
CREATE OR REPLACE FUNCTION public._trg_evaluation_divergence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  c_limiar constant numeric := 0.30;
  v_n int;
  v_mean numeric;
  v_min numeric;
  v_max numeric;
  v_ids uuid[];
  v_cycle uuid;
  v_ja_havia boolean;
  v_vaga text;
BEGIN
  IF NEW.submitted_at IS NULL OR NEW.weighted_subtotal IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT count(*), avg(e.weighted_subtotal), min(e.weighted_subtotal), max(e.weighted_subtotal),
         array_agg(e.evaluator_id ORDER BY e.evaluator_id)
    INTO v_n, v_mean, v_min, v_max, v_ids
    FROM public.selection_evaluations e
   WHERE e.application_id = NEW.application_id
     AND e.evaluation_type = NEW.evaluation_type
     AND e.submitted_at IS NOT NULL
     AND e.weighted_subtotal IS NOT NULL;

  SELECT a.cycle_id INTO v_cycle FROM public.selection_applications a WHERE a.id = NEW.application_id;

  -- #2393 (emenda de 06/11/2026 à ADR-0134 §4): a candidatura piloto avisa a gestão uma vez por ocorrência. Lê se já
  -- havia alerta aberto ANTES de o trecho abaixo apagar e regravar.
  v_ja_havia := EXISTS (SELECT 1 FROM public.selection_evaluation_anomalies an
                         WHERE an.application_id = NEW.application_id
                           AND an.alert_type = 'high_variance'
                           AND an.resolved_at IS NULL
                           AND an.payload->>'evaluation_type' = NEW.evaluation_type);

  DELETE FROM public.selection_evaluation_anomalies an
   WHERE an.application_id = NEW.application_id
     AND an.alert_type = 'high_variance'
     AND an.resolved_at IS NULL
     AND an.payload->>'evaluation_type' = NEW.evaluation_type;

  IF v_n >= 2 AND v_mean > 0 AND (v_max - v_min) > c_limiar * v_mean THEN
    INSERT INTO public.selection_evaluation_anomalies (application_id, cycle_id, alert_type, payload)
    SELECT NEW.application_id, v_cycle, 'high_variance',
           jsonb_build_object(
             'evaluation_type', NEW.evaluation_type,
             'evaluator_id', ev,
             'evaluator_ids', to_jsonb(v_ids),
             'evaluator_count', v_n,
             'mean', round(v_mean, 2),
             'min', v_min,
             'max', v_max,
             'diff', v_max - v_min,
             'rel_diff', round((v_max - v_min) / v_mean, 4),
             'threshold_rel', c_limiar,
             'rule', 'maior - menor > 30% da media, por tipo de avaliacao (#2542, ADR-0134 B6)')
      FROM unnest(v_ids) AS ev;

    -- O farol da emenda: sem nome de candidato, à gestão (manage_platform), que é quem lê as notas do piloto.
    IF NOT v_ja_havia AND NOT public._na_avaliacao_geral(NEW.application_id) THEN
      SELECT a.vep_opportunity_id INTO v_vaga FROM public.selection_applications a WHERE a.id = NEW.application_id;
      PERFORM public.create_notification(
        m.id, 'selection_pilot_divergence',
        'Divergência na candidatura ' || left(NEW.application_id::text, 8),
        'Vaga ' || COALESCE(v_vaga, '?') || ', parte '
          || CASE NEW.evaluation_type WHEN 'objective' THEN 'objetiva' WHEN 'video' THEN 'do vídeo' ELSE NEW.evaluation_type END
          || ': a maior nota passa a menor em mais de 30% da média. Revise o caso antes de decidir.',
        '/admin/selection', 'selection_application', NEW.application_id
      )
      FROM public.members m
      WHERE m.is_active AND m.auth_id IS NOT NULL AND public.can_by_member(m.id, 'manage_platform');
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

-- ── 2. O modo de entrega do aviso ──
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
    WHEN 'selection_evaluator_assigned'       THEN 'transactional_immediate'  -- #2393 M2
    WHEN 'selection_pilot_divergence'         THEN 'transactional_immediate'  -- #2393, emenda de 06/11/2026 à ADR-0134 §4
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

-- ── 3. O painel leva as partes com divergência aberta ──
CREATE OR REPLACE FUNCTION public.get_selection_dashboard(p_cycle_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_result jsonb;
  v_stats_a jsonb;
  v_stats_b jsonb;
  v_via_committee boolean := false;   -- #1591
  v_ve_piloto boolean := false;       -- #2393 fatia 3
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  -- #1591: o comite de selecao e autoridade de LEITURA desta tela. Ate aqui a porta so
  -- falava `view_internal_analytics`, que um avaliador nao tem: o dominio sabia quem era do
  -- comite e a RPC nao. O ciclo EXATO e conferido logo abaixo, depois de resolvido.
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    v_via_committee := public.is_selection_committee_member(v_caller_id, NULL);
    IF NOT v_via_committee THEN
      RETURN jsonb_build_object('error', 'Unauthorized');
    END IF;
  END IF;
  IF p_cycle_code IS NOT NULL THEN
    SELECT id INTO v_cycle_id FROM public.selection_cycles WHERE cycle_code = p_cycle_code;
  ELSE
    -- #1446: prefer the current OPEN cycle; only fall back to newest created_at
    -- when no cycle is open. Fixes the historical-reimport shadowing bug.
    SELECT id INTO v_cycle_id FROM public.selection_cycles ORDER BY (status = 'open') DESC, created_at DESC LIMIT 1;
  END IF;
  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No cycle found', 'cycle', null, 'applications', '[]'::jsonb, 'stats', jsonb_build_object('total', 0));
  END IF;

  -- #1591: entrou pelo comite -> so pode ler o ciclo DELE. Sem isto, ser do comite do ciclo
  -- vivo abriria o PII de candidato de todos os ciclos passados.
  IF v_via_committee AND NOT public.is_selection_committee_member(v_caller_id, v_cycle_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- ADR-0109 PR-2 COI recusal: an active candidate in this cycle is recused from this selection surface.
  IF public.selection_coi_recused(v_caller_id, v_cycle_id) THEN
    RETURN jsonb_build_object('error', 'recused_conflict_of_interest',
      'detail', 'Você é candidato(a) neste ciclo — as visões de seleção estão impedidas por conflito de interesse (ADR-0109).');
  END IF;

  -- #2393 fatia 3: candidatura de vaga piloto da linha (vep_opportunities.evaluation_track) fica fora
  -- da avaliação geral. Nesta tela só a gestão a vê, marcada pela trilha. As contagens do topo seguem
  -- sendo do ciclo inteiro: são agregadas e não identificam ninguém.
  v_ve_piloto := public.can_by_member(v_caller_id, 'manage_platform');

  v_stats_a := jsonb_build_object(
    'total', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id),
    'approved', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('approved', 'converted')),
    'rejected', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('rejected', 'objective_cutoff')),
    'pending', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('submitted', 'screening', 'objective_eval', 'interview_pending', 'interview_scheduled', 'interview_done', 'final_eval')),
    'cancelled', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('cancelled', 'withdrawn')),
    'waitlist', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status = 'waitlist'),
    'leader_ranked', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND rank_leader IS NOT NULL),
    'researcher_ranked', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND rank_researcher IS NOT NULL),
    'ai_analysis_done_count', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND consent_ai_analysis_at IS NOT NULL AND ai_analysis IS NOT NULL),
    'consent_ai_pending', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND consent_ai_analysis_at IS NULL),
    'consent_ai_consented', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND consent_ai_analysis_at IS NOT NULL AND consent_ai_analysis_revoked_at IS NULL),
    'consent_ai_revoked', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND consent_ai_analysis_revoked_at IS NOT NULL)
  );

  v_stats_b := jsonb_build_object(
    'line_pilot_total', CASE WHEN v_ve_piloto THEN (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND NOT public._na_avaliacao_geral(id)) END,  -- #2393 fatia 3
    'with_peer_evals_2plus', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND (SELECT count(DISTINCT e.evaluator_id) FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluation_type = 'objective' AND e.submitted_at IS NOT NULL) >= 2),
    'with_interview_scheduled', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id AND si.status IN ('scheduled','completed','rescheduled'))),
    'with_interview_today', (
      SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id
        AND EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id
          AND si.status = 'scheduled'
          AND (si.scheduled_at AT TIME ZONE 'America/Sao_Paulo')::date = (now() AT TIME ZONE 'America/Sao_Paulo')::date)
    ),
    'with_video_uploaded', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.pmi_video_screenings v WHERE v.application_id = a.id AND v.status IN ('uploaded','transcribing','transcribed'))),
    'with_video_opted_out', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.pmi_video_screenings v WHERE v.application_id = a.id) AND NOT EXISTS (SELECT 1 FROM public.pmi_video_screenings v WHERE v.application_id = a.id AND v.status IN ('uploaded','transcribing','transcribed'))),
    'with_pmi_member_active', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND pmi_id IS NOT NULL AND pmi_id <> '' AND service_latest_end_date >= CURRENT_DATE),
    'with_chapter_canonical', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND service_history_chapters IS NOT NULL AND service_history_chapters <> '' AND service_history_chapters <> 'PMI Global'),
    'with_re_applicants', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND COALESCE(application_count, 1) > 1),
    'with_briefing_generated', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND last_briefing_at IS NOT NULL),
    'shadow_vep_count', (
      SELECT count(*) FROM public.selection_applications a
      WHERE a.cycle_id = v_cycle_id
        AND a.status IN ('approved', 'converted', 'cancelled', 'rejected', 'withdrawn')
        -- #2393: a mesma regra do is_shadow_vep da linha. Uma funcao, uma definicao de sombra.
        AND NOT EXISTS (
          SELECT 1 FROM public.vep_opportunities o
          WHERE o.opportunity_id = a.vep_opportunity_id
            AND o.initiative_id IS NOT NULL
        )
        AND EXISTS (
          SELECT 1 FROM public.members m
          WHERE m.is_active = true
            AND lower(m.email) = lower(a.email)
            AND m.created_at < a.created_at
        )
    ),
    'my_evals_submitted', (SELECT count(*) FROM public.selection_evaluations e JOIN public.selection_applications a ON a.id = e.application_id WHERE a.cycle_id = v_cycle_id AND e.evaluator_id = v_caller_id AND e.submitted_at IS NOT NULL),
    'my_evals_pending', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.notifications n WHERE n.type = 'peer_review_requested' AND n.source_id = a.id AND n.recipient_id = v_caller_id) AND NOT EXISTS (SELECT 1 FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id))
  );

  SELECT jsonb_build_object(
    'cycle', (SELECT jsonb_build_object(
      'id', c.id, 'cycle_code', c.cycle_code, 'title', c.title, 'status', c.status,
      'interview_booking_url', c.interview_booking_url,
      'interview_questions', COALESCE(c.interview_questions, '[]'::jsonb),
      'pert_cutoff', (SELECT jsonb_build_object(
        'target_score', MAX(pert_target_score),
        'band_lower', MAX(pert_band_lower),
        'band_upper', MAX(pert_band_upper),
        'cohort_n', MAX(pert_cohort_n),
        'method', MAX(pert_cutoff_method),
        'calc_at', MAX(pert_calc_at),
        'apps_with_pert', COUNT(*) FILTER (WHERE pert_target_score IS NOT NULL),
        'apps_total', COUNT(*)
      ) FROM public.selection_applications WHERE cycle_id = v_cycle_id),
      'leader_extra_cutoff', (SELECT jsonb_build_object(
        'target_score', MAX(leader_extra_pert_target),
        'band_lower', MAX(leader_extra_pert_band_lower),
        'band_upper', MAX(leader_extra_pert_band_upper),
        'cohort_n', MAX(leader_extra_pert_cohort_n),
        'method', MAX(leader_extra_pert_cutoff_method),
        'calc_at', MAX(leader_extra_pert_calc_at),
        'apps_with_pert', COUNT(*) FILTER (WHERE leader_extra_pert_target IS NOT NULL),
        'apps_with_score', COUNT(*) FILTER (WHERE leader_extra_pert_score IS NOT NULL),
        'apps_total', COUNT(*)
      ) FROM public.selection_applications WHERE cycle_id = v_cycle_id),
      'final_score_cutoff_researcher', (SELECT jsonb_build_object(
        'target_score', MAX(final_score_pert_target),
        'band_lower', MAX(final_score_pert_band_lower),
        'band_upper', MAX(final_score_pert_band_upper),
        'cohort_n', MAX(final_score_pert_cohort_n),
        'method', MAX(final_score_pert_cutoff_method),
        'calc_at', MAX(final_score_pert_calc_at),
        'apps_with_pert', COUNT(*) FILTER (WHERE final_score_pert_target IS NOT NULL),
        'apps_with_score', COUNT(*) FILTER (WHERE final_score IS NOT NULL),
        'apps_total', COUNT(*)
      ) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND role_applied = 'researcher'),
      'final_score_cutoff_leader', (SELECT jsonb_build_object(
        'target_score', MAX(final_score_pert_target),
        'band_lower', MAX(final_score_pert_band_lower),
        'band_upper', MAX(final_score_pert_band_upper),
        'cohort_n', MAX(final_score_pert_cohort_n),
        'method', MAX(final_score_pert_cutoff_method),
        'calc_at', MAX(final_score_pert_calc_at),
        'apps_with_pert', COUNT(*) FILTER (WHERE final_score_pert_target IS NOT NULL),
        'apps_with_score', COUNT(*) FILTER (WHERE final_score IS NOT NULL),
        'apps_total', COUNT(*)
      ) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND role_applied = 'leader')
    ) FROM public.selection_cycles c WHERE c.id = v_cycle_id),
    'applications', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', a.id, 'applicant_name', a.applicant_name, 'email', a.email,
          'phone', a.phone,
          'role_applied', a.role_applied, 'chapter', a.chapter, 'status', a.status,
          'objective_score', a.objective_score_avg, 'final_score', a.final_score,
          'research_score', a.research_score, 'leader_score', a.leader_score,
          'rank_researcher', a.rank_researcher, 'rank_leader', a.rank_leader,
          'promotion_path', a.promotion_path, 'linked_application_id', a.linked_application_id,
          'rank_chapter', a.rank_chapter, 'rank_overall', a.rank_overall,
          'objective_rank', a.objective_rank,
          'linkedin_url', a.linkedin_url, 'resume_url', a.resume_url,
          'resume_storage_path', a.resume_storage_path,
          'resume_synced_at', a.resume_synced_at,
          'tags', a.tags, 'feedback', a.feedback,
          'motivation', a.motivation_letter, 'experience_years', a.seniority_years,
          'membership_status', a.membership_status, 'certifications', a.certifications,
          'is_returning_member', a.is_returning_member, 'application_date', a.application_date,
          'academic_background', a.academic_background, 'areas_of_interest', a.areas_of_interest,
          'availability_declared', a.availability_declared, 'non_pmi_experience', a.non_pmi_experience,
          'proposed_theme', a.proposed_theme, 'leadership_experience', a.leadership_experience,
          'created_at', a.created_at,
          -- #1587: `interview_status` era um cache que NUNCA assumia 'completed' -- nenhuma das
          -- 29 funcoes vivas que tocam selection_interviews o escrevia com esse valor. Medido em
          -- 14/08/2026: 106 das 170 candidaturas exibiam aqui um estado divergente do que as
          -- proprias linhas de entrevista provam (65 diziam 'none' e 32 'scheduled' para
          -- candidaturas com entrevista JA REALIZADA). A tela passa a ler o estado DERIVADO da
          -- view canonica; o cache continua no payload sob outra chave, para o ratchet poder
          -- medir a divergencia encolher sem depender de consulta manual.
          'interview_status', COALESCE(
            (SELECT v.interview_state FROM public.v_application_interview_state v
              WHERE v.application_id = a.id),
            a.interview_status
          ),
          'interview_status_cache', a.interview_status,
          'interview_reschedule_reason', a.interview_reschedule_reason,
          'interview_reschedule_requested_at', a.interview_reschedule_requested_at,
          'consent_ai_status', CASE
            WHEN a.consent_ai_analysis_revoked_at IS NOT NULL THEN 'revoked'
            WHEN a.consent_ai_analysis_at IS NOT NULL THEN 'consented'
            ELSE 'pending'
          END,
          'consent_ai_at', a.consent_ai_analysis_at,
          'consent_ai_revoked_at', a.consent_ai_analysis_revoked_at,
          'member_credly_url', (SELECT m.credly_url FROM public.members m WHERE lower(m.email) = lower(a.email) LIMIT 1),
          'member_photo_url', (SELECT m.photo_url FROM public.members m WHERE lower(m.email) = lower(a.email) LIMIT 1),
          'leader_extra_pert_score', a.leader_extra_pert_score
        ) || jsonb_build_object(
          'interview_score', a.interview_score,
          'cutoff_approved_email_sent_at', a.cutoff_approved_email_sent_at,
          'final_score_pert_target', a.final_score_pert_target,
          'final_score_pert_band_lower', a.final_score_pert_band_lower,
          'final_score_pert_band_upper', a.final_score_pert_band_upper,
          'final_score_pert_cutoff_method', a.final_score_pert_cutoff_method,
          'final_score_pert_cohort_n', a.final_score_pert_cohort_n,
          'final_score_pert_calc_at', a.final_score_pert_calc_at,
          'peer_eval_count', (
            SELECT count(*)::int FROM public.selection_evaluations e
            WHERE e.application_id = a.id AND e.evaluation_type = 'objective' AND e.submitted_at IS NOT NULL
          ),
          'peer_extra', jsonb_build_object(
            'distinct_evaluators', (
              SELECT count(DISTINCT e.evaluator_id)::int FROM public.selection_evaluations e
              WHERE e.application_id = a.id AND e.evaluation_type = 'objective' AND e.submitted_at IS NOT NULL
            ),
            'invites_pending', (
              SELECT count(*)::int FROM public.notifications n
              WHERE n.type = 'peer_review_requested' AND n.source_id = a.id
                AND NOT EXISTS (SELECT 1 FROM public.selection_evaluations e2 WHERE e2.application_id = a.id AND e2.evaluator_id = n.recipient_id)
            )
          ),
          'meta', jsonb_build_object(
            'ai_analysis_done', (a.consent_ai_analysis_at IS NOT NULL AND a.ai_analysis IS NOT NULL),
            'interview_scheduled', EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id AND si.status IN ('scheduled', 'completed', 'rescheduled')),
            'interview_next_at', (
              SELECT MIN(si.scheduled_at) FROM public.selection_interviews si
              WHERE si.application_id = a.id
                AND si.status = 'scheduled'
                AND si.scheduled_at >= now() - interval '12 hours'
            ),
            'has_interview_today', EXISTS (
              SELECT 1 FROM public.selection_interviews si
              WHERE si.application_id = a.id
                AND si.status = 'scheduled'
                AND (si.scheduled_at AT TIME ZONE 'America/Sao_Paulo')::date = (now() AT TIME ZONE 'America/Sao_Paulo')::date
            ),
            'token_consumed', EXISTS (SELECT 1 FROM public.onboarding_tokens t WHERE t.source_id = a.id AND t.source_type = 'pmi_application' AND COALESCE(t.access_count, 0) > 0),
            'video_screening_done', EXISTS (SELECT 1 FROM public.pmi_video_screenings v WHERE v.application_id = a.id AND v.status IN ('uploaded', 'transcribing', 'transcribed', 'opted_out')),
            'interview_stuck', (
              a.status = 'interview_scheduled'
              AND EXISTS (
                SELECT 1 FROM public.selection_interviews si
                WHERE si.application_id = a.id
                  AND si.status = 'scheduled'
                  AND si.conducted_at IS NULL
                  AND si.scheduled_at IS NOT NULL
                  AND si.scheduled_at < now() - COALESCE(
                        (SELECT value_interval FROM public.sla_policies WHERE policy_key = 'stuck_scheduled_grace'),
                        interval '48 hours')
              )
            )
          ),
          'video_agg', jsonb_build_object(
            'status_agg', (SELECT CASE WHEN count(*) = 0 THEN 'none' WHEN count(*) FILTER (WHERE v.status IN ('uploaded','transcribing','transcribed')) > 0 THEN 'uploaded' WHEN count(*) FILTER (WHERE v.status = 'opted_out') = count(*) THEN 'opted_out' ELSE 'partial' END FROM public.pmi_video_screenings v WHERE v.application_id = a.id),
            'uploaded_count', (SELECT count(*)::int FROM public.pmi_video_screenings v WHERE v.application_id = a.id AND v.status IN ('uploaded','transcribing','transcribed')),
            'total_rows', (SELECT count(*)::int FROM public.pmi_video_screenings v WHERE v.application_id = a.id)
          ),
          'pmi_canonical', jsonb_build_object(
            'chapter_canonical', (
              SELECT trim(c) FROM unnest(string_to_array(COALESCE(a.service_history_chapters, ''), ';')) AS c
              WHERE trim(c) <> '' AND trim(c) <> 'PMI Global' LIMIT 1
            ),
            'pmi_memberships', COALESCE(a.pmi_memberships, '[]'::jsonb),
            'is_pmi_member', (a.pmi_id IS NOT NULL AND a.pmi_id <> ''),
            'member_status', CASE
              WHEN a.pmi_id IS NULL OR a.pmi_id = '' THEN 'unknown'
              WHEN a.service_latest_end_date IS NULL THEN 'unknown'
              WHEN a.service_latest_end_date >= CURRENT_DATE THEN 'active'
              ELSE 'past'
            END,
            'member_since', a.service_first_start_date,
            'member_until', a.service_latest_end_date,
            'service_history_count', COALESCE(a.service_history_count, 0),
            'phase_b_fetched_at', a.pmi_data_fetched_at,
            'pmi_id', a.pmi_id
          ),
          'extra_flags', jsonb_build_object(
            'application_count', COALESCE(a.application_count, 1),
            'has_briefing', (a.last_briefing_at IS NOT NULL),
            'briefing_at', a.last_briefing_at,
            'briefing_model', a.last_briefing_model,
            'ai_triage_score', a.ai_triage_score,
            'ai_triage_confidence', a.ai_triage_confidence,
            'is_shadow_vep', (
              a.status IN ('approved', 'converted', 'cancelled', 'rejected', 'withdrawn')
              -- #2393: candidatura a vaga ligada a uma iniciativa nunca e sombra (decisao do GP,
              -- 30/10/2026). Le so a existencia da iniciativa; nenhuma coluna da vaga sai daqui.
              AND NOT EXISTS (
                SELECT 1 FROM public.vep_opportunities o
                WHERE o.opportunity_id = a.vep_opportunity_id
                  AND o.initiative_id IS NOT NULL
              )
              AND EXISTS (
                SELECT 1 FROM public.members m
                WHERE m.is_active = true
                  AND lower(m.email) = lower(a.email)
                  AND m.created_at < a.created_at
              )
            ),
            'pdf_likely_invalid', EXISTS (
              SELECT 1 FROM storage.objects so
              WHERE so.bucket_id = 'selection-resumes'
                AND so.name = a.resume_storage_path
                AND (so.metadata->>'size')::int < 1000
            )
          ),
          'vep_recon', jsonb_build_object(
            'status_raw', a.vep_status_raw,
            'last_seen_at', a.vep_last_seen_at,
            'reconciled_at', a.vep_reconciled_at,
            'offer_expires_at', a.vep_offer_expires_at,
            'expired_at', a.vep_expired_at
          ),
          'my_eval_status', COALESCE(
            (SELECT CASE WHEN e.submitted_at IS NOT NULL THEN 'submitted' ELSE 'draft' END
              FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id LIMIT 1),
            CASE WHEN EXISTS (SELECT 1 FROM public.notifications n WHERE n.type = 'peer_review_requested' AND n.source_id = a.id AND n.recipient_id = v_caller_id) THEN 'invited' ELSE 'not_invited' END
          ),
          'my_eval_score', (SELECT e.weighted_subtotal FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id AND e.submitted_at IS NOT NULL LIMIT 1)
        )
        -- #2393 (emenda de 06/11/2026 à ADR-0134 §4): as partes da candidatura piloto com alerta de divergência aberto.
        -- Só a gestão vê a linha piloto e lê as notas do piloto; para quem não é gestão, ou na avaliação geral, NULL.
        -- Antes da trilha, que fica colada na chave da vaga (guards 2393c e 2393-vaga-com-dono).
        || jsonb_build_object('divergence_types', CASE WHEN v_ve_piloto AND NOT public._na_avaliacao_geral(a.id) THEN (
             SELECT COALESCE(jsonb_agg(DISTINCT an.payload->>'evaluation_type'), '[]'::jsonb)
               FROM public.selection_evaluation_anomalies an
              WHERE an.application_id = a.id AND an.alert_type = 'high_variance' AND an.resolved_at IS NULL) END)
        -- #2393 fatia 3: a trilha de avaliação da vaga. Num || próprio, antes da chave da vaga, que fecha o objeto.
        || jsonb_build_object('evaluation_track', CASE WHEN public._na_avaliacao_geral(a.id) THEN 'general' ELSE 'line_pilot' END)
        -- #2393: a vaga do VEP da candidatura. Por `||` porque o objeto acima esta perto do teto de
        -- 100 argumentos do jsonb_build_object. So o id: o titulo fica com a RLS da vep_opportunities.
        || jsonb_build_object('vep_opportunity_id', a.vep_opportunity_id)
      ORDER BY COALESCE(a.leader_score, a.research_score, a.final_score) DESC NULLS LAST)
      FROM (
        SELECT
          sa.*,
          ROW_NUMBER() OVER (
            PARTITION BY sa.role_applied, public._na_avaliacao_geral(sa.id)  -- #2393 fatia 3: o piloto não divide posição com a avaliação geral
            ORDER BY sa.objective_score_avg DESC NULLS LAST, sa.id ASC
          )::int AS objective_rank
        FROM public.selection_applications sa
        WHERE sa.cycle_id = v_cycle_id
          AND (v_ve_piloto OR public._na_avaliacao_geral(sa.id))  -- #2393 fatia 3
      ) a
    ), '[]'::jsonb),
    'stats', v_stats_a || v_stats_b
  ) INTO v_result;
  RETURN v_result;
END;
$function$;
