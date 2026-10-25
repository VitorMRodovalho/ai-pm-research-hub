-- #2782: pedido de capítulo ou de organização pelo formulário da home vai para o CRM de parceiros.
--
-- Medido em 24/10/2026: as portas "Para capítulos" e "Para organizações" da home (JoinSection.astro) abrem o
-- formulário de interesse (InterestForm.tsx) com role_interest 'chapter' e 'partner' e chamam
-- capture_visitor_lead, que gravava em visitor_leads e parava: nenhum gatilho, nenhum aviso, nenhuma tela (só uma
-- ferramenta do MCP lê a tabela). A home promete resposta em até 5 dias úteis. auto_promote_eligible nasce true e
-- auto_promote_eligible_leads_for_cycle não olhava o papel, então um pedido de capítulo podia virar candidatura de
-- pesquisador quando um ciclo abrisse.
--
-- Decisões do GP: o pedido vai para o CRM de parceiros; o contato de quem pediu fica SÓ no histórico da entidade
-- (partner_interactions, que só manage_platform lê); o aviso vai a quem tem manage_platform; e a retenção é a
-- mesma do lead.
--
-- (1) _delivery_mode_for: 'partner_lead_received' => transactional_immediate (sino e e-mail). Corpo = captura da
--     #2701 (20261017000419, igual ao vivo em 24/10) + uma linha; o comentário da #740 perdeu um travessão.
-- (2) capture_visitor_lead: para 'chapter' e 'partner', o lead nasce (ou passa a ficar) com
--     auto_promote_eligible = false; cria uma linha em partner_entities (status 'prospect'; entity_type
--     'pmi_chapter' para capítulo e 'outro' para organização ou comunidade, que o formulário não distingue) SEM
--     contact_name, contact_email nem nome de pessoa; registra nome, e-mail, telefone e mensagem numa nota de
--     partner_interactions (em details, nunca em summary, que o registro de auditoria expõe); avisa os membros
--     ativos com login e manage_platform (pelo ajudante (2a)); e grava em admin_audit_log a linha 'visitor_lead.routed_to_partner_crm'
--     com o lead, a entidade e a nota. Essa linha é o vínculo lead -> entidade (repetir o envio reaproveita a
--     entidade do mesmo lead) e o MARCADOR de origem que só este caminho grava. A resposta ao chamador anônimo
--     continua com a MESMA forma em todos os caminhos (#1050).
-- (2a) _notify_partner_lead_received: o laço de destinatários do aviso, fora da captura. A varredura do #965
--     (_audit_secdef_public_grant_drift) lê como portão de autoridade qualquer função SECURITY DEFINER anônima cujo
--     corpo cite um dos termos de portão que ela procura, e a captura citava um deles só para escolher quem recebe o
--     aviso: saía da varredura sem ter portão nenhum. O ajudante é SECURITY INVOKER e fechado a PUBLIC, anon e
--     authenticated; a captura o chama como dona, então a chamada segue valendo.
-- (3) auto_promote_eligible_leads_for_cycle: pula 'chapter' e 'partner' mesmo com a flag true (defesa em
--     profundidade). Corpo = captura da #684 (20260805000169, igual ao vivo) + uma condição.
-- (4) _data_retention_sweep: dois ramos novos, presos ao marcador. partner_interactions/anonymize tira o dado de
--     quem pediu (details) da nota do formulário quando a entidade criada pelo formulário segue prospect sem edição
--     nem interação no prazo; partner_entities/delete apaga, num passo seguinte, a entidade que ficou casca (só
--     notas do formulário já anonimizadas e nenhum outro vínculo). Corpo = captura da #1812 (20260816184810, igual
--     ao vivo) + uma variável e os dois ramos. partner_interactions não é tratada como append-only em lugar nenhum
--     (nenhum gatilho, nenhum guard), por isso a anonimização é UPDATE.
-- (5) data_retention_policy: as duas políticas, com o prazo da política de visitor_leads.
--
-- O status do lead fica 'new' (o CHECK só admite new, contacted, promoted e dismissed; nenhum descreve "foi para o
-- CRM"), e a varredura segue apagando o lead não convertido no prazo.
--
-- Rollback: recriar as quatro funções pelas capturas citadas acima, DROP FUNCTION
-- public._notify_partner_lead_received(uuid, boolean, text), e apagar as duas linhas de data_retention_policy por
-- (table_name, cleanup_type).

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
    ELSE 'digest_weekly'
  END;
$function$;

-- ── (2a) aviso a quem gere a plataforma ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public._notify_partner_lead_received(p_partner_id uuid, p_created boolean, p_door text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_recipient record;
  v_n integer := 0;
BEGIN
  -- o aviso não leva nome, e-mail, telefone nem a mensagem: o contato fica no histórico, atrás de manage_platform
  FOR v_recipient IN
    SELECT m.id FROM public.members m
     WHERE m.member_status = 'active' AND m.auth_id IS NOT NULL
       AND public.can_by_member(m.id, 'manage_platform')
       AND NOT EXISTS (
         SELECT 1 FROM public.notifications n
          WHERE n.recipient_id = m.id AND n.type = 'partner_lead_received'
            AND n.source_id = p_partner_id AND n.is_read IS NOT TRUE)
  LOOP
    PERFORM public.create_notification(
      v_recipient.id,
      'partner_lead_received',
      CASE WHEN p_created THEN 'Novo pedido pelo site: ' ELSE 'Nova mensagem pelo site: ' END || p_door,
      CASE WHEN p_created
        THEN 'Chegou pelo formulário da home e entrou no CRM de parceiros como prospect; o contato está no histórico da entidade. A home promete resposta em até 5 dias úteis.'
        ELSE 'Chegou pelo formulário da home uma nova mensagem sobre um pedido que já está no CRM de parceiros; o contato está no histórico da entidade. A home promete resposta em até 5 dias úteis.'
      END,
      '/admin/partnerships',
      'partner_entities',
      p_partner_id
    );
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$function$;
REVOKE ALL ON FUNCTION public._notify_partner_lead_received(uuid, boolean, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._notify_partner_lead_received(uuid, boolean, text) TO service_role;

-- ── (2) captura do lead ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.capture_visitor_lead(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_lead_id uuid;
  v_email text;
  v_name text;
  v_consent boolean;
  v_referrer_id uuid;
  v_existing_id uuid;
  v_target_vertical uuid;
  v_role text;
  v_message text;
  v_phone text;
  v_partner_route boolean;
  v_door text;
  v_today text;
  v_summary text;
  v_details text;
  v_partner_id uuid;
  v_interaction_id uuid;
  v_partner_created boolean := false;
BEGIN
  IF NOT public.rl_check_and_bump('capture_visitor_lead', 10, 60) THEN
    RETURN jsonb_build_object('error','rate_limited');
  END IF;

  v_email := NULLIF(TRIM(LOWER(p_payload->>'email')), '');
  v_name := NULLIF(TRIM(p_payload->>'name'), '');
  v_consent := COALESCE((p_payload->>'lgpd_consent')::boolean, false);

  IF v_email IS NULL OR v_name IS NULL THEN
    RETURN jsonb_build_object('error','name and email are required');
  END IF;

  IF NOT v_consent THEN
    RETURN jsonb_build_object('error','LGPD consent is required');
  END IF;

  -- Soft email format check
  IF v_email !~ '^[^@]+@[^@]+\.[^@]+$' THEN
    RETURN jsonb_build_object('error','invalid email format');
  END IF;

  -- Optional referrer (member_id from URL query ?ref=xxx)
  IF p_payload ? 'referrer_member_id' AND (p_payload->>'referrer_member_id') ~ '^[0-9a-f-]{36}$' THEN
    v_referrer_id := (p_payload->>'referrer_member_id')::uuid;
    -- Verify exists
    PERFORM 1 FROM public.members WHERE id = v_referrer_id;
    IF NOT FOUND THEN v_referrer_id := NULL; END IF;
  END IF;

  -- Optional founder-interest vertical (bloco 6 CTA). Resolve defensively: keep only
  -- when it points at a real community_vertical; else drop to NULL (analytics field,
  -- never blocks lead capture). Mirrors referrer_member_id (data-architect/security review).
  IF p_payload ? 'target_vertical' AND (p_payload->>'target_vertical') ~ '^[0-9a-f-]{36}$' THEN
    v_target_vertical := (p_payload->>'target_vertical')::uuid;
    PERFORM 1 FROM public.initiatives WHERE id = v_target_vertical AND kind = 'community_vertical';
    IF NOT FOUND THEN v_target_vertical := NULL; END IF;
  END IF;

  -- #2782: as portas "Para capítulos" e "Para organizações" da home mandam role_interest 'chapter' e 'partner'
  -- (InterestForm.tsx, JoinSection.astro). Pedido assim é de parceria, não candidatura de pesquisador.
  v_role := NULLIF(TRIM(p_payload->>'role_interest'), '');
  v_message := NULLIF(TRIM(p_payload->>'message'), '');
  v_phone := NULLIF(TRIM(p_payload->>'phone'), '');
  v_partner_route := COALESCE(v_role IN ('chapter', 'partner'), false);

  -- Idempotent: if same email already exists with status='new', update it (same response shape below)
  SELECT id INTO v_existing_id
  FROM public.visitor_leads
  WHERE LOWER(TRIM(email)) = v_email AND status = 'new'
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    -- Update with new payload (last-wins on optional fields)
    UPDATE public.visitor_leads SET
      phone = COALESCE(v_phone, phone),
      chapter_interest = COALESCE(NULLIF(TRIM(p_payload->>'chapter_interest'),''), chapter_interest),
      role_interest = COALESCE(v_role, role_interest),
      message = COALESCE(v_message, message),
      target_vertical = COALESCE(v_target_vertical, target_vertical),
      utm_data = COALESCE(p_payload->'utm_data', utm_data),
      referrer_member_id = COALESCE(v_referrer_id, referrer_member_id),
      source = COALESCE(NULLIF(TRIM(p_payload->>'source'),''), source),
      -- #2782: pedido de parceria nunca vira candidatura; a flag não volta a true sozinha
      auto_promote_eligible = CASE WHEN v_partner_route THEN false ELSE auto_promote_eligible END
    WHERE id = v_existing_id;
    v_lead_id := v_existing_id;
  ELSE
    INSERT INTO public.visitor_leads (
      name, email, phone, chapter_interest, role_interest, message,
      lgpd_consent, source, status, utm_data, referrer_member_id, target_vertical,
      auto_promote_eligible
    ) VALUES (
      v_name, v_email,
      v_phone,
      NULLIF(TRIM(p_payload->>'chapter_interest'), ''),
      v_role,
      v_message,
      true,
      COALESCE(NULLIF(TRIM(p_payload->>'source'), ''), 'website'),
      'new',
      p_payload->'utm_data',
      v_referrer_id,
      v_target_vertical,
      NOT v_partner_route
    )
    RETURNING id INTO v_lead_id;
  END IF;

  -- #2782: o pedido de parceria entra no CRM como prospect e avisa quem gere a plataforma.
  IF v_partner_route THEN
    v_door := CASE v_role WHEN 'chapter' THEN 'capítulo PMI' ELSE 'organização ou comunidade' END;
    v_today := to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD');
    -- summary vai ao registro de auditoria (get_audit_log, export_audit_log_csv): não leva dado de quem pediu
    v_summary := 'Pedido pelo formulário público do site (' || v_door || '), lead ' || v_lead_id::text;
    -- o contato de quem pediu mora SÓ aqui: details só sai por get_partner_interactions (manage_platform)
    v_details := 'Nome: ' || v_name || E'\nE-mail: ' || v_email
      || COALESCE(E'\nTelefone: ' || v_phone, '')
      || COALESCE(E'\nMensagem: ' || v_message, '');

    -- a entidade do MESMO lead, pelo vínculo que este caminho grava; contato de outra entidade não casa nada
    SELECT pe.id INTO v_partner_id
      FROM public.admin_audit_log a
      JOIN public.partner_entities pe ON pe.id::text = a.changes->>'partner_entity_id'
     WHERE a.action = 'visitor_lead.routed_to_partner_crm'
       AND a.target_type = 'visitor_lead' AND a.target_id = v_lead_id
     ORDER BY a.created_at DESC
     LIMIT 1;

    IF v_partner_id IS NULL THEN
      -- sem contato e sem nome de pessoa: capítulo ativo tem o nome publicado (get_public_impact_data)
      INSERT INTO public.partner_entities (
        name, entity_type, partnership_date, status, notes, updated_at
      ) VALUES (
        'Pedido pelo site: ' || v_door || ' (' || v_today || ', ' || left(v_lead_id::text, 8) || ')',
        CASE v_role WHEN 'chapter' THEN 'pmi_chapter' ELSE 'outro' END,
        CURRENT_DATE,
        'prospect',
        'Criado pelo formulário público do site em ' || v_today || ' (lead ' || v_lead_id::text
          || ', porta: ' || v_door || '). O contato está no histórico. Identidade do remetente não verificada.',
        now()
      )
      RETURNING id INTO v_partner_id;
      v_partner_created := true;
    END IF;

    -- a mesma mensagem do mesmo lead não é registrada duas vezes (envio repetido)
    IF v_partner_created OR NOT EXISTS (
      SELECT 1 FROM public.partner_interactions pi
       WHERE pi.partner_id = v_partner_id
         AND pi.interaction_type = 'note'
         AND pi.actor_member_id IS NULL
         AND pi.summary = v_summary
         AND pi.details IS NOT DISTINCT FROM v_details
    ) THEN
      INSERT INTO public.partner_interactions (partner_id, interaction_type, summary, details, actor_member_id)
      VALUES (v_partner_id, 'note', v_summary, v_details, NULL)
      RETURNING id INTO v_interaction_id;
      UPDATE public.partner_entities SET last_interaction_at = now() WHERE id = v_partner_id;
    END IF;

    IF v_interaction_id IS NOT NULL THEN
      -- aviso a quem gere a plataforma, sem dado de quem pediu; o laço mora no ajudante (2a) para esta função
      -- seguir sem termo de portão no corpo: ela é anônima por desenho e a varredura do #965 tem de enxergá-la
      PERFORM public._notify_partner_lead_received(v_partner_id, v_partner_created, v_door);

      -- vínculo lead -> entidade -> nota, e marcador de origem que a retenção usa (só este caminho grava a ação)
      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
      VALUES (NULL, 'visitor_lead.routed_to_partner_crm', 'visitor_lead', v_lead_id,
        jsonb_build_object('partner_entity_id', v_partner_id, 'partner_created', v_partner_created,
          'partner_interaction_id', v_interaction_id, 'role_interest', v_role));
    END IF;
  END IF;

  -- #1050: the SAME shape on every path (new lead, existing lead, partner routed or not), so an anon caller
  -- cannot use the response to test whether an email is already a lead.
  RETURN jsonb_build_object('success', true, 'lead_id', v_lead_id);
END $function$;

-- ── (3) promoção automática ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.auto_promote_eligible_leads_for_cycle(p_cycle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cycle record;
  v_lead record;
  v_app_id uuid;
  v_first text;
  v_last text;
  v_count integer := 0;
  v_skipped integer := 0;
  v_dedup_skipped integer := 0;
  v_caller_id uuid;
  v_cron_context boolean;
BEGIN
  -- #684: role-GUC discriminator (current_user is always the SECDEF owner under SECDEF).
  v_cron_context := NOT public._request_is_rest_caller();

  IF NOT v_cron_context THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL THEN
      RAISE EXCEPTION 'Unauthorized: not authenticated';
    END IF;
    IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
      RAISE EXCEPTION 'Unauthorized: requires manage_member';
    END IF;
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = p_cycle_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Cycle not found');
  END IF;
  IF v_cycle.status <> 'open' THEN
    RETURN jsonb_build_object('error', 'Cycle is not open: ' || v_cycle.status);
  END IF;

  FOR v_lead IN
    SELECT vl.*
    FROM public.visitor_leads vl
    WHERE vl.status = 'new'
      AND vl.auto_promote_eligible = true
      -- #2782: pedido de capítulo ou de organização nunca vira candidatura, mesmo com a flag true
      AND COALESCE(vl.role_interest, '') NOT IN ('chapter', 'partner')
      AND vl.lgpd_consent = true
      AND NOT EXISTS (
        SELECT 1 FROM public.selection_applications sa
        WHERE sa.cycle_id = p_cycle_id
          AND LOWER(TRIM(sa.email)) = vl.dedupe_email_normalized
      )
    ORDER BY vl.created_at ASC
  LOOP
    BEGIN
      v_first := SPLIT_PART(v_lead.name, ' ', 1);
      v_last := NULLIF(TRIM(SUBSTRING(v_lead.name FROM POSITION(' ' IN v_lead.name) + 1)), '');

      INSERT INTO public.selection_applications (
        cycle_id, applicant_name, first_name, last_name, email, phone, chapter,
        referral_source, referrer_member_id, utm_data, status, created_at, application_date
      ) VALUES (
        p_cycle_id, v_lead.name, v_first, v_last, v_lead.email, v_lead.phone,
        v_lead.chapter_interest,
        COALESCE(v_lead.source, 'lead_promote_cron'),
        v_lead.referrer_member_id,
        v_lead.utm_data,
        'submitted', now(), CURRENT_DATE
      )
      RETURNING id INTO v_app_id;

      UPDATE public.visitor_leads SET
        status = 'promoted', promoted_at = now(), promoted_by = NULL,
        promoted_to_application_id = v_app_id
      WHERE id = v_lead.id;

      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
      VALUES (
        v_caller_id, 'visitor_lead.auto_promoted', 'visitor_lead', v_lead.id,
        jsonb_build_object('application_id', v_app_id, 'cycle_id', p_cycle_id, 'via', 'cron'),
        jsonb_strip_nulls(jsonb_build_object('lead_email', v_lead.email))
      );

      v_count := v_count + 1;
    EXCEPTION
      WHEN unique_violation THEN
        v_dedup_skipped := v_dedup_skipped + 1;
      WHEN OTHERS THEN
        v_skipped := v_skipped + 1;
        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
        VALUES (
          v_caller_id, 'visitor_lead.auto_promote_failed', 'visitor_lead', v_lead.id,
          jsonb_build_object('error', SQLERRM),
          jsonb_build_object('lead_email', v_lead.email, 'cycle_id', p_cycle_id)
        );
    END;
  END LOOP;

  UPDATE public.selection_cycles SET leads_auto_promoted_at = now() WHERE id = p_cycle_id;

  RETURN jsonb_build_object(
    'cycle_id', p_cycle_id,
    'cycle_code', v_cycle.cycle_code,
    'promoted', v_count,
    'dedup_skipped', v_dedup_skipped,
    'errors', v_skipped,
    'completed_at', now()
  );
END;
$function$;

-- ── (4) varredura de retenção ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._data_retention_sweep(p_dry_run boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_job_name  constant text := 'data-retention-sweep-daily';
  v_policy    record;
  v_cutoff    timestamptz;
  v_affected  int;
  v_handled   boolean;
  v_reason    text;
  v_results   jsonb := '[]'::jsonb;
  v_total     int := 0;
  v_uncovered int := 0;
  v_ids       uuid[];
BEGIN
  -- Percorre TODAS as politicas ativas, inclusive as que nao sao desta varredura. Uma saida
  -- que so lista o que foi executado nao distingue "nada a apagar" de "ninguem executa" --
  -- que era exatamente o estado anterior desta tabela.
  FOR v_policy IN
    SELECT * FROM public.data_retention_policy WHERE is_active = true ORDER BY table_name
  LOOP
    v_cutoff   := now() - (v_policy.retention_days || ' days')::interval;
    v_affected := 0;
    v_handled  := false;
    v_reason   := NULL;

    IF v_policy.executor IS NULL THEN
      v_reason := 'politica ativa sem executor declarado';
    ELSIF v_policy.executor IS DISTINCT FROM v_job_name THEN
      v_reason := 'executada pelo caminho dedicado ' || v_policy.executor;

    -- ── ramos desta varredura. O qualificador de cada um vem da DESCRICAO da linha. ──
    ELSIF v_policy.cleanup_type = 'delete' AND v_policy.table_name = 'notifications' THEN
      -- descricao: "Notificacoes lidas com mais de 6 meses" -> o qualificador declarado e "lidas".
      -- is_read e read_at sao perfeitamente consistentes (0 divergencias em 6.671 linhas, 16/08);
      -- is_read e o flag que a aplicacao escreve. A funcao aposentada citava `read`, que nao existe.
      IF p_dry_run THEN
        SELECT count(*) INTO v_affected FROM public.notifications
         WHERE is_read = true AND created_at < v_cutoff;
      ELSE
        DELETE FROM public.notifications WHERE is_read = true AND created_at < v_cutoff;
        GET DIAGNOSTICS v_affected = ROW_COUNT;
      END IF;
      v_handled := true;

    ELSIF v_policy.cleanup_type = 'delete' AND v_policy.table_name = 'data_anomaly_log' THEN
      -- descricao: "Logs de anomalia com mais de 1 ano" -> SEM qualificador de resolucao, e
      -- nenhum e inventado aqui. A funcao aposentada exigia status = 'resolved' sobre uma tabela
      -- que nao tem status; e as 165 linhas vivas tem fixed_at e auto_fixed ambos zerados, entao
      -- qualquer qualificador de resolucao apagaria nada e pareceria politica cumprida.
      IF p_dry_run THEN
        SELECT count(*) INTO v_affected FROM public.data_anomaly_log WHERE detected_at < v_cutoff;
      ELSE
        DELETE FROM public.data_anomaly_log WHERE detected_at < v_cutoff;
        GET DIAGNOSTICS v_affected = ROW_COUNT;
      END IF;
      v_handled := true;

    ELSIF v_policy.cleanup_type = 'delete' AND v_policy.table_name = 'visitor_leads' THEN
      -- descricao: "unconverted visitor leads auto-deleted after 90 days" -> o qualificador
      -- declarado e "unconverted", isto e, sem promocao a candidatura (promoted_at IS NULL);
      -- lead dispensado continua sendo lead nao convertido. Esta politica NUNCA teve ramo.
      IF p_dry_run THEN
        SELECT count(*) INTO v_affected FROM public.visitor_leads
         WHERE promoted_at IS NULL AND created_at < v_cutoff;
      ELSE
        DELETE FROM public.visitor_leads WHERE promoted_at IS NULL AND created_at < v_cutoff;
        GET DIAGNOSTICS v_affected = ROW_COUNT;
      END IF;
      v_handled := true;

    -- ── #2782: pedido de capitulo ou de organizacao pelo formulario do site ──
    -- O qualificador de origem dos dois ramos e o MARCADOR que so capture_visitor_lead grava: a linha de
    -- admin_audit_log 'visitor_lead.routed_to_partner_crm' (append-only), com partner_created para a entidade e
    -- partner_interaction_id para a nota. Entidade criada por outro caminho (admin_manage_partner_entity, MCP)
    -- nao tem o marcador e nunca entra aqui, qualquer que seja o status. Cada ramo calcula o conjunto UMA vez,
    -- e a contagem seca e a corrida real usam o mesmo conjunto.
    ELSIF v_policy.cleanup_type = 'anonymize' AND v_policy.table_name = 'partner_interactions' THEN
      -- descricao: "nota do formulario do site (...) anonimizada no mesmo prazo do lead, quando a entidade criada
      -- pelo formulario segue prospect sem edicao nem interacao nova" -> o dado de quem pediu sai de details.
      SELECT COALESCE(array_agg(pi.id), '{}') INTO v_ids
        FROM public.partner_interactions pi
        JOIN public.partner_entities pe ON pe.id = pi.partner_id
       WHERE pi.details IS NOT NULL
         AND EXISTS (SELECT 1 FROM public.admin_audit_log a
                      WHERE a.action = 'visitor_lead.routed_to_partner_crm'
                        AND a.changes->>'partner_interaction_id' = pi.id::text)
         AND EXISTS (SELECT 1 FROM public.admin_audit_log a
                      WHERE a.action = 'visitor_lead.routed_to_partner_crm'
                        AND a.changes->>'partner_created' = 'true'
                        AND a.changes->>'partner_entity_id' = pe.id::text)
         AND pe.status = 'prospect'
         AND COALESCE(pe.updated_at, pe.created_at) < v_cutoff
         AND NOT EXISTS (SELECT 1 FROM public.partner_interactions i
                          WHERE i.partner_id = pe.id AND i.created_at >= v_cutoff);
      IF p_dry_run THEN
        v_affected := cardinality(v_ids);
      ELSE
        UPDATE public.partner_interactions
           SET details = NULL,
               summary = summary || ' [dados de quem pediu removidos em '
                 || to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD')
                 || ', retenção de ' || v_policy.retention_days || ' dias]'
         WHERE id = ANY (v_ids);
        GET DIAGNOSTICS v_affected = ROW_COUNT;
      END IF;
      v_handled := true;

    ELSIF v_policy.cleanup_type = 'delete' AND v_policy.table_name = 'partner_entities' THEN
      -- descricao: "entidade criada pelo formulario do site que ficou casca (...)" -> alem do marcador e do
      -- prazo: toda interacao dela e nota do formulario ja anonimizada (o ramo de partner_interactions roda depois
      -- deste, ORDER BY table_name, entao a casca sai na corrida seguinte a anonimizacao) e nenhuma outra tabela
      -- aponta para ela. governance_documents nao tem ON DELETE: sem esta checagem o DELETE derrubaria a varredura.
      SELECT COALESCE(array_agg(pe.id), '{}') INTO v_ids
        FROM public.partner_entities pe
       WHERE EXISTS (SELECT 1 FROM public.admin_audit_log a
                      WHERE a.action = 'visitor_lead.routed_to_partner_crm'
                        AND a.changes->>'partner_created' = 'true'
                        AND a.changes->>'partner_entity_id' = pe.id::text)
         AND pe.status = 'prospect'
         AND COALESCE(pe.updated_at, pe.created_at) < v_cutoff
         AND NOT EXISTS (SELECT 1 FROM public.partner_interactions i
                          WHERE i.partner_id = pe.id AND i.created_at >= v_cutoff)
         AND NOT EXISTS (SELECT 1 FROM public.partner_interactions i
                          WHERE i.partner_id = pe.id
                            AND (i.details IS NOT NULL
                                 OR NOT EXISTS (SELECT 1 FROM public.admin_audit_log a
                                                 WHERE a.action = 'visitor_lead.routed_to_partner_crm'
                                                   AND a.changes->>'partner_interaction_id' = i.id::text)))
         AND NOT EXISTS (SELECT 1 FROM public.partner_attachments x WHERE x.partner_entity_id = pe.id)
         AND NOT EXISTS (SELECT 1 FROM public.partner_cards x WHERE x.partner_entity_id = pe.id)
         AND NOT EXISTS (SELECT 1 FROM public.board_items x WHERE x.source_partner_id = pe.id)
         AND NOT EXISTS (SELECT 1 FROM public.initiatives x WHERE x.origin_partner_entity_id = pe.id)
         AND NOT EXISTS (SELECT 1 FROM public.governance_documents x WHERE x.partner_entity_id = pe.id);
      IF p_dry_run THEN
        v_affected := cardinality(v_ids);
      ELSE
        DELETE FROM public.partner_entities WHERE id = ANY (v_ids);
        GET DIAGNOSTICS v_affected = ROW_COUNT;
      END IF;
      v_handled := true;

    ELSE
      v_reason := 'sem ramo implementado nesta varredura para ' || v_policy.cleanup_type;
    END IF;

    v_total := v_total + v_affected;
    IF NOT v_handled AND v_policy.executor IS DISTINCT FROM 'lgpd-anonymize-premember-monthly' THEN
      v_uncovered := v_uncovered + 1;
    END IF;

    v_results := v_results || jsonb_build_object(
      'table',    v_policy.table_name,
      'type',     v_policy.cleanup_type,
      'days',     v_policy.retention_days,
      'cutoff',   v_cutoff,
      'executor', v_policy.executor,
      'handled',  v_handled,
      'affected', CASE WHEN v_handled THEN v_affected ELSE NULL END,
      'reason',   v_reason
    );
  END LOOP;

  RETURN jsonb_build_object(
    'success',           true,
    'dry_run',           p_dry_run,
    'policies',          v_results,
    'affected_total',    v_total,
    'uncovered_policies', v_uncovered,
    'executed_at',       now()
  );
END;
$function$;

-- ── (5) políticas de retenção, com o prazo do lead ───────────────────────────
-- resolvidas por (tabela, tipo), nunca por id gerado; reexecutar não duplica
INSERT INTO public.data_retention_policy (table_name, retention_days, cleanup_type, description, is_active, executor)
SELECT v.t, lead.retention_days, v.c, v.d, true, 'data-retention-sweep-daily'
  FROM (VALUES
    ('partner_interactions', 'anonymize',
     'LGPD (#2782): nota do formulário do site (nome, e-mail, telefone e mensagem de quem pediu um capítulo ou uma parceria) anonimizada no mesmo prazo do lead, quando a entidade criada pelo formulário segue prospect sem edição nem interação nova.'),
    ('partner_entities', 'delete',
     'LGPD (#2782): entidade criada pelo formulário do site que ficou casca (prospect, sem edição nem interação no prazo, só notas do formulário já anonimizadas e nenhum outro vínculo) é apagada.')
  ) AS v(t, c, d)
  CROSS JOIN (SELECT r.retention_days FROM public.data_retention_policy r
               WHERE r.table_name = 'visitor_leads' AND r.cleanup_type = 'delete' AND r.is_active) AS lead
 WHERE NOT EXISTS (SELECT 1 FROM public.data_retention_policy p WHERE p.table_name = v.t AND p.cleanup_type = v.c);

NOTIFY pgrst, 'reload schema';

-- ── pós-condição ─────────────────────────────────────────────────────────────
DO $postcondition$
DECLARE
  v_dry  jsonb;
  v_pol  jsonb;
  v_n    int;
BEGIN
  IF public._delivery_mode_for('partner_lead_received') IS DISTINCT FROM 'transactional_immediate'
     OR public._delivery_mode_for('certificate_revoked') IS DISTINCT FROM 'suppress'
     OR public._delivery_mode_for('tipo_que_nao_existe_2782') IS DISTINCT FROM 'digest_weekly' THEN
    RAISE EXCEPTION '#2782: o catálogo de entrega não ficou como esperado';
  END IF;
  -- CREATE OR REPLACE preserva o privilégio: a porta anônima do site continua aberta, o resto continua fechado
  IF NOT has_function_privilege('anon', 'public.capture_visitor_lead(jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.auto_promote_eligible_leads_for_cycle(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public._data_retention_sweep(boolean)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public._data_retention_sweep(boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION '#2782: privilégio fora do esperado';
  END IF;
  -- a captura é anônima por desenho e tem de continuar visível para a varredura do #965 (lista categorizada)
  IF NOT EXISTS (SELECT 1 FROM public._audit_secdef_public_grant_drift() d WHERE d.proname = 'capture_visitor_lead') THEN
    RAISE EXCEPTION '#2782: capture_visitor_lead sumiu da varredura do #965 (lida como se tivesse portão)';
  END IF;
  -- o ajudante do aviso não é chamável de fora nem roda como dono
  IF has_function_privilege('anon', 'public._notify_partner_lead_received(uuid, boolean, text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public._notify_partner_lead_received(uuid, boolean, text)', 'EXECUTE')
     OR (SELECT p.prosecdef FROM pg_proc p
          WHERE p.oid = 'public._notify_partner_lead_received(uuid, boolean, text)'::regprocedure) THEN
    RAISE EXCEPTION '#2782: o ajudante do aviso ficou exposto ou SECURITY DEFINER';
  END IF;
  IF position('NOT IN (''chapter'', ''partner'')' IN
       (SELECT prosrc FROM pg_proc WHERE oid = 'public.auto_promote_eligible_leads_for_cycle(uuid)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '#2782: a promoção automática não pula pedido de parceria';
  END IF;
  -- as duas políticas existem uma vez cada, com o prazo do lead
  SELECT count(*) INTO v_n FROM public.data_retention_policy p
   WHERE p.is_active AND p.executor = 'data-retention-sweep-daily'
     AND (p.table_name, p.cleanup_type) IN (('partner_interactions', 'anonymize'), ('partner_entities', 'delete'))
     AND p.retention_days = (SELECT r.retention_days FROM public.data_retention_policy r
                              WHERE r.table_name = 'visitor_leads' AND r.cleanup_type = 'delete' AND r.is_active);
  IF v_n <> 2 THEN
    RAISE EXCEPTION '#2782: esperava 2 políticas novas com o prazo do lead, achei %', v_n;
  END IF;
  -- a contagem seca executa os dois ramos, e aplicar não toca nada hoje (nenhuma entidade tem o marcador)
  v_dry := public._data_retention_sweep(true);
  v_n := 0;
  FOR v_pol IN SELECT e FROM jsonb_array_elements(v_dry->'policies') e
                WHERE e->>'table' IN ('partner_interactions', 'partner_entities') LOOP
    IF (v_pol->>'handled')::boolean IS NOT TRUE OR (v_pol->>'affected')::int IS DISTINCT FROM 0 THEN
      RAISE EXCEPTION '#2782: a varredura seca não executou % como esperado: %', v_pol->>'table', v_pol;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  IF v_n <> 2 THEN
    RAISE EXCEPTION '#2782: a varredura seca devolveu % das 2 políticas novas', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public._audit_retention_policy_coverage() c
   WHERE c.politica IN ('partner_interactions/anonymize', 'partner_entities/delete') AND c.coberta;
  IF v_n <> 2 THEN
    RAISE EXCEPTION '#2782: as duas políticas novas não ficaram cobertas pelo auditor (%)', v_n;
  END IF;
END
$postcondition$;
