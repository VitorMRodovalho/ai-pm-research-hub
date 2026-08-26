-- #2013 — o lembrete de reagendamento para de ser assedio.
--
-- O CASO (26/08/2026). Uma candidata escreveu ao entrevistador dizendo que recebera "mais um
-- lembrete automatico pedindo para remarcar em 48 horas", que ja tinha respondido ao e-mail do
-- Nucleo dois dias antes sem retorno, e que preferia NAO clicar em "Escolher novo horario" para
-- nao bagunçar o processo. O canal nao estava morto: a cadencia e que estava.
--
-- QUATRO DEFEITOS, TODOS MEDIDOS EM 26/08 — e um deles NAO e alcancado por esta migration.
--
-- (1) O PRAZO ERA FALSO E RENOVAVA SOZINHO. O texto dizia "e importante remarcar nas proximas 48
--     horas" e "sua candidatura pode ficar pausada". O cron repete a cada 3 dias
--     (`sla_policies.reschedule_nudge_repeat`), indefinidamente, e **nao existe estado de pausa**:
--     o dominio de `selection_applications.status` em uso no ciclo aberto nao tem para onde pausar,
--     e nenhum candidato jamais foi pausado. Um ultimato que se renova por 26 dias nao e prazo, e
--     urgencia sem consequencia — ensina o candidato a ignorar o remetente.
--     ⚠️ DECISAO DO PM (26/08): o conserto e o TEXTO parar de prometer, NAO criar o estado de pausa.
--     O teto abaixo passa a ser a consequencia real, e o texto passa a descreve-la.
--
-- (2) O LACO NAO TINHA TETO NEM ESCADA. So parava por mudanca de status da candidatura. Medido: os
--     5 candidatos que o cron ainda alcanca estao TODOS em exatamente 3 despachos no episodio atual
--     (1 link inicial de `request_interview_reschedule` + 2 lembretes do cron), e o 4o sairia em
--     29/08. Com o teto de 3, os cinco param AGORA e viram trabalho de gente.
--
-- (3) O SINAL DE ENGAJAMENTO JA ESTAVA GRAVADO E NINGUEM O LIA. `selection_dispatch_url_log` tem
--     `open_count`, e dois padroes OPOSTOS recebiam o mesmo e-mail: um candidato com 23 aberturas e
--     zero agendamentos (esta tentando e o agendamento falha — pede gente) e outro com 5 despachos
--     medidos e ZERO aberturas (o e-mail pode nao estar chegando — pede verificar entrega).
--     O diagnostico agora vai na ESCALACAO ao comite, nao em e-mail novo ao candidato.
--     ⚠️ `instrumented` antes de dividir: 94 dos 131 despachos do ciclo nunca foram medidos, e ali
--     `open_count = 0` significa "nao medi", nao "nao abriu". A leitura ingenua da 4% de conversao;
--     a correta da 38%. Todo agregado abaixo filtra por `instrumented`.
--
-- (4) `interview_status` NUNCA SE LIMPAVA. Nem `schedule_interview` nem `submit_interview_scores`
--     escreviam a coluna — so `request_interview_reschedule` (que a poe em `needs_reschedule`) e
--     `mark_interview_status`. Medido: 9 linhas em `needs_reschedule`, 3 delas com entrevista
--     CONCLUIDA e pontuada (duas ja `approved`, uma `final_eval`). Elas escapavam do cron pelo
--     FILTRO DE STATUS da candidatura, por acidente e nao por desenho. O dominio do CHECK ja tem
--     `scheduled` e `completed` — os valores existiam e ninguem os escrevia.
--
-- O QUE ESTA MIGRATION NAO RESOLVE, e fica declarado: quem RESPONDE ao e-mail automatico continua
-- invisivel para o automatismo que o gerou (item 5 do aceite). O teto reduz o dano — depois de 3
-- despachos o caso vira notificacao a gente de verdade — mas nao existe caminho de volta da caixa
-- de entrada para a candidatura. Isso e issue propria.
--
-- Cross-ref: #2013, #2012 (o outro lado do mesmo incidente), #1997 (duas das candidaturas saneadas aqui tambem sao
-- da coorte sem conta), #1595 (link governado), #1978 (escada de destinatarios do comite).

-- ─────────────────────────────────────────────────────────────────────────────────────
-- 1. O teto vive no SSOT de configuracao numerica, nao no corpo da funcao.
--    `platform_settings` e onde ja moram `max_members_per_tribe` e `attendance.seal_window`.
-- ─────────────────────────────────────────────────────────────────────────────────────
INSERT INTO public.platform_settings (key, value, description)
VALUES (
  'selection.reschedule_nudge_max_dispatches',
  '3'::jsonb,
  'Teto de despachos de link de reagendamento por EPISODIO (contados desde interview_reschedule_requested_at, incluindo o link inicial). Ao atingir, o cron process_pending_reschedule_nudges PARA de escrever ao candidato e escala para o comite do ciclo uma unica vez. #2013.'
)
ON CONFLICT (key) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- 2. Marcador da escalacao. Sem ele o cron re-notificaria o comite todo dia.
--    Comparado contra `interview_reschedule_requested_at`, entao um episodio NOVO volta a
--    poder escalar sem precisar de reset em lugar nenhum.
-- ─────────────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS interview_reschedule_escalated_at timestamptz;

COMMENT ON COLUMN public.selection_applications.interview_reschedule_escalated_at IS
  '#2013: quando o teto de despachos deste episodio de reagendamento foi atingido e o comite foi avisado. Escopado por episodio: vale enquanto for >= interview_reschedule_requested_at.';

-- ─────────────────────────────────────────────────────────────────────────────────────
-- 3. O texto para de prometer o que nao existe (decisao do PM, 26/08).
--    Sai: "nas proximas 48 horas" e "sua candidatura pode ficar pausada".
--    Entra: a consequencia REAL — o numero de lembretes e limitado e depois o comite retoma.
-- ─────────────────────────────────────────────────────────────────────────────────────
UPDATE public.campaign_templates
SET body_html = jsonb_build_object(
      'pt', '<p>Olá {{first_name}},</p><p>Há alguns dias enviamos um link para você remarcar sua entrevista (motivo: {{reason}}). Notamos que ainda não foi agendado um novo horário.</p><p>Quando puder, é só escolher um horário:</p><p><a href="{{booking_url}}" style="background:#0066cc;color:#fff;padding:10px 20px;text-decoration:none;border-radius:4px;">Escolher novo horário</a></p><p style="color:#666;font-size:13px;">Enviamos um número limitado de lembretes automáticos. Depois disso o comitê retoma o contato com você — nada é decidido sem falar antes. Se preferir desistir, responda este e-mail; não tem problema, só precisamos saber.</p><p>Obrigado!<br/>Núcleo IA &amp; GP</p>',
      'en', '<p>Hello {{first_name}},</p><p>A few days ago we sent you a link to reschedule your interview (reason: {{reason}}). We noticed a new slot has not yet been booked.</p><p>Whenever you can, just pick a slot:</p><p><a href="{{booking_url}}" style="background:#0066cc;color:#fff;padding:10px 20px;text-decoration:none;border-radius:4px;">Pick a new slot</a></p><p style="color:#666;font-size:13px;">We send a limited number of automatic reminders. After that the committee follows up with you directly — nothing is decided without talking to you first. If you prefer to withdraw, just reply to this email; no problem, we just need to know.</p><p>Thank you!<br/>Núcleo IA &amp; GP</p>',
      'es', '<p>Hola {{first_name}},</p><p>Hace algunos días te enviamos un enlace para reagendar tu entrevista (motivo: {{reason}}). Notamos que aún no se ha agendado un nuevo horario.</p><p>Cuando puedas, solo elige un horario:</p><p><a href="{{booking_url}}" style="background:#0066cc;color:#fff;padding:10px 20px;text-decoration:none;border-radius:4px;">Elegir nuevo horario</a></p><p style="color:#666;font-size:13px;">Enviamos un número limitado de recordatorios automáticos. Después de eso el comité retoma el contacto contigo — nada se decide sin hablar antes. Si prefieres desistir, responde este correo; sin problema, solo necesitamos saber.</p><p>¡Gracias!<br/>Núcleo IA &amp; GP</p>'
    ),
    body_text = jsonb_build_object(
      'pt', 'Olá {{first_name}},\n\nHá alguns dias enviamos um link para remarcar sua entrevista (motivo: {{reason}}). Quando puder, escolha um horário: {{booking_url}}\n\nEnviamos um número limitado de lembretes automáticos; depois disso o comitê retoma o contato. Se preferir desistir, responda este e-mail.\n\nNúcleo IA & GP',
      'en', 'Hello {{first_name}},\n\nA few days ago we sent a link to reschedule your interview (reason: {{reason}}). Whenever you can, pick a slot: {{booking_url}}\n\nWe send a limited number of automatic reminders; after that the committee follows up directly. If you prefer to withdraw, reply to this email.\n\nNúcleo IA & GP',
      'es', 'Hola {{first_name}},\n\nHace algunos días te enviamos un enlace para reagendar tu entrevista (motivo: {{reason}}). Cuando puedas, elige un horario: {{booking_url}}\n\nEnviamos un número limitado de recordatorios automáticos; después de eso el comité retoma el contacto. Si prefieres desistir, responde este correo.\n\nNúcleo IA & GP'
    ),
    updated_at = now()
WHERE slug = 'interview_reschedule_nudge';

-- ─────────────────────────────────────────────────────────────────────────────────────
-- 4. O tipo novo entra no CATALOGO de entrega, em vez de cair no ELSE.
--    Mesmo motivo registrado no #1855 e no bloco 5b do #625: o ELSE e um default de
--    conveniencia e um dia muda. `transactional_immediate` porque uma escalacao que espera
--    o digest semanal pode nunca chegar — o gate `v_has_content` do digest so entrega a quem
--    tem OUTRO conteudo na semana (#2010), que e exatamente a classe de sinal invisivel que
--    esta issue ataca.
-- ─────────────────────────────────────────────────────────────────────────────────────
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
    -- #1224 PR2 (2026-07-09): one-time onboarding nudge when the PMI enrichment cannot resolve
    -- an entry chapter (profile_private / no_fetch / not_affiliated / ambiguous-no-choice).
    WHEN 'entry_chapter_action_needed'    THEN 'transactional_immediate'
    -- #740 Wave 3c-i (B8): agreement rejected / reissued — member must re-sign, deliver immediately
    WHEN 'volunteer_agreement_rejected'  THEN 'transactional_immediate'
    WHEN 'volunteer_agreement_reissued'  THEN 'transactional_immediate'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    ELSE 'digest_weekly'
  END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- 5. O cron: teto, escalacao unica e diagnostico por `open_count` (itens 1 e 3).
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.process_pending_reschedule_nudges()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_app record;
  v_first_name text;
  v_booking_url text;
  v_dispatch jsonb;
  v_nudges_sent int := 0;
  v_errors jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
  v_processed jsonb := '[]'::jsonb;
  v_nudge_initial interval;
  v_nudge_repeat interval;
  -- #2013
  v_max_dispatches int;
  v_escalations int := 0;
  v_escalated jsonb := '[]'::jsonb;
  v_ep record;
  v_diag text;
  v_diag_code text;
BEGIN
  SELECT value_interval INTO v_nudge_initial FROM public.sla_policies WHERE policy_key = 'reschedule_nudge_initial';
  IF v_nudge_initial IS NULL THEN v_nudge_initial := interval '3 days'; END IF;
  SELECT value_interval INTO v_nudge_repeat FROM public.sla_policies WHERE policy_key = 'reschedule_nudge_repeat';
  IF v_nudge_repeat IS NULL THEN v_nudge_repeat := interval '3 days'; END IF;

  -- #2013 — o teto vem do SSOT. O fallback existe para o cron nunca virar laco infinito se a
  -- chave sumir; ele repete o valor semeado nesta mesma migration, de proposito.
  SELECT NULLIF(value #>> '{}', '')::int INTO v_max_dispatches
  FROM public.platform_settings WHERE key = 'selection.reschedule_nudge_max_dispatches';
  IF v_max_dispatches IS NULL OR v_max_dispatches < 1 THEN v_max_dispatches := 3; END IF;

  -- Cron-context auth bypass (sem JWT). Alinhado ao padrão do ADR-0028 (emenda p89).
  IF auth.role() IS NOT NULL AND auth.role() NOT IN ('service_role') AND auth.uid() IS NOT NULL THEN
    IF NOT public.can_by_member(
      (SELECT id FROM public.members WHERE auth_id = auth.uid()),
      'manage_member'
    ) THEN
      RAISE EXCEPTION 'Unauthorized: cron RPC requires manage_member or service_role';
    END IF;
  END IF;

  FOR v_app IN
    SELECT a.id, a.applicant_name, a.email, a.cycle_id,
           a.interview_reschedule_reason,
           a.interview_reschedule_requested_at,
           a.interview_reschedule_last_nudged_at,
           a.interview_reschedule_escalated_at
    FROM public.selection_applications a
    WHERE a.interview_status = 'needs_reschedule'
      AND a.interview_reschedule_requested_at IS NOT NULL
      AND a.interview_reschedule_requested_at < now() - v_nudge_initial
      AND (
        a.interview_reschedule_last_nudged_at IS NULL
        OR a.interview_reschedule_last_nudged_at < now() - v_nudge_repeat
      )
      AND a.status IN ('interview_pending', 'interview_scheduled')
  LOOP
    -- #2013 — o EPISODIO e a janela desde o pedido de reagendamento. Contar assim faz o teto
    -- se reabrir sozinho quando um pedido NOVO chega, sem coluna de reset em lugar nenhum.
    -- `instrumented` separa "nao abriu" de "nao medi": sem esse filtro, `open_count = 0` de um
    -- despacho nao instrumentado leria como desinteresse e produziria o diagnostico OPOSTO.
    SELECT
      count(*)::int                                                        AS despachos,
      (count(*) FILTER (WHERE d.instrumented))::int                        AS medidos,
      COALESCE(sum(d.open_count) FILTER (WHERE d.instrumented), 0)::int    AS aberturas,
      (count(*) FILTER (WHERE d.booked_at IS NOT NULL))::int               AS agendamentos
    INTO v_ep
    FROM public.selection_dispatch_url_log d
    WHERE d.application_id = v_app.id
      AND d.dispatched_at >= v_app.interview_reschedule_requested_at;

    IF v_ep.despachos >= v_max_dispatches THEN
      -- Teto atingido: o candidato NAO recebe mais nada por este caminho. Uma unica escalacao
      -- por episodio, com o diagnostico que `open_count` ja permitia fazer e ninguem lia.
      IF v_app.interview_reschedule_escalated_at IS NULL
         OR v_app.interview_reschedule_escalated_at < v_app.interview_reschedule_requested_at THEN

        IF v_ep.medidos = 0 THEN
          v_diag_code := 'sem_medicao';
          v_diag := format('%s despacho(s), nenhum instrumentado: nao da para dizer se o e-mail chegou nem se foi aberto.', v_ep.despachos);
        ELSIF v_ep.aberturas = 0 THEN
          v_diag_code := 'nao_abriu';
          v_diag := format('%s e-mail(s) medido(s) e ZERO aberturas: verificar entrega (spam, endereco errado) antes de insistir.', v_ep.medidos);
        ELSE
          v_diag_code := 'abriu_e_nao_agendou';
          v_diag := format('%s abertura(s) e nenhum agendamento: o agendamento provavelmente esta falhando para esta pessoa, vale contato humano.', v_ep.aberturas);
        END IF;

        BEGIN
          PERFORM public.create_notification(
            r.id,
            'selection_reschedule_escalated',
            'Reagendamento sem resposta: ' || v_app.applicant_name,
            format('Teto de %s despacho(s) automatico(s) atingido neste pedido de reagendamento. %s', v_max_dispatches, v_diag),
            '/admin/selection?app=' || v_app.id::text,
            'selection_application',
            v_app.id
          )
          FROM public._selection_cycle_recipients(v_app.cycle_id) r;

          UPDATE public.selection_applications
          SET interview_reschedule_escalated_at = now()
          WHERE id = v_app.id;

          v_escalations := v_escalations + 1;
          v_escalated := v_escalated || jsonb_build_object(
            'application_id', v_app.id,
            'applicant_name', v_app.applicant_name,
            'dispatches', v_ep.despachos,
            'instrumented', v_ep.medidos,
            'opens', v_ep.aberturas,
            'diagnosis_code', v_diag_code,
            'diagnosis', v_diag
          );
        EXCEPTION WHEN OTHERS THEN
          v_errors := v_errors || jsonb_build_object('application_id', v_app.id, 'error', SQLERRM);
        END;
      END IF;

      CONTINUE;
    END IF;

    v_first_name := split_part(v_app.applicant_name, ' ', 1);
    v_dispatch := NULL;
    v_booking_url := NULL;

    -- Subtransação 1: o despacho governado. Commita por si — um erro de envio adiante não a desfaz.
    BEGIN
      v_dispatch := public._dispatch_interview_booking_link(v_app.id, NULL, 'process_pending_reschedule_nudges');
    EXCEPTION WHEN OTHERS THEN
      v_dispatch := jsonb_build_object('success', false, 'failure_code', 'DISPATCH_ERROR', 'message', SQLERRM);
    END;

    IF COALESCE((v_dispatch->>'success')::boolean, false) IS NOT TRUE THEN
      -- Sem link governado não sai cutucão: mandar o literal do Google era o defeito da #1595.
      v_skipped := v_skipped || jsonb_build_object(
        'application_id', v_app.id,
        'failure_code', v_dispatch->>'failure_code',
        'gate_failed_code', v_dispatch->>'gate_failed_code'
      );
      CONTINUE;
    END IF;

    v_booking_url := v_dispatch->>'booking_url';

    -- Subtransação 2: envio + carimbo.
    BEGIN
      PERFORM public.campaign_send_one_off(
        p_template_slug := 'interview_reschedule_nudge',
        p_to_email := v_app.email,
        p_variables := jsonb_build_object(
          'first_name', v_first_name,
          'reason', COALESCE(v_app.interview_reschedule_reason, '—'),
          'booking_url', v_booking_url
        ),
        p_metadata := jsonb_build_object(
          'source', 'process_pending_reschedule_nudges',
          'application_id', v_app.id,
          'reschedule_requested_at', v_app.interview_reschedule_requested_at,
          'last_nudged_at_before', v_app.interview_reschedule_last_nudged_at,
          'days_pending', EXTRACT(EPOCH FROM (now() - v_app.interview_reschedule_requested_at)) / 86400.0,
          'link_kind', 'governed_token',
          'gate_mode', v_dispatch->>'gate_mode',
          'dispatch_number', v_ep.despachos + 1,
          'dispatch_cap', v_max_dispatches
        )
      );

      UPDATE public.selection_applications
      SET interview_reschedule_last_nudged_at = now()
      WHERE id = v_app.id;

      v_nudges_sent := v_nudges_sent + 1;
      v_processed := v_processed || jsonb_build_object(
        'application_id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'gate_mode', v_dispatch->>'gate_mode',
        'dispatch_number', v_ep.despachos + 1,
        'dispatch_cap', v_max_dispatches,
        'days_since_request', EXTRACT(EPOCH FROM (now() - v_app.interview_reschedule_requested_at)) / 86400.0
      );

    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_object(
        'application_id', v_app.id,
        'error', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'nudges_sent', v_nudges_sent,
    'escalations', v_escalations,
    'dispatch_cap', v_max_dispatches,
    'processed', v_processed,
    'escalated', v_escalated,
    'skipped', v_skipped,
    'errors', v_errors,
    'run_at', now()
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- 6. `interview_status` passa a ter DONO (item 4).
--
--    Nem `schedule_interview` nem `submit_interview_scores` escreviam a coluna. Em vez de
--    ensinar as duas a faze-lo, o dono e o trigger que a p240 ja declarou canonico para
--    sincronizar entrevista -> candidatura: ele dispara em INSERT e em UPDATE de
--    (status, conducted_at), entao cobre de uma vez o agendamento manual, a pontuacao, o
--    `mark_interview_status` e o webhook de calendario.
--
--    ⚠️ A ESCRITA VEM ANTES DO PORTAO TERMINAL, e isso e deliberado. O portao existe para o
--    trigger NUNCA sobrescrever `selection_applications.status` de quem ja e
--    `approved`/`final_eval` (diretiva do PM de 24/05). Mas `interview_status` e sub-estado da
--    ENTREVISTA, nao do funil — e as linhas sujas medidas em 26/08 estao JUSTAMENTE em
--    `approved` e `final_eval`. Escrever depois do portao seria escrever para todos menos
--    para quem precisa. Nada aqui toca a coluna `status`.
--
--    ⚠️ A regra `needs_reschedule -> rescheduled` NAO e nova: `src/pages/api/calendar-webhook.ts`
--    ja a aplica ao materializar um agendamento. Ela e ESPELHADA aqui de proposito, para haver
--    uma regra so — duas regras divergentes sobre a mesma coluna e o defeito seguinte.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._trg_sync_interview_to_app_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_app_status text;
BEGIN
  -- #2013 — sub-estado da ENTREVISTA. Ver o bloco de comentario da migration: precede o portao
  -- terminal de proposito, e nao encosta em `selection_applications.status`.
  IF NEW.conducted_at IS NOT NULL OR NEW.status = 'completed' THEN
    UPDATE public.selection_applications
       SET interview_status = 'completed', updated_at = now()
     WHERE id = NEW.application_id
       AND interview_status IS DISTINCT FROM 'completed';
  ELSIF NEW.status IN ('scheduled', 'rescheduled') THEN
    UPDATE public.selection_applications
       SET interview_status = CASE WHEN interview_status = 'needs_reschedule'
                                   THEN 'rescheduled' ELSE 'scheduled' END,
           updated_at = now()
     WHERE id = NEW.application_id
       AND COALESCE(interview_status, 'none') IN ('none', 'needs_reschedule');
  END IF;

  SELECT status INTO v_app_status
  FROM public.selection_applications
  WHERE id = NEW.application_id;

  -- Terminal / locked statuses: trigger never overwrites these.
  -- (PM directive 2026-05-24: trigger nunca toca terminal.)
  IF v_app_status IS NULL OR v_app_status IN (
    'approved', 'rejected', 'converted', 'withdrawn', 'cancelled', 'waitlist', 'final_eval'
  ) THEN
    RETURN NEW;
  END IF;

  -- Evidence: interview conducted (conducted_at set OR status='completed') → interview_done
  IF NEW.conducted_at IS NOT NULL OR NEW.status = 'completed' THEN
    UPDATE public.selection_applications
       SET status = 'interview_done', updated_at = now()
     WHERE id = NEW.application_id
       AND status IN ('screening', 'objective_eval', 'objective_cutoff', 'interview_pending', 'interview_scheduled');
    RETURN NEW;
  END IF;

  -- Evidence: interview scheduled/rescheduled (not yet conducted) → interview_scheduled
  IF NEW.status IN ('scheduled', 'rescheduled') THEN
    UPDATE public.selection_applications
       SET status = 'interview_scheduled', updated_at = now()
     WHERE id = NEW.application_id
       AND status IN ('screening', 'objective_eval', 'objective_cutoff', 'interview_pending');
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- 7. Saneamento (item 6). Pela REGRA, nao por lista de ids — e por isso alcanca 6 linhas e
--    nao as 3 que a issue nomeia: alem das 3 em `needs_reschedule` com entrevista concluida,
--    ha 2 em `none` e 1 em `scheduled` na mesma condicao. Todas `approved`/`final_eval`, todas
--    com entrevista de fato conduzida. Medido em 26/08/2026.
--    Espelha exatamente o predicado que o trigger acima passa a aplicar na ENTRADA.
-- ─────────────────────────────────────────────────────────────────────────────────────
UPDATE public.selection_applications a
   SET interview_status = 'completed', updated_at = now()
 WHERE a.interview_status IS DISTINCT FROM 'completed'
   AND EXISTS (
     SELECT 1 FROM public.selection_interviews i
      WHERE i.application_id = a.id
        AND (i.conducted_at IS NOT NULL OR i.status = 'completed')
   );
