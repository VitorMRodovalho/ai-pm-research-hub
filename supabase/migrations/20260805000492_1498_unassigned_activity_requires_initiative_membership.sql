-- #1498 — atividade sem responsavel exige pertencimento a iniciativa do board.
--
-- Estado anterior: v_is_activity_owner := v_item.assigned_to = v_caller.id OR v_item.assigned_to IS NULL.
-- O ramo IS NULL liberava QUALQUER membro autenticado, sem checar escopo de board: dava para concluir
-- atividade sem responsavel em board de outra tribo. Medido em 2026-07-28: 207 atividades abertas nessa
-- condicao, distribuidas por 12 dos 18 boards.
--
-- Estado novo: o ramo IS NULL passa a exigir engagement ativo na iniciativa do board. Preserva o uso
-- legitimo (atividade coletiva do card, concluida por quem e da iniciativa) e fecha o cross-tribe.
-- Medido no historico: das 39 conclusoes de atividade sem responsavel ja ocorridas, 36 foram de quem
-- tinha engagement ativo na iniciativa e 37 de quem tem write_board; as 2 restantes sao do mesmo board
-- e de alguem que tinha engagement naquela iniciativa na data do ato (encerrado depois).
--
-- Null-safety: com assigned_to NULL, `v_item.assigned_to = v_caller.id` avalia NULL. Sem o coalesce,
-- `NULL OR false` = NULL e o `IF NOT ... THEN RAISE` nao dispara, o que reabriria o buraco em silencio
-- justamente no caso que esta migration fecha.
--
-- Escolha da fonte: public.auth_engagements, a mesma view que rls_can_see_initiative e
-- rls_can_for_initiative ja consultam de dentro de SECURITY DEFINER. Filtra status = 'active'
-- explicitamente porque a view tambem expoe 'suspended'.

CREATE OR REPLACE FUNCTION public.complete_checklist_item(p_checklist_item_id uuid, p_completed boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_item record;
  v_card record;
  v_board record;
  v_board_legacy_tribe_id int;
  v_is_gp boolean;
  v_is_leader boolean;
  v_is_card_owner boolean;
  v_is_activity_owner boolean;
  v_is_initiative_member boolean;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_item FROM board_item_checklists WHERE id = p_checklist_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Checklist item not found'; END IF;

  SELECT * INTO v_card FROM board_items WHERE id = v_item.board_item_id;
  SELECT * INTO v_board FROM project_boards WHERE id = v_card.board_id;

  -- ADR-0015 Phase 3d: project_boards.tribe_id dropado; derivar via initiative
  SELECT legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives WHERE id = v_board.initiative_id;

  v_is_gp := coalesce(v_caller.is_superadmin, false)
    OR v_caller.operational_role IN ('manager', 'deputy_manager')
    OR coalesce('co_gp' = ANY(v_caller.designations), false);

  v_is_leader := v_caller.operational_role = 'tribe_leader'
    AND v_caller.tribe_id = v_board_legacy_tribe_id;

  -- #1498: pertencimento a iniciativa do board (engagement ativo), nao write_board.
  v_is_initiative_member := v_board.initiative_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.auth_engagements ae
    WHERE ae.auth_id = auth.uid()
      AND ae.initiative_id = v_board.initiative_id
      AND ae.status = 'active'
  );

  v_is_card_owner := v_card.assignee_id = v_caller.id;
  v_is_activity_owner := coalesce(v_item.assigned_to = v_caller.id, false)
    OR (v_item.assigned_to IS NULL AND v_is_initiative_member);

  IF NOT public.can_by_member(v_caller.id, 'write_board') AND NOT v_is_card_owner AND NOT v_is_activity_owner THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission, card/activity ownership, or engagement in the initiative';
  END IF;

  UPDATE board_item_checklists
  SET is_completed = p_completed,
      completed_at = CASE WHEN p_completed THEN now() ELSE NULL END,
      completed_by = CASE WHEN p_completed THEN v_caller.id ELSE NULL END
  WHERE id = p_checklist_item_id;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (v_card.board_id, v_card.id,
    CASE WHEN p_completed THEN 'activity_completed' ELSE 'activity_reopened' END,
    v_item.text || CASE WHEN p_completed THEN ' (concluída por ' || v_caller.name || ')' ELSE ' (reaberta)' END,
    v_caller.id);
END;
$function$;
