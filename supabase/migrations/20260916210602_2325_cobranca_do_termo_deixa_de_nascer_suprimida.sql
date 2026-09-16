-- #2325 — a cobranca do Termo de Voluntariado deixa de nascer suprimida.
--
-- O DEFEITO, medido em 16/09:
--   `notify_pending_volunteer_agreements` emitia a cobranca com `p_type => 'system'`, e
--   `_delivery_mode_for('system')` devolve 'suppress' porque o catalogo ADR-0022 define o tipo
--   como "Internal system events. In-app only.". A cobranca nunca saia da plataforma: ficava no
--   sininho, que so e visto por quem entra, e quem precisa ser cobrado e justamente quem nao entra.
--   26 linhas, 16 pessoas, de 08/07 a 14/09. 26 das 28 linhas `system` da base eram esta cobranca.
--
-- POR QUE UM TIPO NOVO, e nao afrouxar `system`:
--   `system` tambem e emitido por `_alert_sweep_cron` e `_selection_consistency_cron`, que mandam
--   alerta interno para gestor. Mudar o modo de `system` transformaria esses em e-mail. O catalogo
--   esta certo; quem estava errado era o emissor.
--
-- POR QUE NAO REUSAR `selection_termo_due`, que ja e transactional_immediate:
--   Ele e emitido por `process_vep_acceptance_transition` no aceite do VEP, e
--   `_replay_selection_notifications_p228` faz replay sobre ele. Reusar misturaria dois atos
--   diferentes (o aviso de que o termo ABRIU e o lembrete de que ele SEGUE aberto) na mesma
--   serie, e um replay futuro repescaria cobrancas.
--
-- POR QUE `transactional_immediate`, e nao `digest_weekly`:
--   `digest_weekly` monta as secoes por lista branca de tipos e carimba `digest_delivered_at` em
--   tipo que nenhuma secao renderiza — e a #2286, aberta. Um tipo novo cair la seria trocar
--   "suprimido" por "carimbado como entregue sem nunca renderizar". A EF `send-notification-email`
--   roteia por `delivery_mode` e e type-agnostic (confirmado no codigo), entao o caminho imediato
--   entrega sem precisar de lista branca nenhuma.
--
-- POR QUE NAO ENTRA EM `_is_operational_candidate_facing`:
--   Aquela lista existe para furar `notify_delivery_mode_pref = 'suppress_all'` em e-mail
--   operacional para CANDIDATO. Esta cobranca e para MEMBRO ja aprovado, e uma cobranca
--   administrativa nao deve furar a preferencia de quem pediu silencio. Medido hoje: 99 membros
--   ativos, todos em `weekly_digest`, nenhum em `suppress_all` — entao a decisao nao muda nada
--   hoje e evita mexer no par TS/SQL que o guard adr-0022 exige em lock-step.
--
-- DEDUP DE 7 DIAS, que nasce junto de proposito:
--   Ate agora o botao era inofensivo porque nada saia. Passando a sair de verdade, um clique
--   repetido viraria e-mail repetido: no historico havia ate 6 avisos para a mesma pessoa em dois
--   meses. A janela de 7 dias e o mesmo padrao de `detect_credly_unmapped_cron` (que usa 25 dias).
--   O retorno passa a separar `notified` de `skipped_recent` para que o silencio seja legivel em
--   vez de parecer falha.
--
-- Cross-ref: #2325, #2286 (o digest que carimba sem renderizar), #2323 (detector sem cron),
--            ADR-0022 (catalogo), #1631 (o escopo passou a ser recalculado no servidor).

-- ---------------------------------------------------------------------------
-- (1) O helper. Corpo INTEIRO reescrito porque o guard adr-0022 le a ULTIMA migration que o
--     define. Atributos preservados de proposito: LANGUAGE sql, IMMUTABLE e SET search_path
--     — omitir IMMUTABLE o rebaixaria a VOLATILE em silencio.
-- ---------------------------------------------------------------------------
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
    ELSE 'digest_weekly'
  END;
$function$;

-- ---------------------------------------------------------------------------
-- (2) O emissor. Muda o TIPO e ganha janela de deduplicacao. Atributos preservados:
--     SECURITY DEFINER e `SET search_path = ''` — por isso todo objeto segue qualificado.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_pending_volunteer_agreements(p_lang text DEFAULT 'pt-BR')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_caller_person_id uuid;
  v_is_manage_member boolean;
  v_is_chapter_board boolean;
  v_is_vol_director boolean;
  v_title text;
  v_body text;
  v_targets int := 0;
  v_skipped int := 0;
  v_m record;
BEGIN
  SELECT m.id, m.chapter, m.person_id
    INTO v_caller_id, v_caller_chapter, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  v_is_manage_member := public.can_by_member(v_caller_id, 'manage_member');
  v_is_chapter_board := EXISTS (
    SELECT 1 FROM public.auth_engagements ae
    WHERE ae.person_id = v_caller_person_id
      AND ae.kind = 'chapter_board'
      AND ae.status = 'active'
  );
  v_is_vol_director := EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.id = v_caller_id AND 'voluntariado_director' = ANY(m.designations)
  );

  IF NOT v_is_manage_member AND NOT v_is_chapter_board AND NOT v_is_vol_director THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  v_title := CASE p_lang
    WHEN 'en-US'    THEN 'Volunteer Agreement Pending'
    WHEN 'es-LATAM' THEN 'Acuerdo de Voluntariado Pendiente'
    ELSE                 'Termo de Voluntariado Pendente'
  END;
  v_body := CASE p_lang
    WHEN 'en-US'    THEN 'Please sign your volunteer agreement to stay compliant.'
    WHEN 'es-LATAM' THEN 'Por favor firma tu acuerdo de voluntariado.'
    ELSE                 'Por favor assine seu termo de voluntariado para manter a conformidade.'
  END;

  -- Mesma populacao da aba do painel (voluntario ativo, dentro do escopo do chamador),
  -- filtrada pelos que ainda nao tem o termo do ano vigente emitido.
  FOR v_m IN
    SELECT m.id
    FROM public.members m
    WHERE m.is_active
      AND EXISTS (
        SELECT 1 FROM public.auth_engagements ae
        WHERE ae.person_id = m.person_id AND ae.kind = 'volunteer' AND ae.status = 'active'
      )
      AND (v_is_manage_member OR v_is_vol_director OR m.chapter = v_caller_chapter)
      AND NOT EXISTS (
        SELECT 1 FROM public.certificates c
        WHERE c.member_id = m.id
          AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
      )
  LOOP
    -- #2325: a janela nasce junto com a entrega real. Enquanto o tipo era `system`/suppress o
    -- clique repetido era inofensivo; agora ele vira e-mail, e o historico mostrava ate 6 avisos
    -- para a mesma pessoa em dois meses.
    IF EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.recipient_id = v_m.id
        AND n.type = 'volunteer_term_pending'
        AND n.created_at >= now() - interval '7 days'
    ) THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    -- Notacao NOMEADA de proposito: sao 3 sobrecargas e a ambiguidade ja derrubou uma RPC
    -- antes. So esta sobrecarga tem p_title + p_body + p_link juntos.
    PERFORM public.create_notification(
      p_recipient_id => v_m.id,
      p_type         => 'volunteer_term_pending',
      p_title        => v_title,
      p_body         => v_body,
      p_link         => '/volunteer-agreement'
    );
    v_targets := v_targets + 1;
  END LOOP;

  -- `targets` conta chamadas EMITIDAS, nao entregas: create_notification respeita
  -- notification_preferences e pode suprimir em silencio, e a sobrecarga que devolve void
  -- nao reporta isso. Nomear de `sent` seria tratar ausencia de medicao como medicao.
  -- `skipped_recent` existe para que o silencio da janela seja legivel em vez de parecer falha.
  RETURN jsonb_build_object(
    'ok', true,
    'targets', v_targets,
    'skipped_recent', v_skipped,
    'dedup_window_days', 7
  );
END;
$function$;
