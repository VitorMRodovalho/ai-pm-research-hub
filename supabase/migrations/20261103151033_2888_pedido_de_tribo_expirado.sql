-- Onboarding, onda 0, PR-2 (#2888, #2885, #2891; #2892 item 2). Pedido de tribo que expira:
--   1. process_tribe_request_nudges, parte 2: avisa quem pediu (tipo novo tribe_request_expired, marca propria
--      invitee_notified_at), e o aviso ao GP (tribe_request_expired_gp) passa a dizer quem pediu e quando, com link
--      para /admin/members/<id>;
--   2. get_my_tribe_request_context ganha o campo expired, para o painel distinguir "pedido expirado" de "nunca pediu";
--   3. list_tribe_pending_requests deixa de listar o pedido vencido que o job da hora cheia ainda nao marcou;
--   4. _delivery_mode_for cataloga os tipos do fluxo, e os INSERTs da parte 1 e da parte 2 leem do catalogo;
--   5. get_onboarding_contacts, leitora nova para authenticated, devolve so o nome de exibicao dos contatos do
--      onboarding, lidos da chave onboarding_contacts de platform_settings (decisao do GP de 01/11/2026, P1 = a).
--
-- Os corpos de process_tribe_request_nudges, get_my_tribe_request_context e list_tribe_pending_requests partem das
-- capturas mais novas (20260805000395, 20261008235211 e 20260805000218), com so as mudancas desta PR; o md5 do corpo
-- vivo e conferido contra essas capturas antes do apply. _delivery_mode_for parte de 20261102223830, com os tipos
-- novos antes do ELSE. CREATE OR REPLACE mantem a ACL de cada funcao.
--
-- A chave onboarding_contacts guarda member_id, nunca nome: trocar ou acrescentar um contato e admin_update_setting em
-- /admin/settings (motivo obrigatorio e trilha em admin_audit_log), sem PR, e nenhum nome entra no repositorio. A
-- semeadura abaixo poe so o GP (o unico gestor ativo), ate o segundo contato confirmar.
--
-- ROLLBACK: reaplicar os quatro corpos das capturas citadas acima; DROP FUNCTION public.get_onboarding_contacts();
--           DELETE FROM public.platform_settings WHERE key = 'onboarding_contacts'.

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
    ELSE 'digest_weekly'
  END;
$function$;

CREATE OR REPLACE FUNCTION public.process_tribe_request_nudges(p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_run_at timestamptz := now();
  v_leader_due int := 0;
  v_gp_due int := 0;
  v_leader_notifs int := 0;
  v_gp_notifs int := 0;
  v_invitee_due int := 0;
  v_invitee_notifs int := 0;
BEGIN
  -- ── Part 1: D-2 leader nudge ──
  -- Due cohort: pending research_tribe self-requests within 2 days of expiry, not yet nudged.
  SELECT count(*) INTO v_leader_due
  FROM public.initiative_invitations ii
  JOIN public.initiatives i ON i.id = ii.initiative_id AND i.kind = 'research_tribe'
  WHERE ii.status = 'pending'
    AND (ii.metadata->>'leader_nudged_at') IS NULL
    AND ii.expires_at > v_run_at
    AND ii.expires_at <= v_run_at + interval '2 days';

  IF NOT p_dry_run AND v_leader_due > 0 THEN
    WITH due AS (
      SELECT ii.id AS invitation_id, ii.initiative_id, i.legacy_tribe_id, i.title
      FROM public.initiative_invitations ii
      JOIN public.initiatives i ON i.id = ii.initiative_id AND i.kind = 'research_tribe'
      WHERE ii.status = 'pending'
        AND (ii.metadata->>'leader_nudged_at') IS NULL
        AND ii.expires_at > v_run_at
        AND ii.expires_at <= v_run_at + interval '2 days'
    ), ins AS (
      INSERT INTO public.notifications
        (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
      SELECT m2.id, 'tribe_request_nudge',
             'Pedido de entrada na tribo perto de expirar',
             'Um pedido de entrada na tribo ' || d.title || ' aguarda sua revisão e expira em breve. Aprove ou recuse em /tribe/' || d.legacy_tribe_id::text || '?tab=members.',
             '/tribe/' || d.legacy_tribe_id::text || '?tab=members',
             'initiative_invitation', d.invitation_id, public._delivery_mode_for('tribe_request_nudge')
      FROM due d
      JOIN public.engagements e ON e.initiative_id = d.initiative_id
        AND e.kind = 'volunteer' AND e.role = 'leader' AND e.status = 'active'
      JOIN public.members m2 ON m2.person_id = e.person_id
      RETURNING 1
    )
    SELECT count(*) INTO v_leader_notifs FROM ins;

    -- Mark ALL due (even leaderless tribes) so we nudge at most once; the GP fallback catches a
    -- leaderless tribe at expiry.
    UPDATE public.initiative_invitations ii
       SET metadata = ii.metadata || jsonb_build_object('leader_nudged_at', v_run_at)
    FROM public.initiatives i
    WHERE ii.initiative_id = i.id AND i.kind = 'research_tribe'
      AND ii.status = 'pending'
      AND (ii.metadata->>'leader_nudged_at') IS NULL
      AND ii.expires_at > v_run_at
      AND ii.expires_at <= v_run_at + interval '2 days';
  END IF;

  -- ── Part 2: expiry ──
  -- 2a. GP fallback. Recently-expired (last 3 days) research_tribe requests with no GP fallback yet. The 3-day bound
  -- prevents a backfill blast on ship; the metadata flag prevents repeats.
  -- Onda 0 PR-2 (#2885): o aviso diz quem pediu e quando, e leva a ficha da pessoa, porque o pedido expirado nao
  -- aparece na aba da tribo. A mensagem do pedido fica fora: o aviso tambem sai por e-mail, quem e quando bastam
  -- para agir, e a mensagem segue visivel na plataforma.
  SELECT count(*) INTO v_gp_due
  FROM public.initiative_invitations ii
  JOIN public.initiatives i ON i.id = ii.initiative_id AND i.kind = 'research_tribe'
  WHERE ii.status = 'expired'
    AND (ii.metadata->>'gp_fallback_at') IS NULL
    AND ii.expires_at > v_run_at - interval '3 days';

  IF NOT p_dry_run AND v_gp_due > 0 THEN
    WITH due AS (
      SELECT ii.id AS invitation_id, ii.invitee_member_id, ii.created_at AS requested_at, i.title
      FROM public.initiative_invitations ii
      JOIN public.initiatives i ON i.id = ii.initiative_id AND i.kind = 'research_tribe'
      WHERE ii.status = 'expired'
        AND (ii.metadata->>'gp_fallback_at') IS NULL
        AND ii.expires_at > v_run_at - interval '3 days'
    ), ins AS (
      INSERT INTO public.notifications
        (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
      SELECT m.id, 'tribe_request_expired_gp',
             'Pedido de tribo de ' || coalesce(mi.name, 'um voluntário') || ' expirou sem revisão',
             coalesce(mi.name, 'Um voluntário') || ' pediu para entrar na tribo ' || d.title || ' em '
               || to_char(d.requested_at AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY')
               || ', e o pedido expirou sem o líder revisar. Veja a pessoa em /admin/members/' || d.invitee_member_id::text || '.',
             '/admin/members/' || d.invitee_member_id::text,
             'initiative_invitation', d.invitation_id, public._delivery_mode_for('tribe_request_expired_gp')
      FROM due d
      LEFT JOIN public.members mi ON mi.id = d.invitee_member_id
      -- Fan-out: 1 fallback por GP (manager). Espelha detect_stuck_selection_funnel (ADR-0011 Amd A).
      CROSS JOIN public.members m
      WHERE m.operational_role = 'manager' AND m.member_status = 'active'
      RETURNING 1
    )
    SELECT count(*) INTO v_gp_notifs FROM ins;

    UPDATE public.initiative_invitations ii
       SET metadata = ii.metadata || jsonb_build_object('gp_fallback_at', v_run_at)
    FROM public.initiatives i
    WHERE ii.initiative_id = i.id AND i.kind = 'research_tribe'
      AND ii.status = 'expired'
      AND (ii.metadata->>'gp_fallback_at') IS NULL
      AND ii.expires_at > v_run_at - interval '3 days';
  END IF;

  -- 2b. Onda 0 PR-2 (#2888): aviso a quem pediu. So no pedido do proprio voluntario (inviter = invitee), com marca
  -- propria, separada da 2a. A mesma janela de 3 dias: no apply, so os pedidos expirados nos ultimos 3 dias recebem
  -- o aviso. Marca todo o lote devido, como a parte 1, para avisar no maximo uma vez; quem deixou de ser membro ativo
  -- nao recebe.
  SELECT count(*) INTO v_invitee_due
  FROM public.initiative_invitations ii
  JOIN public.initiatives i ON i.id = ii.initiative_id AND i.kind = 'research_tribe'
  WHERE ii.status = 'expired'
    AND ii.inviter_member_id = ii.invitee_member_id
    AND (ii.metadata->>'invitee_notified_at') IS NULL
    AND ii.expires_at > v_run_at - interval '3 days';

  IF NOT p_dry_run AND v_invitee_due > 0 THEN
    WITH due AS (
      SELECT ii.id AS invitation_id, ii.invitee_member_id, i.title
      FROM public.initiative_invitations ii
      JOIN public.initiatives i ON i.id = ii.initiative_id AND i.kind = 'research_tribe'
      WHERE ii.status = 'expired'
        AND ii.inviter_member_id = ii.invitee_member_id
        AND (ii.metadata->>'invitee_notified_at') IS NULL
        AND ii.expires_at > v_run_at - interval '3 days'
    ), ins AS (
      INSERT INTO public.notifications
        (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
      SELECT d.invitee_member_id, 'tribe_request_expired',
             'Seu pedido de tribo passou do prazo',
             'Seu pedido para a tribo ' || d.title || ' passou do prazo sem resposta do líder. Isso não é uma recusa. No seu painel, você pode pedir de novo, escolher outra tribo ou falar com o time de onboarding.',
             '/workspace',
             'initiative_invitation', d.invitation_id, public._delivery_mode_for('tribe_request_expired')
      FROM due d
      JOIN public.members mi ON mi.id = d.invitee_member_id AND mi.is_active = true
      RETURNING 1
    )
    SELECT count(*) INTO v_invitee_notifs FROM ins;

    UPDATE public.initiative_invitations ii
       SET metadata = ii.metadata || jsonb_build_object('invitee_notified_at', v_run_at)
    FROM public.initiatives i
    WHERE ii.initiative_id = i.id AND i.kind = 'research_tribe'
      AND ii.status = 'expired'
      AND ii.inviter_member_id = ii.invitee_member_id
      AND (ii.metadata->>'invitee_notified_at') IS NULL
      AND ii.expires_at > v_run_at - interval '3 days';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'leader_nudge_due', v_leader_due,
    'leader_notifs_inserted', v_leader_notifs,
    'gp_fallback_due', v_gp_due,
    'gp_notifs_inserted', v_gp_notifs,
    'invitee_notice_due', v_invitee_due,
    'invitee_notifs_inserted', v_invitee_notifs,
    'run_at', v_run_at
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_tribe_request_context()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_person_id uuid;
  v_member_status text;
  v_is_active boolean;
  v_tribe_id integer;
  v_has_tribe_engagement boolean;
  v_eligible boolean;
  v_reason text;
  v_current_tribe_title text;
  v_current_tribe_id integer;
  v_current_tribe_initiative_id uuid;
  v_pending jsonb;
  v_expired jsonb;
  v_tribes jsonb;
  v_deadline timestamptz;
  v_window_closed boolean;
  v_can_self_leave boolean;
  v_kind_required text[];
  v_active_vol_count integer;
BEGIN
  SELECT m.id, m.person_id, m.member_status, m.is_active, m.tribe_id
    INTO v_member_id, v_person_id, v_member_status, v_is_active, v_tribe_id
    FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('eligible', false, 'ineligible_reason', 'no_member', 'current_tribe_title', NULL, 'current_tribe_id', NULL, 'current_tribe_initiative_id', NULL, 'can_self_leave', NULL, 'pending', NULL, 'expired', NULL, 'tribes', '[]'::jsonb, 'deadline', NULL);
  END IF;

  -- Deadline SSOT (absent/null = open window). Surfaced in the payload + drives the window_closed reason.
  v_deadline := (SELECT (value #>> '{}')::timestamptz FROM public.platform_settings WHERE key = 'tribe_request_deadline');
  v_window_closed := v_deadline IS NOT NULL AND now() > v_deadline;

  -- caller's pending research_tribe self-request (invitee == me), if any.
  -- #1255: invitation_id added so the FE can cancel this exact pending request.
  SELECT to_jsonb(p) INTO v_pending FROM (
    SELECT ii.id AS invitation_id, i.legacy_tribe_id AS tribe_id, i.title, ii.message, ii.created_at, ii.expires_at
    FROM public.initiative_invitations ii
    JOIN public.initiatives i ON i.id = ii.initiative_id AND i.kind = 'research_tribe'
    WHERE ii.invitee_member_id = v_member_id AND ii.status = 'pending'
    ORDER BY ii.created_at DESC
    LIMIT 1
  ) p;

  -- already in a tribe via an active engagement?
  v_has_tribe_engagement := EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id AND i.kind = 'research_tribe'
    WHERE e.person_id = v_person_id AND e.kind = 'volunteer' AND e.status = 'active'
  );

  -- Onda 0 PR-2 (#2888): o ultimo pedido do proprio voluntario, se ele EXPIROU ha ate 14 dias, para o painel mostrar
  -- "pedido expirado" em vez do seletor sem explicacao. So sem pendente e sem tribo, e so quando o pedido mais novo
  -- e o expirado: um pedido posterior (cancelado, recusado, aceito) encerra o assunto. Mesmo formato do pending.
  IF v_pending IS NULL AND v_tribe_id IS NULL AND NOT v_has_tribe_engagement THEN
    SELECT to_jsonb(x) - 'status' INTO v_expired FROM (
      SELECT ii.id AS invitation_id, i.legacy_tribe_id AS tribe_id, i.title, ii.message, ii.created_at, ii.expires_at,
             ii.status
      FROM public.initiative_invitations ii
      JOIN public.initiatives i ON i.id = ii.initiative_id AND i.kind = 'research_tribe'
      WHERE ii.invitee_member_id = v_member_id AND ii.inviter_member_id = v_member_id
      ORDER BY ii.created_at DESC
      LIMIT 1
    ) x
    WHERE x.status = 'expired' AND x.expires_at > now() - interval '14 days';
  END IF;

  -- eligible to self-request: active, termed (not pre-onboarding), no tribe yet (mirrors request_tribe_assignment)
  v_eligible := v_is_active IS TRUE
    AND v_tribe_id IS NULL
    AND NOT v_has_tribe_engagement
    AND v_person_id IS NOT NULL
    AND NOT public.member_is_pre_onboarding(v_person_id, v_member_status);

  -- #1139 Item 1: surface WHY when ineligible so the FE renders an explicit empty-state instead of a
  -- blank block. Priority mirrors request_tribe_assignment's guard sequence: inactive → has-tribe → term.
  -- Deadline enforcement: if the window is closed and the caller has no tribe (so they would want to
  -- request), window_closed outranks the term/eligible states — after the deadline there is nothing to
  -- request. has_tribe callers keep their own state (the deadline is about joining, not their membership).
  IF v_window_closed AND v_tribe_id IS NULL AND NOT v_has_tribe_engagement THEN
    v_eligible := false;
    v_reason := 'window_closed';
  ELSIF v_eligible THEN
    v_reason := NULL;
  ELSIF v_person_id IS NULL THEN
    v_reason := 'no_member';
  ELSIF v_is_active IS DISTINCT FROM true THEN
    v_reason := 'inactive';
  ELSIF v_tribe_id IS NOT NULL OR v_has_tribe_engagement THEN
    v_reason := 'has_tribe';
  ELSIF public.member_is_pre_onboarding(v_person_id, v_member_status) THEN
    v_reason := 'pending_term';
  ELSE
    v_reason := 'ineligible';
  END IF;

  -- #1256: for the has_tribe empty-state, prefer the initiative where the caller holds the ACTIVE
  -- volunteer engagement — withdraw_from_initiative requires an active engagement on that initiative,
  -- so the FE's "leave tribe" action targets it. Returns tribe_id + initiative_id + title together.
  IF v_reason = 'has_tribe' THEN
    SELECT i.id, i.legacy_tribe_id, i.title
      INTO v_current_tribe_initiative_id, v_current_tribe_id, v_current_tribe_title
    FROM public.initiatives i
    JOIN public.engagements e ON e.initiative_id = i.id
      AND e.person_id = v_person_id AND e.kind = 'volunteer' AND e.status = 'active'
    WHERE i.kind = 'research_tribe'
    ORDER BY (i.legacy_tribe_id = v_tribe_id) DESC NULLS LAST, e.start_date DESC, e.created_at DESC
    LIMIT 1;

    -- legacy-only fallback: tribe_id set but no active engagement (liaison / stale bridge). Keep the
    -- title for the empty-state; leave initiative_id NULL so the FE hides the self-service leave action.
    IF v_current_tribe_title IS NULL THEN
      SELECT i.title, i.legacy_tribe_id INTO v_current_tribe_title, v_current_tribe_id
      FROM public.initiatives i
      WHERE i.kind = 'research_tribe' AND i.legacy_tribe_id = v_tribe_id
      ORDER BY i.legacy_tribe_id
      LIMIT 1;
    END IF;

    -- #1267: pre-check the sole-volunteer/leader safeguard so the FE routes to the GP BEFORE the reason
    -- form. Mirrors withdraw_from_initiative: if 'volunteer' is a required kind of research_tribe and the
    -- caller is the only active/onboarding volunteer of the tribe, withdraw would block. Only meaningful
    -- when there is an active engagement to leave (initiative_id present); NULL otherwise.
    IF v_current_tribe_initiative_id IS NOT NULL THEN
      SELECT ik.required_engagement_kinds INTO v_kind_required
      FROM public.initiative_kinds ik
      WHERE ik.slug = 'research_tribe';

      IF 'volunteer' = ANY(coalesce(v_kind_required, ARRAY[]::text[])) THEN
        SELECT count(*) INTO v_active_vol_count
        FROM public.engagements e
        WHERE e.initiative_id = v_current_tribe_initiative_id
          AND e.kind = 'volunteer'
          AND e.status IN ('active', 'onboarding');
        v_can_self_leave := v_active_vol_count > 1;
      ELSE
        v_can_self_leave := true;
      END IF;
    END IF;
  END IF;

  -- selectable active research_tribe tribes (single source of truth = initiatives, not static data)
  -- #1877: each option carries its free slots (same formula and cap as the request/approve gates), so the
  -- picker can show them and disable a full tribe BEFORE the person writes the motivation. A tribe flagged
  -- metadata.self_request_closed (e.g. a pilot whose places are filled by a separate process) is not listed.
  SELECT coalesce(
    jsonb_agg(jsonb_build_object(
      'tribe_id', i.legacy_tribe_id,
      'title', i.title,
      'slots_left', greatest(public.tribe_capacity_limit() - (
        SELECT count(*) FROM public.v_tribe_active_members v WHERE v.legacy_tribe_id = i.legacy_tribe_id
      ), 0)
    ) ORDER BY i.legacy_tribe_id),
    '[]'::jsonb
  ) INTO v_tribes
  FROM public.initiatives i
  WHERE i.kind = 'research_tribe' AND i.status = 'active' AND i.legacy_tribe_id IS NOT NULL
    AND (i.metadata->>'self_request_closed')::boolean IS NOT TRUE;

  RETURN jsonb_build_object(
    'eligible', v_eligible,
    'ineligible_reason', v_reason,
    'current_tribe_title', v_current_tribe_title,
    'current_tribe_id', v_current_tribe_id,
    'current_tribe_initiative_id', v_current_tribe_initiative_id,
    'can_self_leave', v_can_self_leave,
    'pending', v_pending,
    'expired', v_expired,
    'tribes', v_tribes,
    'deadline', v_deadline
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_tribe_pending_requests(p_tribe_id integer)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_is_admin boolean;
  v_is_leader boolean;
  v_initiative_id uuid;
  v_results jsonb;
  v_count integer;
BEGIN
  SELECT m.id, m.person_id INTO v_caller_member_id, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT i.id INTO v_initiative_id
  FROM public.initiatives i
  WHERE i.legacy_tribe_id = p_tribe_id AND i.kind = 'research_tribe';
  IF v_initiative_id IS NULL THEN
    RAISE EXCEPTION 'Tribo não encontrada' USING ERRCODE = 'no_data_found';
  END IF;

  -- Authority (Caminho-3 inline-scope, identical to review_tribe_request): GP OR leader of THIS tribe.
  v_is_admin := public.can_by_member(v_caller_member_id, 'manage_member');
  IF NOT v_is_admin THEN
    v_is_leader := EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = v_caller_person_id
        AND e.initiative_id = v_initiative_id
        AND e.kind = 'volunteer'
        AND e.role = 'leader'
        AND e.status = 'active'
    );
    IF NOT v_is_leader THEN
      RAISE EXCEPTION 'Não autorizado: apenas o líder desta tribo ou o GP podem ver os pedidos'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  SELECT
    jsonb_agg(jsonb_build_object(
      'invitation_id', ii.id,
      'invitee_member_id', ii.invitee_member_id,
      'invitee_name', m.name,
      'message', ii.message,
      'created_at', ii.created_at,
      'expires_at', ii.expires_at
    ) ORDER BY ii.created_at DESC),
    count(*)
  INTO v_results, v_count
  FROM public.initiative_invitations ii
  JOIN public.members m ON m.id = ii.invitee_member_id
  WHERE ii.initiative_id = v_initiative_id
    AND ii.status = 'pending'
    -- Onda 0 PR-2 (#2892 item 2): o job que marca 'expired' roda na hora cheia; ate la, o pedido vencido sairia na
    -- fila e a aprovacao falharia com "Pedido expirou" (review_tribe_request recusa expires_at < now()).
    AND ii.expires_at > now()
    AND ii.invitee_member_id = ii.inviter_member_id;  -- self-requests only

  IF v_count > 0 THEN
    PERFORM public.log_pii_access(
      v_caller_member_id,
      ARRAY['name']::text[],
      'list_tribe_pending_requests',
      format('Leader/GP viewing %s pending tribe request(s) for tribe_id=%s', v_count, p_tribe_id)
    );
  END IF;

  RETURN COALESCE(v_results, '[]'::jsonb);
END;
$function$;

-- Onda 0 PR-2 (decisao do GP de 01/11/2026, P1 = a): os nomes dos contatos do onboarding nas telas logadas. Le os
-- member_id da chave onboarding_contacts e devolve, na ordem da chave, SO o nome de exibicao de cada contato que
-- segue membro ativo. Nunca e-mail, telefone ou id: o retorno e uma lista de {name}. Quem nao e membro ativo com login
-- recebe lista vazia. Na onda 2, a mesma leitora passa a ler os vinculos do time de onboarding, e a tela nao muda.
CREATE FUNCTION public.get_onboarding_contacts()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_ids      jsonb;
  v_contacts jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true
  ) THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT ps.value INTO v_ids FROM public.platform_settings ps WHERE ps.key = 'onboarding_contacts';
  IF v_ids IS NULL OR jsonb_typeof(v_ids) <> 'array' THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object('name', m.name) ORDER BY c.ord), '[]'::jsonb)
    INTO v_contacts
    FROM jsonb_array_elements_text(v_ids) WITH ORDINALITY AS c(member_id, ord)
    JOIN public.members m ON m.id::text = c.member_id AND m.is_active = true;

  RETURN v_contacts;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_onboarding_contacts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_onboarding_contacts() TO authenticated, service_role;

COMMENT ON FUNCTION public.get_onboarding_contacts() IS
  'Onda 0 PR-2: nomes de exibicao dos contatos do onboarding (chave onboarding_contacts de platform_settings), so para membro ativo com login. Devolve [{name}], nunca e-mail nem telefone.';

-- A chave guarda member_id, nunca nome. Semeada so com o GP: o unico membro ativo com operational_role manager, o
-- mesmo criterio do fan-out do aviso ao GP acima. Se nao houver exatamente um, a chave nasce vazia e a verificacao
-- depois do apply acusa. ON CONFLICT DO NOTHING: reaplicar nao sobrescreve um contato trocado por admin_update_setting.
INSERT INTO public.platform_settings (key, value, description, change_reason)
SELECT 'onboarding_contacts',
       CASE WHEN count(*) = 1 THEN jsonb_build_array(min(m.id::text)) ELSE '[]'::jsonb END,
       'Contatos do time de onboarding, por member_id, na ordem em que aparecem nas telas logadas. Lidos por get_onboarding_contacts, que devolve so o nome. Para trocar, edite a lista aqui.',
       'Onda 0 PR-2: semeada com o GP ate o segundo contato confirmar.'
  FROM public.members m
 WHERE m.operational_role = 'manager' AND m.member_status = 'active'
ON CONFLICT (key) DO NOTHING;

NOTIFY pgrst, 'reload schema';
