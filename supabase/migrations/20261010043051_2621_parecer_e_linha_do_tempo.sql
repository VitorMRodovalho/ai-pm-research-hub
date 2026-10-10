-- =====================================================================================
-- #2621: o parecer da curadoria mora no registro dela, e o card mostra a linha do tempo do envio
--
-- Decisao do GP (09/10/2026): parecer num lugar proprio, por rodada e com data, e linha do tempo do
-- envio no card. Hoje a devolucao e a rejeicao colam o parecer ao fim da descricao do artefato, e a
-- tela so carrega o historico da curadoria quando o card NAO esta em rascunho, que e justamente o
-- estado depois de uma devolucao.
--
-- O QUE MUDA
--   - submit_curation_review: devolucao e rejeicao deixam de alterar a descricao do card. O parecer
--     segue em curation_review_log (rodada, data, decisao, notas) e no aviso da decisao (#2629).
--   - get_item_curation_history: cada parecer traz a rodada; o retorno ganha 'submissions' (cada envio
--     a curadoria, com o prazo) e 'approved_at', para a linha do tempo. Portoes de leitura iguais.
--
-- Corpos montados sobre o vivo (md5 normalizado == capturas 20260805000449 e 20261005191818,
-- conferido em 09/10). Assinaturas, SECURITY DEFINER, search_path e grants nao mudam.
-- ROLLBACK: reaplicar as capturas 20260805000449 (submit_curation_review) e 20261005191818
--   (get_item_curation_history).
-- =====================================================================================

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

CREATE OR REPLACE FUNCTION public.get_item_curation_history(p_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  -- #785: confidential gate (item->board->initiative)
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN
    RETURN jsonb_build_object('reviews', '[]'::jsonb, 'assignments', '[]'::jsonb, 'sla_config', '{}'::jsonb, 'submissions', '[]'::jsonb, 'approved_at', NULL);
  END IF;

  IF NOT public.rls_can_see_item(p_item_id) THEN
    RETURN jsonb_build_object('reviews', '[]'::jsonb, 'assignments', '[]'::jsonb, 'sla_config', '{}'::jsonb, 'submissions', '[]'::jsonb, 'approved_at', NULL);
  END IF;
  SELECT jsonb_build_object(
    'reviews', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', crl.id,
        'curator_name', m.name,
        'curator_id', crl.curator_id,
        'decision', crl.decision,
        'criteria_scores', crl.criteria_scores,
        'feedback_notes', crl.feedback_notes,
        'completed_at', crl.completed_at,
        'review_round', crl.review_round
      ) ORDER BY crl.completed_at DESC)
      FROM curation_review_log crl
      LEFT JOIN members m ON m.id = crl.curator_id
      WHERE crl.board_item_id = p_item_id
    ), '[]'::jsonb),
    'assignments', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'reviewer_name', m.name,
        'reviewer_id', ble.actor_member_id,
        'round', ble.review_round,
        'assigned_at', ble.created_at,
        'sla_deadline', ble.sla_deadline
      ) ORDER BY ble.created_at DESC)
      FROM board_lifecycle_events ble
      LEFT JOIN members m ON m.id = ble.actor_member_id
      WHERE ble.item_id = p_item_id AND ble.action = 'reviewer_assigned'
    ), '[]'::jsonb),
    -- #2621: linha do tempo do envio para o autor: cada envio a curadoria (com o prazo) e a aprovacao.
    'submissions', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'at', ble.created_at,
        'sla_deadline', ble.sla_deadline
      ) ORDER BY ble.created_at)
      FROM board_lifecycle_events ble
      WHERE ble.item_id = p_item_id AND ble.action = 'submitted_for_curation'
    ), '[]'::jsonb),
    'approved_at', (
      SELECT max(ble.created_at) FROM board_lifecycle_events ble
      WHERE ble.item_id = p_item_id AND ble.action = 'curation_approved'
    ),
    'sla_config', coalesce((
      SELECT jsonb_build_object(
        'sla_days', sc.sla_days,
        'reviewers_required', sc.reviewers_required,
        'max_review_rounds', sc.max_review_rounds,
        'rubric_criteria', sc.rubric_criteria
      )
      FROM board_sla_config sc
      JOIN board_items bi ON bi.board_id = sc.board_id
      WHERE bi.id = p_item_id
    ), '{}'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
