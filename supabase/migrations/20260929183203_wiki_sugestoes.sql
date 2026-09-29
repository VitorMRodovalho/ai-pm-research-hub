-- #2495 fase B2: "Sugerir melhoria" no wiki (decisões do GP em 28/09/2026).
--
-- Qualquer membro ativo que lê uma página pode sugerir uma melhoria. A sugestão não entra na página:
-- vai para quem decide sobre ela, e só quem sugeriu e quem decide a enxergam (ADR-0010: o texto é livre
-- e pode carregar dado pessoal; por isso também não vai no corpo do aviso nem do e-mail).
--
--   Quem decide (mesma regra das versões, ADR-0129 emendas 2 e 3):
--     - página de uma iniciativa (tribo, grupo de trabalho, vertical, grupo de estudos) com liderança
--       ativa (leader, coordinator): a liderança dela;
--     - página sem iniciativa dona, página de governança, iniciativa sem liderança ativa, ou sugestão
--       de alguém da própria liderança (quatro olhos): o Comitê de Curadoria.
--     O comitê enxerga todas na fila, mas só é avisado das que são dele. Ninguém responde à própria.
--   Resposta: aceitar ou recusar. Recusar exige motivo escrito. Quem sugeriu é avisado do desfecho:
--   toda sugestão fica registrada e nenhuma é resolvida em silêncio.
--
--   (1) wiki_page_suggestions: sem acesso direto de cliente (RLS ligada, sem grant); tudo passa pelas
--       funções abaixo, que aplicam os portões.
--   (2) _wiki_page_initiative: a iniciativa dona de uma página. Página da plataforma: a das versões.
--       Página do repositório de tribo (tribes/tribo-N-...): a tribo de legacy_tribe_id = N, que é único.
--   (3) wiki_suggest, wiki_suggestion_decide, wiki_suggestion_queue.
--   (4) _delivery_mode_for recriado a partir do corpo vivo (md5 normalizado 5ec751ae..., igual à
--       captura de 20260927212811), com 2 tipos novos imediatos.
--
-- ROLLBACK: DROP FUNCTION wiki_suggestion_queue(), wiki_suggestion_decide(uuid, text, text),
--   wiki_suggest(text, text), _wiki_page_initiative(text); DROP TABLE wiki_page_suggestions;
--   reaplicar _delivery_mode_for de 20260927212811.

-- ─── (1) sugestões ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.wiki_page_suggestions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  page_path        text NOT NULL,
  initiative_id    uuid REFERENCES public.initiatives(id),
  route            text NOT NULL CHECK (route IN ('leader','committee')),
  body             text NOT NULL CHECK (length(btrim(body)) BETWEEN 10 AND 2000),
  pii_detail       text,
  author_id        uuid REFERENCES public.members(id) ON DELETE SET NULL,
  status           text NOT NULL DEFAULT 'open' CHECK (status IN ('open','accepted','declined')),
  decided_by       uuid REFERENCES public.members(id) ON DELETE SET NULL,
  decided_at       timestamptz,
  decision_reason  text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT wiki_page_suggestions_decided_check
    CHECK ((status = 'open') = (decided_at IS NULL)),
  CONSTRAINT wiki_page_suggestions_declined_reason_check
    CHECK (status <> 'declined' OR length(btrim(coalesce(decision_reason, ''))) > 0)
);
CREATE INDEX IF NOT EXISTS idx_wiki_page_suggestions_open
  ON public.wiki_page_suggestions (route, initiative_id) WHERE status = 'open';
CREATE INDEX IF NOT EXISTS idx_wiki_page_suggestions_initiative ON public.wiki_page_suggestions (initiative_id);
CREATE INDEX IF NOT EXISTS idx_wiki_page_suggestions_author ON public.wiki_page_suggestions (author_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wiki_page_suggestions_decided_by ON public.wiki_page_suggestions (decided_by);

ALTER TABLE public.wiki_page_suggestions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.wiki_page_suggestions FROM PUBLIC, anon, authenticated;

-- ─── (2) a iniciativa dona da página ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._wiki_page_initiative(p_page_path text)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
    WHEN p_page_path LIKE 'nucleo/%' THEN
      (SELECT v.initiative_id FROM public.wiki_page_versions v WHERE v.page_path = p_page_path LIMIT 1)
    WHEN p_page_path ~ '^tribes/tribo-[0-9]+-' THEN
      (SELECT i.id FROM public.initiatives i
        WHERE i.kind = 'research_tribe'
          AND i.legacy_tribe_id = substring(p_page_path FROM '^tribes/tribo-([0-9]+)-')::integer)
  END;
$function$;

-- ─── (3) sugerir, responder, fila ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.wiki_suggest(p_page_path text, p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller     uuid;
  v_page       record;
  v_initiative uuid;
  v_route      text;
  v_body       text := btrim(coalesce(p_body, ''));
  v_id         uuid;
  v_recipients uuid[];
  v_r          uuid;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.rls_is_authoritative_member() THEN
    RAISE EXCEPTION 'wiki: requer membro ativo' USING ERRCODE = '42501';
  END IF;

  SELECT w.path, w.title, w.domain INTO v_page FROM public.wiki_pages w WHERE w.path = p_page_path;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'wiki: página não encontrada' USING ERRCODE = '42501';
  END IF;
  v_initiative := public._wiki_page_initiative(p_page_path);
  IF v_initiative IS NOT NULL AND NOT public.rls_can_see_initiative(v_initiative) THEN
    RAISE EXCEPTION 'wiki: página não encontrada' USING ERRCODE = '42501';
  END IF;

  IF length(v_body) < 10 OR length(v_body) > 2000 THEN
    RAISE EXCEPTION 'wiki: a sugestão precisa ter entre 10 e 2000 caracteres' USING ERRCODE = '23514';
  END IF;
  IF (SELECT count(*) FROM public.wiki_page_suggestions s
       WHERE s.author_id = v_caller AND s.page_path = p_page_path AND s.status = 'open') >= 3 THEN
    RAISE EXCEPTION 'wiki: você já tem 3 sugestões abertas nesta página; espere a resposta' USING ERRCODE = '23514';
  END IF;

  -- Quem decide: a liderança da iniciativa, salvo quando a página é de governança, não tem iniciativa
  -- dona, a iniciativa não tem liderança ativa, ou quem sugere é da própria liderança (quatro olhos).
  v_route := CASE
    WHEN v_initiative IS NULL
      OR v_page.domain = 'governance'
      OR public._wiki_is_initiative_leader(v_caller, v_initiative)
      OR NOT EXISTS (SELECT 1 FROM public._wiki_initiative_leader_ids(v_initiative))
    THEN 'committee' ELSE 'leader' END;

  INSERT INTO public.wiki_page_suggestions (page_path, initiative_id, route, body, pii_detail, author_id)
  VALUES (p_page_path, v_initiative, v_route, v_body, public._wiki_pii_detail(v_body), v_caller)
  RETURNING id INTO v_id;

  -- O aviso não leva o texto da sugestão: ele pode carregar dado pessoal e o e-mail sai da plataforma.
  v_recipients := CASE v_route
    WHEN 'committee' THEN ARRAY(SELECT public._wiki_committee_ids())
    ELSE ARRAY(SELECT public._wiki_initiative_leader_ids(v_initiative)) END;
  FOR v_r IN SELECT DISTINCT u FROM unnest(array_remove(v_recipients, v_caller)) u WHERE u IS NOT NULL LOOP
    PERFORM public.create_notification(v_r, 'wiki_suggestion_received', 'Sugestão de melhoria no wiki',
      'Uma sugestão de melhoria para "' || v_page.title || '" aguarda sua resposta.',
      '/wiki?tab=decide', 'wiki_page_suggestion', v_id);
  END LOOP;

  RETURN jsonb_build_object('id', v_id, 'route', v_route);
END;
$function$;

CREATE OR REPLACE FUNCTION public.wiki_suggestion_decide(p_suggestion_id uuid, p_decision text, p_reason text DEFAULT NULL)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller       uuid;
  v_s            public.wiki_page_suggestions%ROWTYPE;
  v_is_committee boolean;
  v_reason       text := nullif(btrim(coalesce(p_reason, '')), '');
  v_title        text;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.rls_is_authoritative_member() THEN
    RAISE EXCEPTION 'wiki: requer membro ativo' USING ERRCODE = '42501';
  END IF;
  IF p_decision IS NULL OR p_decision NOT IN ('accepted', 'declined') THEN
    RAISE EXCEPTION 'wiki: resposta inválida (accepted ou declined)';
  END IF;

  SELECT * INTO v_s FROM public.wiki_page_suggestions WHERE id = p_suggestion_id FOR UPDATE;
  IF NOT FOUND OR (v_s.initiative_id IS NOT NULL AND NOT public.rls_can_see_initiative(v_s.initiative_id)) THEN
    RAISE EXCEPTION 'wiki: sugestão não encontrada' USING ERRCODE = '42501';
  END IF;
  IF v_s.status <> 'open' THEN
    RAISE EXCEPTION 'wiki: esta sugestão já foi respondida (estado atual: %)', v_s.status;
  END IF;
  IF v_s.author_id = v_caller THEN
    RAISE EXCEPTION 'wiki: quem sugeriu não responde à própria sugestão' USING ERRCODE = '42501';
  END IF;

  v_is_committee := public.can_by_member(v_caller, 'curate_content');
  IF v_s.route = 'committee' AND NOT v_is_committee THEN
    RAISE EXCEPTION 'wiki: esta sugestão aguarda o comitê de curadoria' USING ERRCODE = '42501';
  END IF;
  IF v_s.route = 'leader' AND NOT (v_is_committee OR public._wiki_is_initiative_leader(v_caller, v_s.initiative_id)) THEN
    RAISE EXCEPTION 'wiki: só a liderança da iniciativa ou o comitê respondem esta sugestão' USING ERRCODE = '42501';
  END IF;
  IF p_decision = 'declined' AND v_reason IS NULL THEN
    RAISE EXCEPTION 'wiki: recusar exige motivo' USING ERRCODE = '23514';
  END IF;

  UPDATE public.wiki_page_suggestions
     SET status = p_decision, decided_by = v_caller, decided_at = now(), decision_reason = v_reason, updated_at = now()
   WHERE id = p_suggestion_id;

  SELECT w.title INTO v_title FROM public.wiki_pages w WHERE w.path = v_s.page_path;
  IF v_s.author_id IS NOT NULL THEN
    PERFORM public.create_notification(v_s.author_id, 'wiki_suggestion_decision',
      CASE p_decision WHEN 'accepted' THEN 'Sua sugestão no wiki foi aceita' ELSE 'Sua sugestão no wiki foi recusada' END,
      'Sua sugestão para "' || coalesce(v_title, v_s.page_path) || '" foi '
        || CASE p_decision WHEN 'accepted' THEN 'aceita' ELSE 'recusada' END
        || CASE WHEN v_reason IS NOT NULL THEN '. Motivo: ' || v_reason ELSE '.' END,
      '/wiki?tab=mine', 'wiki_page_suggestion', p_suggestion_id);
  END IF;
  RETURN p_decision;
END;
$function$;

CREATE OR REPLACE FUNCTION public.wiki_suggestion_queue()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller       uuid;
  v_is_committee boolean;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.rls_is_authoritative_member() THEN
    RAISE EXCEPTION 'wiki: requer membro ativo' USING ERRCODE = '42501';
  END IF;
  v_is_committee := public.can_by_member(v_caller, 'curate_content');

  RETURN jsonb_build_object(
    -- Para responder: as da liderança de uma iniciativa que a pessoa lidera e, para o comitê, todas.
    'to_decide', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'id', s.id, 'page_path', s.page_path, 'page_title', coalesce(w.title, s.page_path),
               'initiative', i.title, 'route', s.route, 'body', s.body, 'pii', s.pii_detail,
               'author', m.name, 'created_at', s.created_at) ORDER BY s.created_at)
        FROM public.wiki_page_suggestions s
        LEFT JOIN public.wiki_pages w ON w.path = s.page_path
        LEFT JOIN public.initiatives i ON i.id = s.initiative_id
        LEFT JOIN public.members m ON m.id = s.author_id
       WHERE s.status = 'open'
         AND s.author_id IS DISTINCT FROM v_caller
         AND (s.initiative_id IS NULL OR public.rls_can_see_initiative(s.initiative_id))
         AND ((s.route = 'committee' AND v_is_committee)
           OR (s.route = 'leader' AND (v_is_committee OR public._wiki_is_initiative_leader(v_caller, s.initiative_id))))),
      '[]'::jsonb),
    -- As que a pessoa enviou, com o desfecho e o motivo.
    'mine', coalesce((
      SELECT jsonb_agg(x.j ORDER BY x.created_at DESC)
        FROM (SELECT s.created_at, jsonb_build_object(
                     'id', s.id, 'page_path', s.page_path, 'page_title', coalesce(w.title, s.page_path),
                     'route', s.route, 'body', s.body, 'status', s.status,
                     'decision_reason', s.decision_reason, 'decided_at', s.decided_at,
                     'created_at', s.created_at) AS j
                FROM public.wiki_page_suggestions s
                LEFT JOIN public.wiki_pages w ON w.path = s.page_path
               WHERE s.author_id = v_caller
               ORDER BY s.created_at DESC
               LIMIT 50) x),
      '[]'::jsonb));
END;
$function$;

-- ─── (4) modo de entrega dos 2 tipos novos ─────────────────────────────────────────────────────
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
    -- #2496 (2026-09-27): aviso a tribo (participantes do card e lideranca da iniciativa) de que o
    -- item entrou em curadoria. Imediato de proposito: caia em card_moved (digest_weekly), com o
    -- codigo cru do status e link generico, e nenhuma das 3 pessoas da tribo recebeu e-mail.
    WHEN 'curation_submitted_to_tribe'    THEN 'transactional_immediate'
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


-- ─── permissões ────────────────────────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public._wiki_page_initiative(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._wiki_page_initiative(text) TO service_role;

REVOKE ALL ON FUNCTION public.wiki_suggest(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.wiki_suggestion_decide(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.wiki_suggestion_queue() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.wiki_suggest(text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.wiki_suggestion_decide(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.wiki_suggestion_queue() TO authenticated, service_role;
