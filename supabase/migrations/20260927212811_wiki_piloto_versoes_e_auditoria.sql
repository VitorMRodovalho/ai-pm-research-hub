-- #2495: piloto do wiki vivo, camada de banco (ADR-0129 com as emendas 1 e 2).
--
-- Modelo decidido pelo GP em 27/09: a lideranca da tribo publica na hora e o Comite de Curadoria
-- audita toda publicacao em ate 14 dias (mantem, altera ou despublica, sempre com motivo). O comite
-- aprova ANTES quando: o filtro aponta possivel dado pessoal; o autor e a propria lideranca; o
-- autor e do comite; ou a tribo nao tem lideranca ativa. Quem escreveu nunca decide nem audita a
-- propria versao. Piloto restrito ao dominio tribes.
--
--   (1) wiki_pages: trava do espaco de caminhos da plataforma (nucleo/...), para o sync-wiki nunca
--       sobrescrever pagina da plataforma, e estado de auditoria (pending / audited).
--   (2) wiki_page_versions + wiki_page_events: a versao e a unidade de revisao; eventos so de
--       acrescimo. Sem acesso direto de cliente (RLS ligada, sem politica, REVOKE).
--   (3) auxiliares internas, sem EXECUTE de cliente.
--   (4-7) wiki_save_draft, wiki_submit, wiki_decide, wiki_audit.
--   (8) wiki_review_queue, wiki_get_version (portao confidencial rls_can_see_initiative).
--   (9, 11) wiki_audit_sla_sweep diario, aviso de vencido a quem gere a plataforma.
--   _delivery_mode_for recriado a partir do corpo vivo, com 4 tipos novos imediatos.
--
-- ROLLBACK: cron.unschedule('wiki-audit-sla-daily'); DROP das funcoes wiki_* e _wiki_*; DROP TABLE
--   wiki_page_events, wiki_page_versions; DELETE FROM wiki_pages WHERE source_repo = 'plataforma';
--   DROP das 3 constraints e das 2 colunas novas de wiki_pages; reaplicar _delivery_mode_for de
--   20260927153519.

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

-- ─── (1) wiki_pages: espaço de caminhos da plataforma e estado de auditoria ───────────────────
-- ADR-0129 d.2: páginas da plataforma vivem em caminhos que o repositório nunca usa. O sync-wiki
-- faz upsert por `path`; sem esta trava, um arquivo do repositório com o mesmo caminho sobrescreveria
-- a página da plataforma. Com ela, esse upsert falha e a página fica intacta.
ALTER TABLE public.wiki_pages ADD COLUMN IF NOT EXISTS audit_status text;
ALTER TABLE public.wiki_pages ADD COLUMN IF NOT EXISTS platform_version_id uuid;

ALTER TABLE public.wiki_pages DROP CONSTRAINT IF EXISTS wiki_pages_audit_status_check;
ALTER TABLE public.wiki_pages ADD CONSTRAINT wiki_pages_audit_status_check
  CHECK (audit_status IS NULL OR audit_status IN ('pending', 'audited'));

ALTER TABLE public.wiki_pages DROP CONSTRAINT IF EXISTS wiki_pages_platform_namespace_check;
ALTER TABLE public.wiki_pages ADD CONSTRAINT wiki_pages_platform_namespace_check
  CHECK ((source_repo = 'plataforma') = (path LIKE 'nucleo/%'));

ALTER TABLE public.wiki_pages DROP CONSTRAINT IF EXISTS wiki_pages_platform_audit_check;
ALTER TABLE public.wiki_pages ADD CONSTRAINT wiki_pages_platform_audit_check
  CHECK ((source_repo = 'plataforma') = (audit_status IS NOT NULL));

-- ─── (2) versões e eventos ─────────────────────────────────────────────────────────────────────
-- A unidade de revisão é a VERSÃO da página (emenda 2, item 7). O conteúdo de uma versão só muda
-- enquanto ela é rascunho do autor; os eventos são só de acréscimo (nenhuma função os altera).
CREATE TABLE IF NOT EXISTS public.wiki_page_versions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  page_path       text NOT NULL CHECK (page_path ~ '^nucleo/[a-z0-9][a-z0-9/_-]*$'),
  initiative_id   uuid NOT NULL REFERENCES public.initiatives(id),
  domain          text NOT NULL CHECK (domain IN ('research','governance','tribes','partnerships','platform','onboarding')),
  version_no      integer NOT NULL CHECK (version_no > 0),
  title           text NOT NULL CHECK (length(btrim(title)) > 0),
  summary         text,
  content         text NOT NULL DEFAULT '' CHECK (length(content) <= 200000),
  doc_type        text CHECK (doc_type IN ('tutorial','how_to','reference','explanation')),
  sources         jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(sources) = 'array'),
  author_id       uuid REFERENCES public.members(id) ON DELETE SET NULL,
  status          text NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft','pending_leader','pending_committee','returned','published','superseded','unpublished')),
  review_route    text CHECK (review_route IN ('leader','committee')),
  pii_detail      text,
  submitted_at    timestamptz,
  published_at    timestamptz,
  published_by    uuid REFERENCES public.members(id) ON DELETE SET NULL,
  audit_due_at    timestamptz,
  audited_at      timestamptz,
  audited_by      uuid REFERENCES public.members(id) ON DELETE SET NULL,
  audit_outcome   text CHECK (audit_outcome IN ('kept','altered','unpublished')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (page_path, version_no)
);
CREATE INDEX IF NOT EXISTS idx_wiki_page_versions_path ON public.wiki_page_versions (page_path);
CREATE INDEX IF NOT EXISTS idx_wiki_page_versions_initiative_status ON public.wiki_page_versions (initiative_id, status);
CREATE INDEX IF NOT EXISTS idx_wiki_page_versions_audit_pending
  ON public.wiki_page_versions (audit_due_at) WHERE status = 'published' AND audited_at IS NULL;
-- no máximo UMA versão publicada por página
CREATE UNIQUE INDEX IF NOT EXISTS uq_wiki_page_versions_one_published
  ON public.wiki_page_versions (page_path) WHERE status = 'published';

CREATE TABLE IF NOT EXISTS public.wiki_page_events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id  uuid NOT NULL REFERENCES public.wiki_page_versions(id),
  page_path   text NOT NULL,
  action      text NOT NULL CHECK (action IN ('submitted','returned','published','audited_kept','altered','unpublished','audit_overdue')),
  actor_id    uuid REFERENCES public.members(id) ON DELETE SET NULL,
  reason      text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wiki_page_events_version ON public.wiki_page_events (version_id);

-- Sem acesso direto de cliente: tudo passa pelas funções abaixo, que aplicam os portões.
ALTER TABLE public.wiki_page_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wiki_page_events   ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.wiki_page_versions FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.wiki_page_events   FROM PUBLIC, anon, authenticated;

-- ─── (3) auxiliares internas ───────────────────────────────────────────────────────────────────
-- Mesma regra de dado pessoal de wiki_health_report (e-mail, telefone BR, CPF).
CREATE OR REPLACE FUNCTION public._wiki_pii_detail(p_text text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT NULLIF(concat_ws(', ',
    CASE WHEN p_text ~* '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' THEN 'e-mail' END,
    CASE WHEN p_text ~ '\+?55\s?\d{2}\s?\d{4,5}[\s-]?\d{4}' THEN 'telefone' END,
    CASE WHEN p_text ~ '\d{3}\.\d{3}\.\d{3}-\d{2}' THEN 'CPF' END), '');
$function$;

CREATE OR REPLACE FUNCTION public._wiki_is_initiative_leader(p_member uuid, p_initiative uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.engagements e JOIN public.members m ON m.person_id = e.person_id
     WHERE m.id = p_member AND e.initiative_id = p_initiative
       AND e.status = 'active' AND e.role = 'leader');
$function$;

-- Quem escreve: quem participa da tribo (liderança ou pesquisa) ou o comitê de curadoria.
CREATE OR REPLACE FUNCTION public._wiki_can_author(p_member uuid, p_initiative uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.engagements e JOIN public.members m ON m.person_id = e.person_id
     WHERE m.id = p_member AND e.initiative_id = p_initiative
       AND e.status = 'active' AND e.role IN ('leader', 'researcher'))
    OR public.can_by_member(p_member, 'curate_content');
$function$;

CREATE OR REPLACE FUNCTION public._wiki_initiative_leader_ids(p_initiative uuid)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT DISTINCT m.id
    FROM public.engagements e JOIN public.members m ON m.person_id = e.person_id
   WHERE e.initiative_id = p_initiative AND e.status = 'active' AND e.role = 'leader'
     AND m.is_active AND m.member_status = 'active';
$function$;

CREATE OR REPLACE FUNCTION public._wiki_committee_ids()
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT m.id FROM public.members m
   WHERE m.is_active AND m.member_status = 'active' AND m.auth_id IS NOT NULL
     AND public.can_by_member(m.id, 'curate_content');
$function$;

CREATE OR REPLACE FUNCTION public._wiki_notify(p_recipients uuid[], p_type text, p_title text, p_body text, p_version uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_id uuid;
  v_n  integer := 0;
BEGIN
  FOR v_id IN SELECT DISTINCT u FROM unnest(p_recipients) u WHERE u IS NOT NULL LOOP
    PERFORM public.create_notification(v_id, p_type, p_title, p_body, '/wiki', 'wiki_page_version', p_version);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$function$;

-- ─── (4) escrever: rascunho ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.wiki_save_draft(
  p_page_path text, p_initiative_id uuid, p_title text, p_summary text, p_content text,
  p_doc_type text, p_sources jsonb DEFAULT '[]'::jsonb, p_domain text DEFAULT 'tribes',
  p_version_id uuid DEFAULT NULL)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller   uuid;
  v_ver      public.wiki_page_versions%ROWTYPE;
  v_owner    uuid;
  v_no       integer;
  v_id       uuid;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.rls_is_authoritative_member() THEN
    RAISE EXCEPTION 'wiki: requer membro ativo' USING ERRCODE = '42501';
  END IF;

  -- Editar um rascunho (ou versão devolvida) do próprio autor.
  IF p_version_id IS NOT NULL THEN
    SELECT * INTO v_ver FROM public.wiki_page_versions WHERE id = p_version_id FOR UPDATE;
    IF NOT FOUND OR v_ver.author_id IS DISTINCT FROM v_caller THEN
      RAISE EXCEPTION 'wiki: rascunho não encontrado' USING ERRCODE = '42501';
    END IF;
    IF v_ver.status NOT IN ('draft', 'returned') THEN
      RAISE EXCEPTION 'wiki: só rascunho ou versão devolvida pode ser editada (estado atual: %)', v_ver.status;
    END IF;
    UPDATE public.wiki_page_versions
       SET title = p_title, summary = p_summary, content = coalesce(p_content, ''),
           doc_type = p_doc_type, sources = coalesce(p_sources, '[]'::jsonb),
           status = 'draft', updated_at = now()
     WHERE id = p_version_id;
    RETURN p_version_id;
  END IF;

  -- Piloto (emenda 1, item 4): só o domínio tribes, em tribo de pesquisa.
  IF p_domain IS DISTINCT FROM 'tribes' THEN
    RAISE EXCEPTION 'wiki: fora do piloto (só o domínio tribes)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.initiatives i WHERE i.id = p_initiative_id AND i.kind = 'research_tribe') THEN
    RAISE EXCEPTION 'wiki: a iniciativa precisa ser uma tribo de pesquisa';
  END IF;
  IF NOT public.rls_can_see_initiative(p_initiative_id) THEN
    RAISE EXCEPTION 'wiki: iniciativa não encontrada' USING ERRCODE = '42501';
  END IF;
  IF NOT public._wiki_can_author(v_caller, p_initiative_id) THEN
    RAISE EXCEPTION 'wiki: só quem participa da tribo, ou o comitê de curadoria, escreve nesta página' USING ERRCODE = '42501';
  END IF;
  IF p_page_path IS NULL OR p_page_path !~ '^nucleo/[a-z0-9][a-z0-9/_-]*$' THEN
    RAISE EXCEPTION 'wiki: caminho inválido (use nucleo/...)';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('wiki_page_versions:' || p_page_path));
  SELECT initiative_id INTO v_owner FROM public.wiki_page_versions WHERE page_path = p_page_path LIMIT 1;
  IF v_owner IS NOT NULL AND v_owner <> p_initiative_id THEN
    RAISE EXCEPTION 'wiki: esta página pertence a outra iniciativa';
  END IF;
  SELECT coalesce(max(version_no), 0) + 1 INTO v_no FROM public.wiki_page_versions WHERE page_path = p_page_path;

  INSERT INTO public.wiki_page_versions
    (page_path, initiative_id, domain, version_no, title, summary, content, doc_type, sources, author_id, status)
  VALUES
    (p_page_path, p_initiative_id, p_domain, v_no, p_title, p_summary, coalesce(p_content, ''),
     p_doc_type, coalesce(p_sources, '[]'::jsonb), v_caller, 'draft')
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

-- ─── (5) enviar: filtro automático e rota ──────────────────────────────────────────────────────
-- Rota do comitê (aprovação ANTES) quando: há aviso de dado pessoal; o autor é a liderança da tribo;
-- o autor é do comitê; ou a tribo não tem liderança ativa. Nos demais casos, a liderança decide.
CREATE OR REPLACE FUNCTION public.wiki_submit(p_version_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller     uuid;
  v_ver        public.wiki_page_versions%ROWTYPE;
  v_missing    text[] := '{}';
  v_pii        text;
  v_route      text;
  v_status     text;
  v_recipients uuid[];
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.rls_is_authoritative_member() THEN
    RAISE EXCEPTION 'wiki: requer membro ativo' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_ver FROM public.wiki_page_versions WHERE id = p_version_id FOR UPDATE;
  IF NOT FOUND OR v_ver.author_id IS DISTINCT FROM v_caller THEN
    RAISE EXCEPTION 'wiki: versão não encontrada' USING ERRCODE = '42501';
  END IF;
  IF v_ver.status NOT IN ('draft', 'returned') THEN
    RAISE EXCEPTION 'wiki: esta versão já foi enviada (estado atual: %)', v_ver.status;
  END IF;

  IF coalesce(btrim(v_ver.summary), '') = '' THEN v_missing := v_missing || 'resumo'::text; END IF;
  IF v_ver.doc_type IS NULL THEN v_missing := v_missing || 'tipo'::text; END IF;
  IF jsonb_array_length(v_ver.sources) = 0 THEN v_missing := v_missing || 'fontes'::text; END IF;
  IF cardinality(v_missing) > 0 THEN
    RAISE EXCEPTION 'wiki: faltam campos obrigatórios: %', array_to_string(v_missing, ', ') USING ERRCODE = '23514';
  END IF;

  v_pii := public._wiki_pii_detail(concat_ws(E'\n', v_ver.title, v_ver.summary, v_ver.content));
  v_route := CASE
    WHEN v_pii IS NOT NULL
      OR public._wiki_is_initiative_leader(v_caller, v_ver.initiative_id)
      OR public.can_by_member(v_caller, 'curate_content')
      OR NOT EXISTS (SELECT 1 FROM public._wiki_initiative_leader_ids(v_ver.initiative_id))
    THEN 'committee' ELSE 'leader' END;
  v_status := CASE v_route WHEN 'committee' THEN 'pending_committee' ELSE 'pending_leader' END;

  UPDATE public.wiki_page_versions
     SET status = v_status, review_route = v_route, pii_detail = v_pii,
         submitted_at = now(), updated_at = now()
   WHERE id = p_version_id;
  INSERT INTO public.wiki_page_events (version_id, page_path, action, actor_id, reason)
  VALUES (p_version_id, v_ver.page_path, 'submitted', v_caller,
          CASE WHEN v_pii IS NOT NULL THEN 'possível dado pessoal: ' || v_pii END);

  v_recipients := CASE v_route
    WHEN 'committee' THEN ARRAY(SELECT public._wiki_committee_ids())
    ELSE ARRAY(SELECT public._wiki_initiative_leader_ids(v_ver.initiative_id)) END;
  PERFORM public._wiki_notify(array_remove(v_recipients, v_caller), 'wiki_review_requested',
    'Página do wiki aguarda sua aprovação',
    '"' || v_ver.title || '" foi enviada para '
      || CASE v_route WHEN 'committee' THEN 'o comitê de curadoria' ELSE 'a liderança da tribo' END || '.'
      || CASE WHEN v_pii IS NOT NULL THEN ' O filtro apontou possível dado pessoal (' || v_pii || ').' ELSE '' END,
    p_version_id);

  RETURN jsonb_build_object('status', v_status, 'route', v_route, 'pii', v_pii);
END;
$function$;

-- ─── (6) decidir: publicar ou devolver ─────────────────────────────────────────────────────────
-- Quatro olhos: quem escreveu nunca decide a própria versão. Publicação pela liderança abre a
-- auditoria de 14 dias; publicação pelo comitê já nasce auditada.
CREATE OR REPLACE FUNCTION public.wiki_decide(p_version_id uuid, p_decision text, p_reason text DEFAULT NULL)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller       uuid;
  v_ver          public.wiki_page_versions%ROWTYPE;
  v_is_committee boolean;
  v_is_leader    boolean;
  v_author_name  text;
  v_audit_status text;
  v_due          timestamptz;
  v_others       uuid[];
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.rls_is_authoritative_member() THEN
    RAISE EXCEPTION 'wiki: requer membro ativo' USING ERRCODE = '42501';
  END IF;
  IF p_decision IS NULL OR p_decision NOT IN ('publish', 'return') THEN
    RAISE EXCEPTION 'wiki: decisão inválida (publish ou return)';
  END IF;
  SELECT * INTO v_ver FROM public.wiki_page_versions WHERE id = p_version_id FOR UPDATE;
  IF NOT FOUND OR NOT public.rls_can_see_initiative(v_ver.initiative_id) THEN
    RAISE EXCEPTION 'wiki: versão não encontrada' USING ERRCODE = '42501';
  END IF;
  IF v_ver.status NOT IN ('pending_leader', 'pending_committee') THEN
    RAISE EXCEPTION 'wiki: esta versão não aguarda decisão (estado atual: %)', v_ver.status;
  END IF;
  IF v_ver.author_id = v_caller THEN
    RAISE EXCEPTION 'wiki: quem escreveu não aprova a própria versão' USING ERRCODE = '42501';
  END IF;

  v_is_committee := public.can_by_member(v_caller, 'curate_content');
  v_is_leader    := public._wiki_is_initiative_leader(v_caller, v_ver.initiative_id);
  IF v_ver.status = 'pending_committee' AND NOT v_is_committee THEN
    RAISE EXCEPTION 'wiki: esta versão aguarda o comitê de curadoria' USING ERRCODE = '42501';
  END IF;
  IF v_ver.status = 'pending_leader' AND NOT (v_is_leader OR v_is_committee) THEN
    RAISE EXCEPTION 'wiki: só a liderança da tribo ou o comitê decidem esta versão' USING ERRCODE = '42501';
  END IF;

  IF p_decision = 'return' THEN
    IF coalesce(btrim(p_reason), '') = '' THEN
      RAISE EXCEPTION 'wiki: devolver exige motivo';
    END IF;
    UPDATE public.wiki_page_versions SET status = 'returned', updated_at = now() WHERE id = p_version_id;
    INSERT INTO public.wiki_page_events (version_id, page_path, action, actor_id, reason)
    VALUES (p_version_id, v_ver.page_path, 'returned', v_caller, p_reason);
    PERFORM public._wiki_notify(ARRAY[v_ver.author_id], 'wiki_page_decision', 'Página do wiki devolvida',
      '"' || v_ver.title || '" foi devolvida: ' || p_reason, p_version_id);
    RETURN 'returned';
  END IF;

  -- publicar
  v_due := CASE WHEN v_is_committee THEN NULL ELSE now() + interval '14 days' END;
  v_audit_status := CASE WHEN v_is_committee THEN 'audited' ELSE 'pending' END;

  UPDATE public.wiki_page_versions SET status = 'superseded', updated_at = now()
   WHERE page_path = v_ver.page_path AND status = 'published';
  UPDATE public.wiki_page_versions
     SET status = 'published', published_by = v_caller, published_at = now(), audit_due_at = v_due,
         audited_at = CASE WHEN v_is_committee THEN now() END,
         audited_by = CASE WHEN v_is_committee THEN v_caller END,
         audit_outcome = CASE WHEN v_is_committee THEN 'kept' END,
         updated_at = now()
   WHERE id = p_version_id;

  SELECT name INTO v_author_name FROM public.members WHERE id = v_ver.author_id;
  INSERT INTO public.wiki_pages
    (path, title, domain, content, summary, authors, source_repo, source_sha, synced_at, updated_at,
     audit_status, platform_version_id)
  VALUES
    (v_ver.page_path, v_ver.title, v_ver.domain, v_ver.content, v_ver.summary,
     CASE WHEN v_author_name IS NULL THEN '{}'::text[] ELSE ARRAY[v_author_name] END,
     'plataforma', p_version_id::text, now(), now(), v_audit_status, p_version_id)
  ON CONFLICT (path) DO UPDATE
     SET title = EXCLUDED.title, domain = EXCLUDED.domain, content = EXCLUDED.content,
         summary = EXCLUDED.summary, authors = EXCLUDED.authors, source_sha = EXCLUDED.source_sha,
         synced_at = EXCLUDED.synced_at, updated_at = EXCLUDED.updated_at,
         audit_status = EXCLUDED.audit_status, platform_version_id = EXCLUDED.platform_version_id
   WHERE public.wiki_pages.source_repo = 'plataforma';

  INSERT INTO public.wiki_page_events (version_id, page_path, action, actor_id, reason)
  VALUES (p_version_id, v_ver.page_path, 'published', v_caller,
          CASE WHEN v_is_committee THEN 'pelo comitê de curadoria' ELSE 'pela liderança da tribo' END);

  v_others := array_remove(ARRAY[v_ver.author_id] || ARRAY(SELECT public._wiki_initiative_leader_ids(v_ver.initiative_id)), v_caller);
  PERFORM public._wiki_notify(v_others, 'wiki_page_decision', 'Página do wiki publicada',
    '"' || v_ver.title || '" foi publicada'
      || CASE WHEN v_is_committee THEN ' e já está auditada pelo comitê.'
              ELSE ' e fica com auditoria pendente do comitê até '
                   || to_char(v_due AT TIME ZONE 'America/Sao_Paulo', 'DD/MM') || '.' END,
    p_version_id);
  IF NOT v_is_committee THEN
    PERFORM public._wiki_notify(array_remove(ARRAY(SELECT public._wiki_committee_ids()), v_caller),
      'wiki_audit_requested', 'Página do wiki para auditar',
      '"' || v_ver.title || '" foi publicada pela liderança da tribo. Prazo da auditoria: '
        || to_char(v_due AT TIME ZONE 'America/Sao_Paulo', 'DD/MM') || '.',
      p_version_id);
  END IF;
  RETURN 'published';
END;
$function$;

-- ─── (7) auditar: manter, alterar ou despublicar ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.wiki_audit(
  p_version_id uuid, p_outcome text, p_reason text DEFAULT NULL,
  p_title text DEFAULT NULL, p_summary text DEFAULT NULL, p_content text DEFAULT NULL)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller  uuid;
  v_ver     public.wiki_page_versions%ROWTYPE;
  v_new     public.wiki_page_versions%ROWTYPE;
  v_no      integer;
  v_pii     text;
  v_others  uuid[];
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.rls_is_authoritative_member()
     OR NOT public.can_by_member(v_caller, 'curate_content') THEN
    RAISE EXCEPTION 'wiki: auditoria é do comitê de curadoria' USING ERRCODE = '42501';
  END IF;
  IF p_outcome IS NULL OR p_outcome NOT IN ('kept', 'altered', 'unpublished') THEN
    RAISE EXCEPTION 'wiki: resultado inválido (kept, altered ou unpublished)';
  END IF;
  SELECT * INTO v_ver FROM public.wiki_page_versions WHERE id = p_version_id FOR UPDATE;
  IF NOT FOUND OR NOT public.rls_can_see_initiative(v_ver.initiative_id) THEN
    RAISE EXCEPTION 'wiki: versão não encontrada' USING ERRCODE = '42501';
  END IF;
  IF v_ver.status <> 'published' THEN
    RAISE EXCEPTION 'wiki: só versão publicada é auditada (estado atual: %)', v_ver.status;
  END IF;
  IF v_ver.author_id = v_caller THEN
    RAISE EXCEPTION 'wiki: quem escreveu não audita a própria versão' USING ERRCODE = '42501';
  END IF;
  IF p_outcome IN ('altered', 'unpublished') AND coalesce(btrim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'wiki: alterar ou despublicar exige motivo';
  END IF;
  v_others := ARRAY[v_ver.author_id] || ARRAY(SELECT public._wiki_initiative_leader_ids(v_ver.initiative_id));

  IF p_outcome = 'kept' THEN
    IF v_ver.audited_at IS NOT NULL THEN
      RAISE EXCEPTION 'wiki: esta versão já foi auditada';
    END IF;
    UPDATE public.wiki_page_versions
       SET audited_at = now(), audited_by = v_caller, audit_outcome = 'kept', updated_at = now()
     WHERE id = p_version_id;
    UPDATE public.wiki_pages SET audit_status = 'audited'
     WHERE path = v_ver.page_path AND source_repo = 'plataforma';
    INSERT INTO public.wiki_page_events (version_id, page_path, action, actor_id, reason)
    VALUES (p_version_id, v_ver.page_path, 'audited_kept', v_caller, p_reason);
    PERFORM public._wiki_notify(array_remove(v_others, v_caller), 'wiki_page_decision', 'Página do wiki auditada',
      '"' || v_ver.title || '" foi auditada e mantida pelo comitê de curadoria.', p_version_id);
    RETURN p_version_id;
  END IF;

  IF p_outcome = 'unpublished' THEN
    UPDATE public.wiki_page_versions
       SET status = 'unpublished', audited_at = coalesce(audited_at, now()), audited_by = v_caller,
           audit_outcome = 'unpublished', updated_at = now()
     WHERE id = p_version_id;
    DELETE FROM public.wiki_pages WHERE path = v_ver.page_path AND source_repo = 'plataforma';
    INSERT INTO public.wiki_page_events (version_id, page_path, action, actor_id, reason)
    VALUES (p_version_id, v_ver.page_path, 'unpublished', v_caller, p_reason);
    PERFORM public._wiki_notify(array_remove(v_others, v_caller), 'wiki_page_decision', 'Página do wiki despublicada',
      '"' || v_ver.title || '" foi despublicada pelo comitê de curadoria: ' || p_reason, p_version_id);
    RETURN p_version_id;
  END IF;

  -- alterar: o comitê publica uma versão nova, já auditada, e a anterior fica registrada como alterada
  IF p_content IS NULL THEN
    RAISE EXCEPTION 'wiki: alterar exige o texto novo';
  END IF;
  v_pii := public._wiki_pii_detail(concat_ws(E'\n', coalesce(p_title, v_ver.title), coalesce(p_summary, v_ver.summary), p_content));
  IF v_pii IS NOT NULL THEN
    RAISE EXCEPTION 'wiki: o texto novo tem possível dado pessoal (%)', v_pii USING ERRCODE = '23514';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('wiki_page_versions:' || v_ver.page_path));
  SELECT max(version_no) + 1 INTO v_no FROM public.wiki_page_versions WHERE page_path = v_ver.page_path;

  UPDATE public.wiki_page_versions
     SET status = 'superseded', audited_at = coalesce(audited_at, now()), audited_by = v_caller,
         audit_outcome = 'altered', updated_at = now()
   WHERE id = p_version_id;
  INSERT INTO public.wiki_page_versions
    (page_path, initiative_id, domain, version_no, title, summary, content, doc_type, sources,
     author_id, status, review_route, submitted_at, published_at, published_by,
     audited_at, audited_by, audit_outcome)
  VALUES
    (v_ver.page_path, v_ver.initiative_id, v_ver.domain, v_no, coalesce(p_title, v_ver.title),
     coalesce(p_summary, v_ver.summary), p_content, v_ver.doc_type, v_ver.sources,
     v_caller, 'published', 'committee', now(), now(), v_caller, now(), v_caller, 'kept')
  RETURNING * INTO v_new;

  UPDATE public.wiki_pages
     SET title = v_new.title, summary = v_new.summary, content = v_new.content,
         source_sha = v_new.id::text, synced_at = now(), updated_at = now(),
         audit_status = 'audited', platform_version_id = v_new.id
   WHERE path = v_ver.page_path AND source_repo = 'plataforma';

  INSERT INTO public.wiki_page_events (version_id, page_path, action, actor_id, reason)
  VALUES (p_version_id, v_ver.page_path, 'altered', v_caller, p_reason),
         (v_new.id, v_ver.page_path, 'published', v_caller, 'alteração do comitê de curadoria');
  PERFORM public._wiki_notify(array_remove(v_others, v_caller), 'wiki_page_decision', 'Página do wiki alterada',
    '"' || v_new.title || '" foi alterada pelo comitê de curadoria: ' || p_reason, v_new.id);
  RETURN v_new.id;
END;
$function$;

-- ─── (8) ler: fila de quem decide e audita, e uma versão ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.wiki_review_queue()
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
    'awaiting_my_decision', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'id', v.id, 'page_path', v.page_path, 'version_no', v.version_no, 'title', v.title,
               'initiative', i.title, 'status', v.status, 'route', v.review_route,
               'pii', v.pii_detail, 'submitted_at', v.submitted_at) ORDER BY v.submitted_at)
        FROM public.wiki_page_versions v JOIN public.initiatives i ON i.id = v.initiative_id
       WHERE public.rls_can_see_initiative(v.initiative_id)
         AND v.author_id IS DISTINCT FROM v_caller
         AND ((v.status = 'pending_leader'
               AND (public._wiki_is_initiative_leader(v_caller, v.initiative_id) OR v_is_committee))
           OR (v.status = 'pending_committee' AND v_is_committee))), '[]'::jsonb),
    'audit_pending', CASE WHEN v_is_committee THEN coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'id', v.id, 'page_path', v.page_path, 'version_no', v.version_no, 'title', v.title,
               'initiative', i.title, 'published_at', v.published_at, 'audit_due_at', v.audit_due_at,
               'overdue', v.audit_due_at < now()) ORDER BY v.audit_due_at)
        FROM public.wiki_page_versions v JOIN public.initiatives i ON i.id = v.initiative_id
       WHERE public.rls_can_see_initiative(v.initiative_id)
         AND v.status = 'published' AND v.audited_at IS NULL
         AND v.author_id IS DISTINCT FROM v_caller), '[]'::jsonb) ELSE '[]'::jsonb END,
    'my_versions', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'id', v.id, 'page_path', v.page_path, 'version_no', v.version_no, 'title', v.title,
               'status', v.status, 'updated_at', v.updated_at) ORDER BY v.updated_at DESC)
        FROM public.wiki_page_versions v
       WHERE v.author_id = v_caller
         AND v.status IN ('draft', 'returned', 'pending_leader', 'pending_committee')), '[]'::jsonb));
END;
$function$;

-- Versão publicada (ou substituída) é legível por membro ativo; rascunho, pendente, devolvida e
-- despublicada só por quem escreveu, pela liderança da tribo e pelo comitê.
CREATE OR REPLACE FUNCTION public.wiki_get_version(p_version_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_ver    public.wiki_page_versions%ROWTYPE;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.rls_is_authoritative_member() THEN
    RAISE EXCEPTION 'wiki: requer membro ativo' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_ver FROM public.wiki_page_versions WHERE id = p_version_id;
  IF NOT FOUND OR NOT public.rls_can_see_initiative(v_ver.initiative_id)
     OR NOT (v_ver.status IN ('published', 'superseded')
             OR v_ver.author_id = v_caller
             OR public._wiki_is_initiative_leader(v_caller, v_ver.initiative_id)
             OR public.can_by_member(v_caller, 'curate_content')) THEN
    RAISE EXCEPTION 'wiki: versão não encontrada' USING ERRCODE = '42501';
  END IF;
  RETURN to_jsonb(v_ver) || jsonb_build_object(
    'events', coalesce((SELECT jsonb_agg(jsonb_build_object('action', e.action, 'reason', e.reason,
                                  'actor', m.name, 'at', e.created_at) ORDER BY e.created_at)
                          FROM public.wiki_page_events e LEFT JOIN public.members m ON m.id = e.actor_id
                         WHERE e.version_id = p_version_id), '[]'::jsonb));
END;
$function$;

-- ─── (9) prazo de auditoria vencido: aviso diário a quem gere a plataforma ─────────────────────
CREATE OR REPLACE FUNCTION public.wiki_audit_sla_sweep()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  r      record;
  v_n    integer := 0;
  v_gp   uuid[];
BEGIN
  v_gp := ARRAY(SELECT m.id FROM public.members m
                 WHERE m.is_active AND m.member_status = 'active' AND m.auth_id IS NOT NULL
                   AND public.can_by_member(m.id, 'manage_platform'));
  FOR r IN
    SELECT v.id, v.page_path, v.title, v.audit_due_at
      FROM public.wiki_page_versions v
     WHERE v.status = 'published' AND v.audited_at IS NULL AND v.audit_due_at < now()
       AND NOT EXISTS (SELECT 1 FROM public.wiki_page_events e
                        WHERE e.version_id = v.id AND e.action = 'audit_overdue')
  LOOP
    INSERT INTO public.wiki_page_events (version_id, page_path, action, actor_id, reason)
    VALUES (r.id, r.page_path, 'audit_overdue', NULL, 'prazo de 14 dias vencido');
    PERFORM public._wiki_notify(v_gp, 'wiki_audit_overdue', 'Auditoria do wiki vencida',
      '"' || r.title || '" passou do prazo de auditoria ('
        || to_char(r.audit_due_at AT TIME ZONE 'America/Sao_Paulo', 'DD/MM') || ') sem parecer do comitê.',
      r.id);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$function$;

-- ─── (10) permissões ───────────────────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public._wiki_pii_detail(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._wiki_is_initiative_leader(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._wiki_can_author(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._wiki_initiative_leader_ids(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._wiki_committee_ids() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._wiki_notify(uuid[], text, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.wiki_audit_sla_sweep() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._wiki_pii_detail(text) TO service_role;
GRANT EXECUTE ON FUNCTION public._wiki_is_initiative_leader(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._wiki_can_author(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._wiki_initiative_leader_ids(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._wiki_committee_ids() TO service_role;
GRANT EXECUTE ON FUNCTION public._wiki_notify(uuid[], text, text, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.wiki_audit_sla_sweep() TO service_role;

REVOKE ALL ON FUNCTION public.wiki_save_draft(text, uuid, text, text, text, text, jsonb, text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.wiki_submit(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.wiki_decide(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.wiki_audit(uuid, text, text, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.wiki_review_queue() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.wiki_get_version(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.wiki_save_draft(text, uuid, text, text, text, text, jsonb, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.wiki_submit(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.wiki_decide(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.wiki_audit(uuid, text, text, text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.wiki_review_queue() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.wiki_get_version(uuid) TO authenticated, service_role;

-- ─── (11) agendamento diário da varredura ──────────────────────────────────────────────────────
SELECT cron.unschedule('wiki-audit-sla-daily')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'wiki-audit-sla-daily');

SELECT cron.schedule(
  'wiki-audit-sla-daily',
  '27 12 * * *',
  $cron$SELECT public.wiki_audit_sla_sweep();$cron$
);
