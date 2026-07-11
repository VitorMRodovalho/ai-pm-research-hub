-- #1289 — mover card entre boards: (1) SEGURANCA — move_item_to_board nao tinha gate NENHUM
-- (qualquer authenticated movia QUALQUER card para QUALQUER board; SECURITY DEFINER bypassa RLS =
-- privilege escalation). (2) O #1289 pede "respeitar can()/visibilidade (confidencial ADR-0105)".
--
-- Fix: helper board_write_authority(member, board) — a MESMA disjuncao do move_board_item
-- (GP / lider-de-tribo / comms-do-dominio / lider-da-iniciativa / write_board), reusada para os
-- boards de ORIGEM e DESTINO. move_item_to_board agora exige: destino VISIVEL (rls_can_see_initiative)
-- + autoridade de escrita no destino, E autoridade no origem OU posse do card. Fail-closed.

-- ═══════════════════════════════════════════════════════════════════════════
-- Helper: autoridade de escrita em um board (espelha o gate do move_board_item)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.board_write_authority(p_member_id uuid, p_board_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor record;
  v_board record;
  v_board_legacy_tribe_id int;
BEGIN
  SELECT * INTO v_actor FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN RETURN false; END IF;
  SELECT * INTO v_board FROM public.project_boards WHERE id = p_board_id;
  IF NOT FOUND THEN RETURN false; END IF;
  SELECT legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives WHERE id = v_board.initiative_id;

  RETURN (
    -- GP
    coalesce(v_actor.is_superadmin, false)
    OR v_actor.operational_role IN ('manager', 'deputy_manager')
    OR coalesce('co_gp' = ANY(v_actor.designations), false)
    -- tribe leader deste board
    OR (v_actor.operational_role = 'tribe_leader' AND v_actor.tribe_id = v_board_legacy_tribe_id)
    -- comms team num board de dominio 'communication'
    OR (coalesce(v_board.domain_key, '') = 'communication' AND (
         v_actor.operational_role = 'communicator'
         OR coalesce('comms_team' = ANY(v_actor.designations), false)
         OR coalesce('comms_leader' = ANY(v_actor.designations), false)
         OR coalesce('comms_member' = ANY(v_actor.designations), false)))
    -- lider/coordenador/manager/co_gp da iniciativa deste board
    OR (v_board.initiative_id IS NOT NULL AND v_actor.person_id IS NOT NULL AND EXISTS (
         SELECT 1 FROM public.engagements e
         WHERE e.person_id = v_actor.person_id
           AND e.initiative_id = v_board.initiative_id
           AND e.status = 'active'
           AND e.role IN ('leader', 'coordinator', 'manager', 'co_gp')))
    -- capacidade global write_board
    OR public.can_by_member(p_member_id, 'write_board')
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.board_write_authority(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.board_write_authority(uuid, uuid) TO service_role;
COMMENT ON FUNCTION public.board_write_authority(uuid, uuid) IS
  '#1289: autoridade de escrita num board (GP / lider-de-tribo / comms-do-dominio / lider-da-iniciativa / write_board). Helper interno reusado por move_item_to_board (origem+destino).';

-- ═══════════════════════════════════════════════════════════════════════════
-- Harden: move_item_to_board — gate de origem+destino + gate confidencial
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.move_item_to_board(p_item_id uuid, p_target_board_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_old_board_id uuid;
  v_max_pos int;
  v_actor uuid;
  v_target record;
  v_is_owner boolean;
BEGIN
  SELECT m.id INTO v_actor FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT board_id INTO v_old_board_id FROM public.board_items WHERE id = p_item_id;
  IF v_old_board_id IS NULL THEN
    RAISE EXCEPTION 'Item not found' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT * INTO v_target FROM public.project_boards WHERE id = p_target_board_id AND is_active = true;
  IF v_target.id IS NULL THEN
    RAISE EXCEPTION 'Target board not found' USING ERRCODE = 'no_data_found';
  END IF;

  -- #1289: destino VISIVEL (confidencial ADR-0105) + autoridade de escrita no destino
  IF NOT public.rls_can_see_initiative(v_target.initiative_id) THEN
    RAISE EXCEPTION 'Unauthorized: target board not visible' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.board_write_authority(v_actor, p_target_board_id) THEN
    RAISE EXCEPTION 'Unauthorized: requires write authority on the target board' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- origem: autoridade de escrita no board OU posse do card
  v_is_owner := EXISTS (SELECT 1 FROM public.board_items WHERE id = p_item_id AND (created_by = v_actor OR assignee_id = v_actor))
    OR EXISTS (SELECT 1 FROM public.board_item_assignments WHERE item_id = p_item_id AND member_id = v_actor);
  IF NOT public.board_write_authority(v_actor, v_old_board_id) AND NOT v_is_owner THEN
    RAISE EXCEPTION 'Unauthorized: requires write authority on the source board or card ownership' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT coalesce(max(position), -1) + 1 INTO v_max_pos
  FROM public.board_items WHERE board_id = p_target_board_id AND status = 'backlog';

  UPDATE public.board_items
  SET board_id = p_target_board_id, status = 'backlog', position = v_max_pos, updated_at = now()
  WHERE id = p_item_id;

  INSERT INTO public.board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES
    (v_old_board_id, p_item_id, 'moved_out', 'Movido para outro board', v_actor),
    (p_target_board_id, p_item_id, 'moved_in', 'Recebido de outro board', v_actor);
END;
$function$;
