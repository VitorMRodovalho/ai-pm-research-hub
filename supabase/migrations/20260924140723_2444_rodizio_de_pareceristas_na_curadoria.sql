-- ============================================================================
-- #2444 — rodizio de pareceristas na curadoria, com lembrete e escalonamento
-- ============================================================================
--
-- WHAT: quando um card entra em curation_pending, a plataforma designa os pareceristas que o
--   quadro exige (board_sla_config.reviewers_required, 2 por padrao), por menor carga aberta e,
--   no empate, por quem foi designado ha mais tempo. Um job diario lembra o designado 2 dias
--   antes do prazo e, no vencimento, troca quem nao respondeu (se houver curador livre) e avisa
--   quem gere a plataforma.
-- WHY: o pool aberto nao funcionou. Medido em 24/09/2026: 0 designacoes na historia
--   (assign_curation_reviewer existe e nunca foi chamada), 0 pareceres nos cards que chegaram a
--   curadoria, e os que estao na fila com prazo vencido. Todos responsaveis = ninguem responsavel.
-- DESENHO:
--   * curation_reviewer_assignments e o registro ESTRUTURADO de quem foi designado (o evento
--     reviewer_assigned guarda so o nome em texto). O evento continua sendo gravado, porque
--     submit_curation_review le a rodada dele.
--   * elegivel = membro ativo, com login, com curate_content (o que assign_curation_reviewer exige
--     do designado) E participate_in_governance_review (o que submit_curation_review exige de quem
--     da parecer); nunca autor/contribuidor do card nem o assignee legado.
--   * card arquivado ou de iniciativa confidencial nao recebe designacao automatica.
--   * assign_curation_reviewer (designacao manual) passa a gravar no mesmo registro.
-- ROLLBACK: cron.unschedule('curation-reviewer-sla-daily'); DROP TRIGGER
--   trg_curation_auto_assign_on_pending ON board_items; DROP FUNCTION dos helpers; DROP TABLE
--   curation_reviewer_assignments; reaplicar a versao anterior de assign_curation_reviewer e de
--   _delivery_mode_for.
-- CROSS-REF: #2444 · #186 · ADR-0086 · ADR-0022 · ADR-0105
-- ============================================================================

-- (1) O registro de designacoes -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.curation_reviewer_assignments (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  board_item_id uuid NOT NULL REFERENCES public.board_items(id) ON DELETE CASCADE,
  review_round  integer NOT NULL,
  reviewer_id   uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  source        text NOT NULL CHECK (source IN ('auto', 'manual', 'reassign')),
  assigned_by   uuid REFERENCES public.members(id) ON DELETE SET NULL,
  assigned_at   timestamptz NOT NULL DEFAULT now(),
  due_at        timestamptz NOT NULL,
  reminded_at   timestamptz,
  overdue_at    timestamptz,
  released_at   timestamptz,
  UNIQUE (board_item_id, review_round, reviewer_id)
);

CREATE INDEX IF NOT EXISTS idx_curation_reviewer_assignments_open
  ON public.curation_reviewer_assignments (reviewer_id) WHERE released_at IS NULL;

ALTER TABLE public.curation_reviewer_assignments ENABLE ROW LEVEL SECURITY;

-- Leitura: quem ja le o quadro (mesma regra de board_items), e o gate confidencial como em
-- toda tabela-filha do card (#1784). Escrita: nenhuma policy; so as funcoes SECURITY DEFINER.
CREATE POLICY curation_reviewer_assignments_read_members
  ON public.curation_reviewer_assignments FOR SELECT TO authenticated
  USING (public.rls_is_authoritative_member());

CREATE POLICY curation_reviewer_assignments_confidential_visibility
  ON public.curation_reviewer_assignments AS RESTRICTIVE FOR SELECT
  USING (public.rls_can_see_item(board_item_id));

REVOKE ALL ON public.curation_reviewer_assignments FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE ON public.curation_reviewer_assignments FROM authenticated;
GRANT SELECT ON public.curation_reviewer_assignments TO authenticated;

COMMENT ON TABLE public.curation_reviewer_assignments IS
  '#2444 — quem foi designado parecerista de um card na curadoria, em qual rodada, com prazo, lembrete, escalonamento e substituicao. Escrita so por funcoes SECURITY DEFINER.';

-- (2) Quem pode ser designado para um card numa rodada, com a carga aberta de cada um ----
CREATE OR REPLACE FUNCTION public._curation_eligible_reviewers(p_item_id uuid, p_round integer)
RETURNS TABLE (member_id uuid, open_load integer, last_assigned_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT m.id,
         (SELECT count(*)::int
            FROM public.curation_reviewer_assignments a
            JOIN public.board_items b ON b.id = a.board_item_id
           WHERE a.reviewer_id = m.id
             AND a.released_at IS NULL
             AND b.curation_status = 'curation_pending'
             AND NOT EXISTS (SELECT 1 FROM public.curation_review_log r
                              WHERE r.board_item_id = a.board_item_id
                                AND r.curator_id = m.id
                                AND r.review_round = a.review_round)),
         (SELECT max(a.assigned_at) FROM public.curation_reviewer_assignments a WHERE a.reviewer_id = m.id)
    FROM public.members m
   WHERE m.member_status = 'active'
     AND m.is_active IS TRUE
     AND m.auth_id IS NOT NULL
     AND public.can_by_member(m.id, 'curate_content')
     AND public.can_by_member(m.id, 'participate_in_governance_review')
     -- quem escreveu nao da parecer sobre o proprio card
     AND m.id IS DISTINCT FROM (SELECT bi.assignee_id FROM public.board_items bi WHERE bi.id = p_item_id)
     AND NOT EXISTS (SELECT 1 FROM public.board_item_assignments bia
                      WHERE bia.item_id = p_item_id AND bia.member_id = m.id
                        AND bia.role IN ('author', 'contributor'))
     -- quem ja foi designado nesta rodada (ativo ou substituido) nao volta pela fila
     AND NOT EXISTS (SELECT 1 FROM public.curation_reviewer_assignments a
                      WHERE a.board_item_id = p_item_id AND a.review_round = p_round
                        AND a.reviewer_id = m.id);
$fn$;

-- (3) Designa UMA pessoa: registro, evento (a rodada que submit_curation_review le), Drive e aviso
CREATE OR REPLACE FUNCTION public._curation_assign_one(
  p_item_id uuid, p_round integer, p_reviewer_id uuid, p_source text, p_assigned_by uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_item     public.board_items%ROWTYPE;
  v_name     text;
  v_sla_days int;
  v_due      timestamptz;
  v_id       uuid;
BEGIN
  SELECT * INTO v_item FROM public.board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RETURN false; END IF;

  SELECT sla_days INTO v_sla_days FROM public.board_sla_config WHERE board_id = v_item.board_id;
  v_due := now() + make_interval(days => coalesce(v_sla_days, 7));

  INSERT INTO public.curation_reviewer_assignments
    (board_item_id, review_round, reviewer_id, source, assigned_by, due_at)
  VALUES (p_item_id, p_round, p_reviewer_id, p_source, p_assigned_by, v_due)
  ON CONFLICT (board_item_id, review_round, reviewer_id) DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN RETURN false; END IF;

  SELECT name INTO v_name FROM public.members WHERE id = p_reviewer_id;

  -- A designacao manual ja grava o proprio evento; so a automatica e a substituicao gravam aqui.
  IF p_source <> 'manual' THEN
    INSERT INTO public.board_lifecycle_events (board_id, item_id, action, reason, actor_member_id, review_round, sla_deadline)
    VALUES (v_item.board_id, p_item_id, 'reviewer_assigned',
            CASE p_source WHEN 'reassign' THEN 'Revisor redesignado (prazo vencido): ' ELSE 'Revisor designado (rodizio): ' END
              || coalesce(v_name, '?'),
            p_assigned_by, p_round, v_due);

    IF v_item.curation_status = 'curation_pending' THEN
      PERFORM public.enqueue_curation_drive_grant_for_member(p_item_id, p_reviewer_id, 'reviewer_assignment');
    END IF;
  END IF;

  PERFORM public.create_notification(
    p_reviewer_id,
    'curation_review_assigned',
    'Parecer de curadoria para você',
    '"' || v_item.title || '" aguarda o seu parecer no Comitê de Curadoria até '
      || to_char(v_due AT TIME ZONE 'America/Sao_Paulo', 'DD/MM') || '.',
    '/admin/curatorship',
    'board_item',
    p_item_id
  );
  RETURN true;
END;
$fn$;

-- (4) Completa a rodada do card ate o numero exigido de pareceristas ----------------------
CREATE OR REPLACE FUNCTION public._curation_auto_assign(p_item_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_item      public.board_items%ROWTYPE;
  v_required  int;
  v_last      int;
  v_round     int;
  v_active    int;
  v_assigned  int := 0;
  r           record;
BEGIN
  SELECT * INTO v_item FROM public.board_items WHERE id = p_item_id;
  IF NOT FOUND OR v_item.curation_status IS DISTINCT FROM 'curation_pending' THEN RETURN 0; END IF;
  -- Card arquivado nao e trabalho de curadoria; iniciativa confidencial fica fora da curadoria por padrao (ADR-0105).
  IF v_item.status = 'archived' THEN RETURN 0; END IF;
  IF EXISTS (SELECT 1 FROM public.project_boards pb JOIN public.initiatives i ON i.id = pb.initiative_id
              WHERE pb.id = v_item.board_id AND i.visibility = 'confidential') THEN
    RETURN 0;
  END IF;

  SELECT reviewers_required INTO v_required FROM public.board_sla_config WHERE board_id = v_item.board_id;
  v_required := coalesce(v_required, 2);

  -- Rodada: a ultima designada; se ela ja teve parecer, esta e uma volta do card e abre a proxima.
  SELECT max(review_round) INTO v_last
    FROM public.board_lifecycle_events WHERE item_id = p_item_id AND action = 'reviewer_assigned';
  IF v_last IS NULL THEN
    v_round := 1;
  ELSIF EXISTS (SELECT 1 FROM public.curation_review_log WHERE board_item_id = p_item_id AND review_round = v_last) THEN
    v_round := v_last + 1;
  ELSE
    v_round := v_last;
  END IF;

  SELECT count(*) INTO v_active FROM public.curation_reviewer_assignments
   WHERE board_item_id = p_item_id AND review_round = v_round AND released_at IS NULL;

  FOR r IN
    SELECT e.member_id FROM public._curation_eligible_reviewers(p_item_id, v_round) e
     ORDER BY e.open_load ASC, e.last_assigned_at ASC NULLS FIRST, e.member_id
     LIMIT greatest(v_required - v_active, 0)
  LOOP
    IF public._curation_assign_one(p_item_id, v_round, r.member_id, 'auto', NULL) THEN
      v_assigned := v_assigned + 1;
    END IF;
  END LOOP;
  RETURN v_assigned;
END;
$fn$;

-- (5) Gatilho: na TRANSICAO para curation_pending ----------------------------------------
CREATE OR REPLACE FUNCTION public.trg_curation_auto_assign_on_pending()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
BEGIN
  IF NEW.curation_status = 'curation_pending'
     AND OLD.curation_status IS DISTINCT FROM 'curation_pending' THEN
    PERFORM public._curation_auto_assign(NEW.id);
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_curation_auto_assign_on_pending ON public.board_items;
CREATE TRIGGER trg_curation_auto_assign_on_pending
  AFTER UPDATE OF curation_status ON public.board_items
  FOR EACH ROW EXECUTE FUNCTION public.trg_curation_auto_assign_on_pending();

-- (6) Job diario: lembrete 2 dias antes; no vencimento, troca e escalona -------------------
CREATE OR REPLACE FUNCTION public.curation_reviewer_sla_sweep()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  a            record;
  v_repl       uuid;
  v_reminded   int := 0;
  v_overdue    int := 0;
  v_replaced   int := 0;
  v_gp         record;
BEGIN
  -- Lembrete: prazo em ate 2 dias, parecer em aberto, ainda nao lembrado.
  FOR a IN
    SELECT ca.*, bi.title
      FROM public.curation_reviewer_assignments ca
      JOIN public.board_items bi ON bi.id = ca.board_item_id
     WHERE ca.released_at IS NULL AND ca.reminded_at IS NULL AND ca.overdue_at IS NULL
       AND bi.curation_status = 'curation_pending' AND bi.status IS DISTINCT FROM 'archived'
       AND ca.due_at > now() AND ca.due_at <= now() + interval '2 days'
       AND NOT EXISTS (SELECT 1 FROM public.curation_review_log r
                        WHERE r.board_item_id = ca.board_item_id AND r.curator_id = ca.reviewer_id
                          AND r.review_round = ca.review_round)
  LOOP
    PERFORM public.create_notification(
      a.reviewer_id, 'curation_review_assigned', 'Lembrete: parecer de curadoria',
      '"' || a.title || '" aguarda o seu parecer até '
        || to_char(a.due_at AT TIME ZONE 'America/Sao_Paulo', 'DD/MM') || '.',
      '/admin/curatorship', 'board_item', a.board_item_id);
    UPDATE public.curation_reviewer_assignments SET reminded_at = now() WHERE id = a.id;
    v_reminded := v_reminded + 1;
  END LOOP;

  -- Vencido: troca por um curador livre (se houver) e avisa quem gere a plataforma, uma vez.
  FOR a IN
    SELECT ca.*, bi.title, m.name AS reviewer_name
      FROM public.curation_reviewer_assignments ca
      JOIN public.board_items bi ON bi.id = ca.board_item_id
      JOIN public.members m ON m.id = ca.reviewer_id
     WHERE ca.released_at IS NULL AND ca.overdue_at IS NULL
       AND bi.curation_status = 'curation_pending' AND bi.status IS DISTINCT FROM 'archived'
       AND ca.due_at <= now()
       AND NOT EXISTS (SELECT 1 FROM public.curation_review_log r
                        WHERE r.board_item_id = ca.board_item_id AND r.curator_id = ca.reviewer_id
                          AND r.review_round = ca.review_round)
  LOOP
    UPDATE public.curation_reviewer_assignments SET overdue_at = now() WHERE id = a.id;
    v_overdue := v_overdue + 1;

    SELECT e.member_id INTO v_repl
      FROM public._curation_eligible_reviewers(a.board_item_id, a.review_round) e
     ORDER BY e.open_load ASC, e.last_assigned_at ASC NULLS FIRST, e.member_id
     LIMIT 1;

    IF v_repl IS NOT NULL THEN
      UPDATE public.curation_reviewer_assignments SET released_at = now() WHERE id = a.id;
      PERFORM public._curation_assign_one(a.board_item_id, a.review_round, v_repl, 'reassign', NULL);
      v_replaced := v_replaced + 1;
    END IF;

    FOR v_gp IN
      SELECT m.id FROM public.members m
       WHERE m.member_status = 'active' AND m.auth_id IS NOT NULL
         AND public.can_by_member(m.id, 'manage_platform')
    LOOP
      PERFORM public.create_notification(
        v_gp.id, 'curation_review_overdue', 'Parecer de curadoria vencido',
        '"' || a.title || '": o parecer de ' || a.reviewer_name || ' venceu em '
          || to_char(a.due_at AT TIME ZONE 'America/Sao_Paulo', 'DD/MM') || '. '
          || CASE WHEN v_repl IS NOT NULL THEN 'Outro curador foi designado.'
                  ELSE 'Nenhum curador livre para substituir: precisa de decisão.' END,
        '/admin/curatorship', 'board_item', a.board_item_id);
    END LOOP;
    v_repl := NULL;
  END LOOP;

  RETURN jsonb_build_object('reminded', v_reminded, 'overdue', v_overdue, 'replaced', v_replaced, 'ran_at', now());
END;
$fn$;

REVOKE ALL ON FUNCTION public._curation_eligible_reviewers(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._curation_assign_one(uuid, integer, uuid, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._curation_auto_assign(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_curation_auto_assign_on_pending() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.curation_reviewer_sla_sweep() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._curation_eligible_reviewers(uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public._curation_assign_one(uuid, integer, uuid, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._curation_auto_assign(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.curation_reviewer_sla_sweep() TO service_role;

-- (7) Designacao manual grava no mesmo registro -------------------------------------------
CREATE OR REPLACE FUNCTION public.assign_curation_reviewer(p_item_id uuid, p_reviewer_id uuid, p_round integer DEFAULT 1)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller   members%rowtype;
  v_reviewer members%rowtype;
  v_item     board_items%rowtype;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- ADR-0041: strict V4 catalog (committee work)
  IF NOT public.can_by_member(v_caller.id, 'participate_in_governance_review') THEN
    RAISE EXCEPTION 'Requires participate_in_governance_review';
  END IF;

  SELECT * INTO v_reviewer FROM members WHERE id = p_reviewer_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Reviewer not found'; END IF;
  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content').
  -- Target-user check (reviewer, not caller). co_gp legacy path preserved as V3.
  IF NOT (
    public.can_by_member(p_reviewer_id, 'curate_content')
    OR 'co_gp' = ANY(coalesce(v_reviewer.designations, array[]::text[]))
  ) THEN
    RAISE EXCEPTION 'Reviewer must have curate_content authority or co_gp designation';
  END IF;

  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;

  -- #785 PR-3: confidential gate (curator without engagement cannot act on confidential items)
  IF NOT public.rls_can_see_board(v_item.board_id) THEN
    RAISE EXCEPTION 'Item not found';
  END IF;

  IF p_reviewer_id = v_item.assignee_id THEN
    IF NOT EXISTS (
      SELECT 1 FROM board_lifecycle_events
      WHERE item_id = p_item_id AND action = 'reviewer_assigned'
        AND review_round = p_round AND actor_member_id IS DISTINCT FROM p_reviewer_id
    ) THEN
      RAISE EXCEPTION 'Cannot designate item author as sole reviewer';
    END IF;
  END IF;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id, review_round)
  VALUES (v_item.board_id, p_item_id, 'reviewer_assigned',
    'Revisor designado: ' || v_reviewer.name, v_caller.id, p_round);

  -- #301 / ADR-0108: give the assigned reviewer temporary Drive access to the submitted artifacts
  -- (only while the item is actually in curation; otherwise the entry trigger covers the committee).
  IF v_item.curation_status = 'curation_pending' THEN
    PERFORM public.enqueue_curation_drive_grant_for_member(p_item_id, p_reviewer_id, 'reviewer_assignment');
  END IF;

  -- #2444: a designacao manual entra no mesmo registro do rodizio, com prazo, lembrete e aviso.
  PERFORM public._curation_assign_one(p_item_id, p_round, p_reviewer_id, 'manual', v_caller.id);
END;
$function$;

-- (8) Os dois tipos novos de aviso entram catalogados (ADR-0022), nunca pelo ELSE --------
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
    ELSE 'digest_weekly'
  END;
$function$;

-- (9) Agendamento diario. 12:17 UTC = 09:17 em Sao Paulo; minuto deslocado de proposito (#1844).
SELECT cron.unschedule('curation-reviewer-sla-daily')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'curation-reviewer-sla-daily');

SELECT cron.schedule(
  'curation-reviewer-sla-daily',
  '17 12 * * *',
  $cron$SELECT public.curation_reviewer_sla_sweep();$cron$
);

-- (10) Carga inicial: o que JA esta na fila recebe designacao agora (arquivado e confidencial
--      ficam de fora pela propria funcao).
SELECT public._curation_auto_assign(bi.id)
  FROM public.board_items bi
 WHERE bi.curation_status = 'curation_pending';
