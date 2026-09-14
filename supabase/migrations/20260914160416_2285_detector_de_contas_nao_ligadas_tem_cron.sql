-- #2285: o detector de contas nao ligadas nunca rodou.
--
-- `detect_unlinked_accounts()` nasceu na #2273 e nunca teve quem o acionasse:
-- `SELECT * FROM cron.job WHERE command ILIKE '%detect_unlinked%'` volta vazio contra 71
-- jobs agendados (controle positivo, 14/09). Um detector sem agendamento nao falha, apenas
-- nunca roda.
--
-- E agendar a RPC direto NAO resolveria. O portao dela aceita service_role (via
-- request.jwt.claims) ou can_by_member(auth.uid()). Sob pg_cron a sessao e `postgres`, com
-- os dois nulos, entao a funcao levanta 'Unauthorized: requires manage_platform' na linha 13,
-- antes de ler qualquer coisa (medido). O job falharia em toda execucao, em silencio.
-- Por isso os 71 jobs vivos deste banco nunca chamam RPC com portao: chamam um wrapper.
--
-- Estrutura, igual a dos irmaos (detect_credly_unmapped_cron, detect_agenda_blocks_pending_cron):
--   (1) worker interno  _unlinked_accounts_rows()   - a consulta, sem portao e sem mascara
--   (2) RPC com portao  detect_unlinked_accounts()  - le o worker, mascara, audita (inalterada
--                                                     por fora: mesmo retorno, mesmo portao)
--   (3) wrapper de cron detect_unlinked_accounts_cron() - le o worker, notifica, audita
--   (4) o tipo de notificacao entra no catalogo ADR-0022
--   (5) o agendamento

-- ----------------------------------------------------------------------------
-- (1) Worker interno. Devolve o endereco CRU: quem chama decide mascarar.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._unlinked_accounts_rows()
RETURNS TABLE (
  member_id       uuid,
  email           text,
  member_since    timestamptz,
  member_status   text,
  auth_created_at timestamptz,
  last_sign_in_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp, auth
AS $function$
  SELECT m.id, m.email, m.created_at, m.member_status, u.created_at, u.last_sign_in_at
    FROM public.members m
    JOIN auth.users u
      ON lower(u.email) = lower(COALESCE(
           (SELECT me.email::text FROM public.member_emails me
             WHERE me.member_id = m.id AND me.is_primary IS TRUE LIMIT 1),
           m.email))
   WHERE m.auth_id IS NULL
     AND m.anonymized_at IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.members m2 WHERE m2.auth_id = u.id)
     AND NOT (u.id = ANY(COALESCE(m.secondary_auth_ids, '{}'::uuid[])));
$function$;

-- CREATE FUNCTION nasce com EXECUTE para PUBLIC: este worker entrega endereco cru e nao pode
-- ficar ao alcance de anon nem de authenticated.
REVOKE ALL ON FUNCTION public._unlinked_accounts_rows() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._unlinked_accounts_rows() FROM anon;
REVOKE ALL ON FUNCTION public._unlinked_accounts_rows() FROM authenticated;
GRANT EXECUTE ON FUNCTION public._unlinked_accounts_rows() TO service_role;

-- ----------------------------------------------------------------------------
-- (2) A RPC com portao passa a ler o worker. Portao, auditoria e formato de retorno
--     ficam identicos: o contrato F da #2273 continua valendo palavra por palavra.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.detect_unlinked_accounts()
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp, auth
AS $function$
DECLARE
  v_caller_id uuid;
  v_is_service boolean := (current_setting('request.jwt.claims', true)::jsonb->>'role') IS NOT DISTINCT FROM 'service_role';
  v_rows jsonb;
  v_count int;
BEGIN
  -- Service-role (cron) OU manage_platform. Nao e leitura publica: a lista e um mapa de pessoas
  -- que estao a um passo de entrar, e o e-mail sai mascarado mesmo para quem passa no portao.
  IF NOT v_is_service THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform'::text) THEN
      RAISE EXCEPTION 'Unauthorized: requires manage_platform';
    END IF;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'member_id',     x.member_id,
           'masked_email',  public._mask_email(x.email),
           'member_since',  x.member_since,
           'account_since', x.auth_created_at,
           'last_sign_in',  x.last_sign_in_at,
           'member_status', x.member_status
         ) ORDER BY x.last_sign_in_at DESC NULLS LAST), '[]'::jsonb),
         count(*)
    INTO v_rows, v_count
  FROM public._unlinked_accounts_rows() x;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id, 'platform.unlinked_accounts_detected', 'platform', NULL,
    jsonb_build_object('count', v_count),
    jsonb_build_object('source', 'detect_unlinked_accounts', 'issue', 2273,
                       'via', CASE WHEN v_is_service THEN 'service_role' ELSE 'manage_platform' END)
  );

  RETURN jsonb_build_object('success', true, 'count', v_count, 'members', v_rows);
END;
$function$;

-- ----------------------------------------------------------------------------
-- (3) O wrapper de cron. Sem portao de sessao de proposito: sob pg_cron nao ha JWT, entao
--     auth.uid() e request.jwt.claims sao nulos e qualquer gate de usuario NEGA. A protecao
--     aqui e o ACL (REVOKE abaixo), nao um gate - mesma decisao ja registrada no #1548.
--     `p_dry_run` existe para que o contrato exerca o caminho INTEIRO sem escrever no banco
--     compartilhado nem disparar e-mail a pessoas reais em toda rodada de CI.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.detect_unlinked_accounts_cron(p_dry_run boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp, auth
AS $function$
DECLARE
  v_total     int := 0;
  v_signed_in int := 0;
  v_alvos     int := 0;
  v_inserted  int := 0;
BEGIN
  SELECT count(*)::int,
         count(*) FILTER (WHERE x.last_sign_in_at IS NOT NULL)::int
    INTO v_total, v_signed_in
    FROM public._unlinked_accounts_rows() x;

  -- Quem receberia: mesmo predicado do INSERT, contado antes. Serve ao dry-run e ao retorno.
  SELECT count(*)::int INTO v_alvos
    FROM public.members m
   WHERE m.is_active = true
     AND public.can_by_member(m.id, 'manage_platform')
     AND NOT EXISTS (
       SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = m.id
          AND n.type = 'unlinked_accounts_detected'
          AND n.created_at >= now() - interval '25 days'
     );

  IF v_total > 0 AND NOT p_dry_run THEN
    -- A notificacao carrega CONTAGEM, nunca endereco: o detalhe fica atras do portao de
    -- detect_unlinked_accounts(), que mascara. Janela de 25 dias = lembrete mensal sobre um
    -- cron semanal, de proposito: a serie tem de ser medida toda semana, mas a fila fica
    -- parada por semanas (em 14/09 e 1 conta, e ela e um caso que o GP ja decidiu NAO ligar),
    -- e avisar toda semana sobre decisao ja tomada e como nao avisar.
    INSERT INTO public.notifications (recipient_id, type, title, body, link, delivery_mode, created_at)
    SELECT m.id,
           'unlinked_accounts_detected',
           format('%s conta(s) de acesso sem vinculo com o cadastro', v_total),
           format('%s pessoa(s) tem conta de acesso criada e nenhum cadastro apontando para ela. Dessas, %s ja entrou na plataforma alguma vez, e esse e o caso urgente: a pessoa entra, nao se reconhece, e toda contagem de "membro sem conta" fica errada. A lista, com o endereco mascarado, sai da RPC detect_unlinked_accounts(); ainda nao ha tela nem ferramenta de MCP que a mostre (#2287). Ligar conta a cadastro exige prova de posse da caixa, nunca so o e-mail bater.',
                  v_total, v_signed_in),
           -- Sem link de proposito. /admin/data-health mostra anomalias, invariantes e eventos
           -- de entrevista orfaos, e NAO contas nao ligadas (conferido no DataHealthIsland em
           -- 14/09): apontar para la seria mandar o GP a uma tela que nao responde a pergunta.
           -- Um botao que leva a um muro foi justamente o defeito que a #2273 fechou.
           NULL,
           public._delivery_mode_for('unlinked_accounts_detected'),
           now()
    FROM public.members m
    WHERE m.is_active = true
      AND public.can_by_member(m.id, 'manage_platform')
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = m.id
          AND n.type = 'unlinked_accounts_detected'
          AND n.created_at >= now() - interval '25 days'
      );
    GET DIAGNOSTICS v_inserted = ROW_COUNT;
  END IF;

  -- A auditoria fica FORA do IF de contagem, ao contrario dos irmaos. Um detector que so
  -- registra quando acha nao deixa como separar "rodou e nao achou nada" de "nunca rodou",
  -- que e exatamente o defeito que esta migration conserta. A serie tem de existir no zero.
  IF NOT p_dry_run THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL, 'cron.detect_unlinked_accounts_run', 'system_event', NULL,
      jsonb_build_object('unlinked_total', v_total,
                         'already_signed_in', v_signed_in,
                         'managers_notified', v_inserted),
      jsonb_build_object('source', 'cron_detect_unlinked_accounts', 'issue', 2285)
    );
  END IF;

  RETURN jsonb_build_object(
    'unlinked_total',         v_total,
    'already_signed_in',      v_signed_in,
    'would_notify',           v_alvos,
    'notifications_inserted', v_inserted,
    'dry_run',                p_dry_run,
    'run_at',                 now()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.detect_unlinked_accounts_cron(boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.detect_unlinked_accounts_cron(boolean) FROM anon;
REVOKE ALL ON FUNCTION public.detect_unlinked_accounts_cron(boolean) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.detect_unlinked_accounts_cron(boolean) TO service_role;

-- ----------------------------------------------------------------------------
-- (4) O tipo entra no catalogo ADR-0022. O bloco abaixo e o corpo VIVO de
--     _delivery_mode_for (md5 normalizado 1122f9eb345e341b9d82a916ced67a7a, conferido contra
--     pg_proc em 14/09) com UMA linha acrescentada, para nao reescrever o helper de memoria.
--     O guard tests/contracts/adr-0022-delivery-mode.test.mjs le a ULTIMA redefinicao entre
--     as migrations, que passa a ser esta.
-- ----------------------------------------------------------------------------
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
-- ----------------------------------------------------------------------------
-- (5) O agendamento. `cron.schedule` faz upsert por NOME em pg_cron recente, mas o
--     `unschedule` antes deixa a migration reaplicavel em qualquer versao (mesmo padrao das
--     migrations do #2188). Segunda 06:40 UTC = 03:40 em Sao Paulo. Minuto deslocado de
--     proposito (#1844): hora cheia concentra jobs, e o pool e compartilhado com trafego real.
--     Segunda de manha para que a fila da semana chegue antes de a semana comecar.
-- ----------------------------------------------------------------------------
SELECT cron.unschedule('unlinked-accounts-detect-weekly')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'unlinked-accounts-detect-weekly');

SELECT cron.schedule(
  'unlinked-accounts-detect-weekly',
  '40 6 * * 1',
  $cron$SELECT public.detect_unlinked_accounts_cron();$cron$
);
