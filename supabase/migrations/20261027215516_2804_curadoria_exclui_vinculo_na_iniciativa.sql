-- #2804: conflito de interesse na curadoria. Em card de board de LINHA DE PESQUISA (initiatives.kind =
-- 'research_tribe'), quem tem vinculo ativo (qualquer papel) nessa linha nao recebe o card no sorteio, nao e
-- designado a mao e nao registra parecer sobre ele. Nas demais iniciativas vale a declaracao e a abstencao do
-- curador, fora da plataforma.
-- Base: Codigo de Etica e Conduta Profissional do PMI (ed. 2025), 4.3.1 e 4.3.2.
--
-- Corpos de partida: os vivos em 27/10/2026, conferidos pelo md5 do prosrc normalizado:
--   _curation_eligible_reviewers  cdfd56f2b8dd1cba4b7510924b009e5f  (captura 20260924140723_2444_rodizio_de_pareceristas_na_curadoria)
--   assign_curation_reviewer      9b14f85e0001aa23a18f8ed3ae4bac81  (captura 20260924140723_2444_rodizio_de_pareceristas_na_curadoria)
--   submit_curation_review        ded2222b26f1423dc09db3b64b695686  (captura 20261010043051_2621_parecer_e_linha_do_tempo)
-- Assinaturas, SECURITY DEFINER e search_path inalterados: CREATE OR REPLACE. Os GRANTs ficam como estao.
-- Designacoes ativas que ja estejam em conflito NAO sao desfeitas aqui; em 27/10/2026 eram 0.

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
                        AND a.reviewer_id = m.id)
     -- #2804: em card de LINHA DE PESQUISA, quem tem vinculo ativo nessa linha nao da parecer sobre ele
     -- (conflito de interesse, Codigo de Etica do PMI 4.3.1 e 4.3.2); nas demais iniciativas vale a declaracao
     AND NOT EXISTS (SELECT 1
                       FROM public.board_items bi
                       JOIN public.project_boards pb ON pb.id = bi.board_id
                       JOIN public.initiatives i ON i.id = pb.initiative_id
                       JOIN public.engagements e ON e.initiative_id = pb.initiative_id
                      WHERE bi.id = p_item_id
                        AND i.kind = 'research_tribe'
                        AND e.person_id = m.person_id
                        AND e.status = 'active');
$fn$;

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

  -- #2804: em card de linha de pesquisa, quem tem vinculo ativo nela nao e designado (conflito de interesse)
  IF EXISTS (SELECT 1 FROM project_boards pb
               JOIN initiatives i ON i.id = pb.initiative_id
               JOIN engagements e ON e.initiative_id = pb.initiative_id
              WHERE pb.id = v_item.board_id
                AND i.kind = 'research_tribe'
                AND e.person_id = v_reviewer.person_id
                AND e.status = 'active') THEN
    RAISE EXCEPTION 'Reviewer has an active engagement in this research line (conflict of interest)';
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

CREATE OR REPLACE FUNCTION public.submit_curation_review(p_item_id uuid, p_decision text, p_criteria_scores jsonb DEFAULT '{}'::jsonb, p_feedback_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller   members%rowtype;
  v_item     board_items%rowtype;
  v_log_id   uuid;
  v_pub_id   uuid;
  v_origin_board uuid;
  v_required int;
  v_current_round int;
  v_approved_count int;
  v_criteria text[];
  v_key text;
  v_score int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF NOT public.can_by_member(v_caller.id, 'participate_in_governance_review') THEN
    RAISE EXCEPTION 'Requires participate_in_governance_review';
  END IF;

  IF p_decision NOT IN ('approved', 'returned_for_revision', 'rejected') THEN
    RAISE EXCEPTION 'Invalid decision: %', p_decision;
  END IF;

  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Board item not found'; END IF;

  -- #785 PR-3 parity (mirror assign_curation_reviewer): a curator without
  -- engagement on a confidential initiative cannot act on its board items.
  IF NOT public.rls_can_see_board(v_item.board_id) THEN
    RAISE EXCEPTION 'Board item not found';
  END IF;

  IF v_item.curation_status <> 'curation_pending' THEN
    RAISE EXCEPTION 'Item is not in curation_pending status';
  END IF;

  -- #2804: em card de linha de pesquisa, quem tem vinculo ativo nela nao registra parecer (conflito de interesse)
  IF EXISTS (SELECT 1 FROM project_boards pb
               JOIN initiatives i ON i.id = pb.initiative_id
               JOIN engagements e ON e.initiative_id = pb.initiative_id
              WHERE pb.id = v_item.board_id
                AND i.kind = 'research_tribe'
                AND e.person_id = v_caller.person_id
                AND e.status = 'active') THEN
    RAISE EXCEPTION 'You have an active engagement in this research line (conflict of interest)';
  END IF;

  IF p_criteria_scores IS NOT NULL AND p_criteria_scores <> '{}'::jsonb THEN
    FOR v_key IN SELECT unnest(ARRAY['clarity','originality','adherence','relevance','ethics'])
    LOOP
      v_score := (p_criteria_scores->>v_key)::int;
      IF v_score IS NULL OR v_score < 1 OR v_score > 5 THEN
        RAISE EXCEPTION 'Invalid score for %: must be 1-5', v_key;
      END IF;
    END LOOP;
  END IF;

  SELECT coalesce(max(review_round), 1) INTO v_current_round
  FROM board_lifecycle_events
  WHERE item_id = p_item_id AND action = 'reviewer_assigned';

  IF EXISTS (
    SELECT 1 FROM curation_review_log
    WHERE board_item_id = p_item_id
      AND curator_id = v_caller.id
      AND review_round = v_current_round
  ) THEN
    RAISE EXCEPTION 'You have already submitted a review for this item in round %', v_current_round;
  END IF;

  SELECT reviewers_required INTO v_required
  FROM board_sla_config WHERE board_id = v_item.board_id;
  v_required := coalesce(v_required, 2);

  INSERT INTO curation_review_log (
    board_item_id, curator_id, criteria_scores, feedback_notes,
    decision, due_date, completed_at, review_round
  ) VALUES (
    p_item_id, v_caller.id, p_criteria_scores, p_feedback_notes,
    p_decision, v_item.curation_due_at, now(), v_current_round
  ) RETURNING id INTO v_log_id;

  INSERT INTO board_lifecycle_events
    (board_id, item_id, action, reason, actor_member_id, review_score, review_round, sla_deadline)
  VALUES
    (v_item.board_id, p_item_id, 'curation_review',
     p_decision || ': ' || coalesce(p_feedback_notes, ''),
     v_caller.id, p_criteria_scores, v_current_round, v_item.curation_due_at);

  IF p_decision = 'approved' THEN
    SELECT count(DISTINCT curator_id) INTO v_approved_count
    FROM curation_review_log
    WHERE board_item_id = p_item_id
      AND decision = 'approved'
      AND review_round = v_current_round;

    IF v_approved_count >= v_required THEN
      v_pub_id := public.publish_board_item_from_curation(p_item_id);
      INSERT INTO board_lifecycle_events
        (board_id, item_id, action, reason, actor_member_id, review_round)
      VALUES
        (v_item.board_id, p_item_id, 'curation_approved',
         v_approved_count || '/' || v_required || ' revisores aprovaram',
         v_caller.id, v_current_round);
    END IF;

  -- #2621: o parecer mora no curation_review_log (por rodada, com data) e chega ao autor pelo aviso
  -- da decisao e pela linha do tempo do card; nao e mais colado ao fim da descricao do artefato.
  ELSIF p_decision = 'returned_for_revision' THEN
    UPDATE board_items SET
      curation_status = 'draft',
      status = 'review',
      updated_at = now()
    WHERE id = p_item_id;

  ELSIF p_decision = 'rejected' THEN
    UPDATE board_items SET
      curation_status = 'draft',
      status = 'archived',
      updated_at = now()
    WHERE id = p_item_id;
  END IF;

  RETURN v_log_id;
END;
$function$;
