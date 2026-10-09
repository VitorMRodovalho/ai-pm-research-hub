-- =====================================================================================
-- complete_leader_review: paridade de visibilidade com as demais RPCs da curadoria (#785)
--
-- Corpo montado sobre o vivo (md5 normalizado == captura 20260924184829, conferido em 09/10).
-- Assinatura, SECURITY DEFINER, search_path e grants nao mudam (CREATE OR REPLACE).
-- ROLLBACK: reaplicar a captura 20260924184829 de complete_leader_review.
-- =====================================================================================

CREATE OR REPLACE FUNCTION public.complete_leader_review(p_item_id uuid, p_decision text, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_item   board_items%ROWTYPE;
  v_initiative_id uuid;
  v_is_leader boolean := false;
  v_author record;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_decision NOT IN ('approved', 'returned', 'waived') THEN
    RAISE EXCEPTION 'Decision must be one of: approved, returned, waived (got: %)', p_decision;
  END IF;

  SELECT * INTO v_item FROM public.board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found: %', p_item_id; END IF;

  -- Paridade com as demais RPCs da curadoria (#785).
  IF NOT public.rls_can_see_board(v_item.board_id) THEN
    RAISE EXCEPTION 'Item not found: %', p_item_id;
  END IF;

  IF v_item.curation_status NOT IN ('leader_review', 'draft') THEN
    RAISE EXCEPTION 'Leader review can only be completed from leader_review or draft (current: %)', v_item.curation_status;
  END IF;

  SELECT pb.initiative_id INTO v_initiative_id
    FROM public.project_boards pb WHERE pb.id = v_item.board_id;

  IF v_initiative_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.persons p ON p.id = e.person_id
    WHERE e.initiative_id = v_initiative_id
      AND e.status = 'active'
      AND e.role = 'leader'
      AND p.auth_id = auth.uid()
  ) THEN
    v_is_leader := true;
  ELSIF public.can_by_member(v_caller.id, 'participate_in_governance_review') THEN
    v_is_leader := true;
  END IF;

  IF NOT v_is_leader THEN
    RAISE EXCEPTION 'Leader review requires tribe leadership of card''s initiative or governance reviewer authority';
  END IF;

  -- #2447: so artefato publicavel segue para a curadoria. Devolver continua sempre possivel,
  -- e e a saida para os cards que entraram no fluxo sem ser artefato.
  IF p_decision IN ('approved', 'waived') AND NOT public._board_item_needs_curation(p_item_id) THEN
    RAISE EXCEPTION 'Só artefato publicável segue para a curadoria: classifique o card como entregável de portfólio com um tipo de publicação, ou use Devolver.';
  END IF;

  IF p_decision IN ('approved', 'waived') THEN
    UPDATE public.board_items
    SET curation_status = 'curation_pending',
        leader_review_completed_at = now(),
        leader_review_decision = p_decision,
        leader_review_notes = p_notes,
        leader_reviewer_id = v_caller.id,
        updated_at = now()
    WHERE id = p_item_id;

    -- Use distinct action for analytics clarity (added to CHECK in B1 fix)
    INSERT INTO public.board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES (
      v_item.board_id,
      p_item_id,
      'leader_review_completed',
      'Leader review ' || p_decision || ' → submetido à curadoria' || COALESCE(' — ' || p_notes, ''),
      v_caller.id
    );
  ELSIF p_decision = 'returned' THEN
    -- p197 fix H2: ALSO reset waiver state when returning. Without this,
    -- author who waived peer review then got returned would have stale
    -- "waived" flag persisting and potentially skip peer review on retry.
    UPDATE public.board_items
    SET curation_status = 'draft',
        leader_review_completed_at = now(),
        leader_review_decision = p_decision,
        leader_review_notes = p_notes,
        leader_reviewer_id = v_caller.id,
        peer_review_completed_at = NULL,
        peer_review_summary = NULL,
        peer_review_waived = false,
        peer_review_waived_reason = NULL,
        updated_at = now()
    WHERE id = p_item_id;

    INSERT INTO public.board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES (
      v_item.board_id,
      p_item_id,
      'leader_review_completed',
      'Leader review devolvido ao autor' || COALESCE(' — ' || p_notes, ''),
      v_caller.id
    );

    -- #2444: a devolucao avisa TODOS os autores do card (board_item_assignments author/contributor,
    -- mais o assignee legado), na hora e com link para o quadro. Antes ia so para assignee_id, a
    -- coluna legada e singular (mesma classe do #1903), e como card_moved, que cai no digest semanal.
    -- p197 fix H1 mantido: source_type = 'board_item' literal.
    FOR v_author IN
      SELECT DISTINCT x.mid FROM (
        SELECT v_item.assignee_id AS mid
        UNION
        SELECT bia.member_id FROM public.board_item_assignments bia
         WHERE bia.item_id = p_item_id AND bia.role IN ('author', 'contributor')
      ) x
      WHERE x.mid IS NOT NULL AND x.mid IS DISTINCT FROM v_caller.id
    LOOP
      PERFORM public.create_notification(
        v_author.mid,
        'leader_review_returned',
        'O líder devolveu a peça para ajustes',
        '"' || v_item.title || '": ' || COALESCE(p_notes, 'sem nota do líder.'),
        '/boards/' || v_item.board_id::text,
        'board_item',
        v_item.id
      );
    END LOOP;
  END IF;
END;
$function$;
