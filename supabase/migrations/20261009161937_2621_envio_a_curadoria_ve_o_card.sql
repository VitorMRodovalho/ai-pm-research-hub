-- =====================================================================================
-- #2621 -- submit_for_curation passa a exigir que quem envia VEJA o card e, no caminho do
-- lider de tribo, que lidere a iniciativa do card
--
-- MEDIDO em 2026-10-09 (corpo vivo == captura 20260924151234, md5 normalizado):
--   - submit_for_curation nao tinha portao de visibilidade (#785, ADR-0105), ao contrario de
--     submit_curation_review e assign_curation_reviewer: um lider de tribo enviava card de
--     iniciativa CONFIDENCIAL em que nao esta engajado. Ha 2 iniciativas confidenciais hoje.
--   - o ramo "lider de tribo" (ADR-0041 Path Y) testava so operational_role = 'tribe_leader',
--     GLOBAL: qualquer lider enviava card de qualquer tribo. O portao de visibilidade sozinho nao
--     fecha isso, porque card de iniciativa nao confidencial e visivel a todo membro.
--   - historico: 3 envios registrados (submitted_for_curation); 0 de lider em card de outra
--     iniciativa. Os 14 membros com operational_role = 'tribe_leader' tem engajamento ativo
--     role = 'leader'. A mudanca so RESTRINGE: ninguem ganha capacidade.
--
-- O QUE MUDA (duas partes separaveis; a decisao do GP escolhe (a) ou (a)+(b))
--   (a) visibilidade: depois de achar o item, rls_can_see_board(board do item), com a mesma
--       mensagem de item ausente, para nao revelar que o card existe.
--   (b) escopo do lider: quem nao tem participate_in_governance_review so envia card da
--       iniciativa em que tem engajamento ativo role = 'leader' (o mesmo predicado de
--       complete_leader_review). Governanca segue sem escopo.
--   As duas mensagens novas casam padroes ja traduzidos na tela (REVIEW_ERRORS do CardDetail:
--   '^Item not found' e '^Requires '), entao o guard #2456 segue verde sem mudar a tela.
--
-- Assinatura, SECURITY DEFINER, search_path e grants nao mudam (CREATE OR REPLACE).
-- ROLLBACK: reaplicar a captura 20260924151234 de submit_for_curation.
-- =====================================================================================

CREATE OR REPLACE FUNCTION public.submit_for_curation(p_item_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller members%rowtype;
  v_item board_items%rowtype;
  v_sla_days int;
  v_is_gov boolean;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- ADR-0041: V4 catalog OR Path Y (tribe_leader operational handoff)
  v_is_gov := public.can_by_member(v_caller.id, 'participate_in_governance_review');
  IF NOT (
    v_is_gov
    OR v_caller.operational_role = 'tribe_leader'
  ) THEN
    RAISE EXCEPTION 'Requires participate_in_governance_review or tribe_leader';
  END IF;

  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;

  -- #2621 (a): paridade #785 com submit_curation_review e assign_curation_reviewer. Card de
  -- iniciativa confidencial em que quem envia nao esta engajado responde como item ausente.
  IF NOT public.rls_can_see_board(v_item.board_id) THEN
    RAISE EXCEPTION 'Item not found';
  END IF;

  -- #2621 (b): Path Y escopado. O lider de tribo envia so card da iniciativa que lidera; mesmo
  -- predicado de complete_leader_review (engajamento ativo role = 'leader' na iniciativa do board).
  IF NOT v_is_gov AND NOT EXISTS (
    SELECT 1
    FROM project_boards pb
    JOIN engagements e ON e.initiative_id = pb.initiative_id
    JOIN persons p ON p.id = e.person_id
    WHERE pb.id = v_item.board_id
      AND e.status = 'active'
      AND e.role = 'leader'
      AND p.auth_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Requires tribe leadership of the card''s initiative or participate_in_governance_review';
  END IF;

  IF v_item.curation_status NOT IN ('leader_review', 'draft') THEN
    RAISE EXCEPTION 'Item must be in leader_review or draft status';
  END IF;

  -- #2447: so artefato publicavel entra na fila da curadoria.
  IF NOT public._board_item_needs_curation(p_item_id) THEN
    RAISE EXCEPTION 'Só artefato publicável entra na curadoria: marque o card como entregável de portfólio e escolha um tipo de publicação.';
  END IF;

  SELECT sla_days INTO v_sla_days FROM board_sla_config WHERE board_id = v_item.board_id;

  UPDATE board_items
  SET curation_status = 'curation_pending',
      curation_due_at = now() + make_interval(days => coalesce(v_sla_days, 7)),
      updated_at = now()
  WHERE id = p_item_id;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, actor_member_id, sla_deadline)
  VALUES (v_item.board_id, p_item_id, 'submitted_for_curation', v_caller.id,
    now() + make_interval(days => coalesce(v_sla_days, 7)));
END;
$function$;
