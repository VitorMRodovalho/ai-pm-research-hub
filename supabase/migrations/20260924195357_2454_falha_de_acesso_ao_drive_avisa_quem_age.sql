-- ============================================================================
-- #2454 — falha de acesso ao Drive avisa quem pode agir
-- ============================================================================
--
-- WHAT: um gatilho nas duas tabelas de concessao (drive_membership_grants e drive_curation_grants),
--   disparado UMA vez na passagem para 'failed', classifica o erro da API do Drive:
--   * destinatario (e-mail sem conta Google; dominio que bloqueia receber de fora) -> aviso a
--     PROPRIA pessoa para cadastrar um e-mail Google no perfil (a reconciliacao ja concede tambem aos
--     e-mails secundarios, entao o acesso vem sozinho na rodada seguinte). So se ela nao tiver acesso
--     a mesma pasta por outro e-mail. Na curadoria o parecerista ja e avisado pelo gatilho da #2449.
--   * conta de servico (qualquer outro erro: o Drive e sempre o do Nucleo, entao a conta de servico
--     deveria conseguir) -> aviso imediato a quem tem manage_platform: acao do administrador do
--     Workspace.
-- WHY: medido em 24/09/2026, drive_membership_grants tinha 110 granted e 3 failed, as 3 do lado do
--   destinatario (2 x 403 sem conta Google, 1 x 400 dominio bloqueia), e ninguem era avisado: o
--   'succeeded' do cron e so o disparo HTTP. As 3 pessoas tem login e 1 e-mail cada, e nenhuma tinha
--   acesso a pasta por outro e-mail.
-- DEDUPE: upsert_membership_drive_grants mantem a linha 'failed' (so atualiza carimbos), entao o
--   gatilho na TRANSICAO avisa uma vez; as 3 falhas ja existentes sao avisadas uma vez aqui.
-- ROLLBACK: DROP dos dois gatilhos e das funcoes; reaplicar _delivery_mode_for anterior.
-- CROSS-REF: #2454 · #2449 · #2444 · ADR-0094 · ADR-0022
-- ============================================================================

-- (1) Classificacao do erro da API do Drive -------------------------------------------------
CREATE OR REPLACE FUNCTION public._drive_grant_failure_class(p_api_error jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT CASE
    WHEN coalesce(p_api_error->>'message', p_api_error::text, '') ~* 'do(es)? not have a Google Account'
      THEN 'recipient_no_google'
    WHEN coalesce(p_api_error->>'message', p_api_error::text, '') ~* 'disabled the ability to receive items|cannot share .* outside'
      THEN 'recipient_domain_blocked'
    ELSE 'service_account'
  END;
$fn$;

-- (2) Aviso de acordo com a classe ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._notify_drive_grant_failure(
  p_table text, p_grant_id uuid, p_member_id uuid, p_folder_id text, p_folder_url text,
  p_api_error jsonb, p_context text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_class text := public._drive_grant_failure_class(p_api_error);
  v_gp    record;
  v_why   text;
BEGIN
  IF v_class IN ('recipient_no_google', 'recipient_domain_blocked') THEN
    -- Na curadoria o parecerista ja e avisado pelo gatilho da #2449.
    IF p_table <> 'drive_membership_grants' OR p_member_id IS NULL THEN RETURN v_class; END IF;
    -- Tem acesso a mesma pasta por outro e-mail: nao ha o que fazer.
    IF EXISTS (SELECT 1 FROM public.drive_membership_grants g
                WHERE g.grantee_member_id = p_member_id AND g.drive_folder_id = p_folder_id
                  AND g.status = 'granted') THEN
      RETURN v_class;
    END IF;
    v_why := CASE v_class
      WHEN 'recipient_no_google' THEN 'o e-mail cadastrado não tem conta Google, e o Drive só compartilha com conta Google'
      ELSE 'o domínio do seu e-mail bloqueia receber arquivos compartilhados de fora' END;
    PERFORM public.create_notification(
      p_member_id,
      'drive_access_action_needed',
      'Seu acesso à pasta da iniciativa não foi concedido',
      'Não conseguimos te dar acesso à pasta do Drive de ' || coalesce(p_context, 'sua iniciativa') || ': ' || v_why
        || '. Cadastre um e-mail Google (Gmail ou conta Google do trabalho) no seu perfil, em E-mails; o acesso é concedido sozinho na verificação diária seguinte.',
      '/profile',
      NULL,
      NULL
    );
  ELSE
    FOR v_gp IN
      SELECT m.id FROM public.members m
       WHERE m.member_status = 'active' AND m.auth_id IS NOT NULL
         AND public.can_by_member(m.id, 'manage_platform')
    LOOP
      PERFORM public.create_notification(
        v_gp.id,
        'drive_access_admin_needed',
        'Conta de serviço sem permissão no Drive do Núcleo',
        'A concessão de acesso falhou por um motivo que não é do destinatário (' || coalesce(p_context, p_table)
          || '; HTTP ' || coalesce(p_api_error->>'status', '?') || '). Provável falta do papel de organizador '
          || 'da conta de serviço na pasta: ação do administrador do Google Workspace (ADR-0094). Pasta: ' || coalesce(p_folder_url, p_folder_id, '?'),
        '/admin',
        NULL,
        NULL
      );
    END LOOP;
  END IF;
  RETURN v_class;
END;
$fn$;

-- (3) Gatilhos: uma vez, na passagem para 'failed' --------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_drive_membership_grant_failed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
BEGIN
  IF NEW.status = 'failed' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'failed') THEN
    PERFORM public._notify_drive_grant_failure(
      'drive_membership_grants', NEW.id, NEW.grantee_member_id, NEW.drive_folder_id, NEW.drive_folder_url,
      NEW.api_error, (SELECT i.title FROM public.initiatives i WHERE i.id = NEW.initiative_id));
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.trg_drive_curation_grant_failed_escalation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
BEGIN
  IF NEW.status = 'failed' AND OLD.status IS DISTINCT FROM 'failed' THEN
    PERFORM public._notify_drive_grant_failure(
      'drive_curation_grants', NEW.id, NEW.grantee_member_id, NEW.drive_file_id, NEW.drive_file_url,
      NEW.api_error, 'curadoria de "' || coalesce((SELECT bi.title FROM public.board_items bi WHERE bi.id = NEW.board_item_id), '?') || '"');
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_drive_membership_grant_failed ON public.drive_membership_grants;
CREATE TRIGGER trg_drive_membership_grant_failed
  AFTER INSERT OR UPDATE OF status ON public.drive_membership_grants
  FOR EACH ROW EXECUTE FUNCTION public.trg_drive_membership_grant_failed();

DROP TRIGGER IF EXISTS trg_drive_curation_grant_failed_escalation ON public.drive_curation_grants;
CREATE TRIGGER trg_drive_curation_grant_failed_escalation
  AFTER UPDATE OF status ON public.drive_curation_grants
  FOR EACH ROW EXECUTE FUNCTION public.trg_drive_curation_grant_failed_escalation();

REVOKE ALL ON FUNCTION public._notify_drive_grant_failure(text, uuid, uuid, text, text, jsonb, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_drive_membership_grant_failed() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_drive_curation_grant_failed_escalation() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._notify_drive_grant_failure(text, uuid, uuid, text, text, jsonb, text) TO service_role;

-- (4) Os dois tipos novos, catalogados como imediatos (ADR-0022) ------------------------------
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
    -- #2444 (2026-09-24): rodizio de pareceristas da curadoria. Imediato de proposito: a
    -- designacao e o lembrete sao o que da dono ao parecer; o digest semanal chegaria depois do
    -- prazo de 7 dias. O vencido vai para quem gere a plataforma, tambem imediato: e decisao.
    WHEN 'curation_review_assigned'       THEN 'transactional_immediate'
    WHEN 'curation_review_overdue'        THEN 'transactional_immediate'
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

-- (5) As falhas que ja existem: aviso uma vez -------------------------------------------------
SELECT public._notify_drive_grant_failure(
         'drive_membership_grants', g.id, g.grantee_member_id, g.drive_folder_id, g.drive_folder_url,
         g.api_error, (SELECT i.title FROM public.initiatives i WHERE i.id = g.initiative_id))
  FROM public.drive_membership_grants g
 WHERE g.status = 'failed';
