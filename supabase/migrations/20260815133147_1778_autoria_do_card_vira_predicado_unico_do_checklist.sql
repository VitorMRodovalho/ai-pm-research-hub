-- #1778 — quem e dono do trabalho pode gerir as atividades DAQUELE card.
--
-- A regra de recurso ja existia, espalhada por tres corpos e com tres redacoes diferentes:
-- add/update/delete aceitavam "write_board OR assignee do card OR board_members admin/editor"
-- (e so o add tinha o ramo do time de comunicacao), assign aceitava board_members 'admin' e nao
-- 'editor'. Faltava a nocao que a queixa de campo usou: AUTOR e CONTRIBUIDOR do card, que vivem
-- em board_item_assignments e nenhuma das quatro olhava.
--
-- Este patch move a regra para UM predicado e faz as quatro chamarem. A reconciliacao tem duas
-- consequencias medidas em 15/08/2026, ambas praticamente vazias hoje e ambas intencionais:
--   - delete/update passam a ter o ramo de comunicacao que so o add tinha: 0 pessoas ativas com
--     perfil de comms estao sem write_board.
--   - assign passa a aceitar board_role 'editor' alem de 'admin': board_members tem 2 linhas na
--     plataforma inteira (1 admin, 1 editor).
-- O ganho pretendido: 1 pessoa ativa que e autor/contribuidor sem ser assignee e sem write_board
-- (de 3 ativas barradas hoje, as outras 2 sao assignee e ja passariam pela regra antiga).
--
-- complete_checklist_item NAO entra: a regra dele ja e mais larga (dono da atividade ou engajado
-- na iniciativa) e substitui-la aqui seria estreitar.
--
-- O REVOKE no fim fecha uma deriva antiga: as quatro nasceram com EXECUTE para PUBLIC, logo anon
-- alcancava as quatro por PostgREST. Fecham por dentro (auth.uid() nulo levanta excecao), mas a
-- porta estava aberta.

CREATE OR REPLACE FUNCTION public.can_manage_card_checklist(p_member_id uuid, p_card_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT p_member_id IS NOT NULL
     AND p_card_id IS NOT NULL
     AND (
       -- capacidade organizacional (o caminho de sempre)
       public.can_by_member(p_member_id, 'write_board')
       -- responsavel pelo card
       OR EXISTS (SELECT 1 FROM public.board_items bi
                  WHERE bi.id = p_card_id AND bi.assignee_id = p_member_id)
       -- autor ou contribuidor do card (#1778: dono do trabalho, ainda que sem capacidade)
       OR EXISTS (SELECT 1 FROM public.board_item_assignments ba
                  WHERE ba.item_id = p_card_id AND ba.member_id = p_member_id
                    AND ba.role IN ('author', 'contributor'))
       -- papel explicito no board
       OR EXISTS (SELECT 1 FROM public.board_items bi
                  JOIN public.board_members bm ON bm.board_id = bi.board_id
                  WHERE bi.id = p_card_id AND bm.member_id = p_member_id
                    AND bm.board_role IN ('admin', 'editor'))
       -- time de comunicacao no board de comunicacao
       OR EXISTS (SELECT 1 FROM public.board_items bi
                  JOIN public.project_boards pb ON pb.id = bi.board_id
                  JOIN public.members m ON m.id = p_member_id
                  WHERE bi.id = p_card_id
                    AND coalesce(pb.domain_key, '') = 'communication'
                    AND (m.operational_role = 'communicator'
                         OR m.designations && ARRAY['comms_team', 'comms_leader', 'comms_member']))
     );
$function$;

COMMENT ON FUNCTION public.can_manage_card_checklist(uuid, uuid) IS
  '#1778 — autoridade para gerir as atividades de UM card: capacidade write_board OU vinculo com o recurso (responsavel, autor/contribuidor, papel no board, time de comunicacao no board de comunicacao). Fonte unica das RPCs add/update/delete/assign_checklist_item e do fail-fast do card_checklist no MCP.';

CREATE OR REPLACE FUNCTION public.add_checklist_item(p_board_item_id uuid, p_text text, p_position smallint DEFAULT NULL::smallint, p_assigned_to uuid DEFAULT NULL::uuid, p_target_date date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_card record;
  v_new_id uuid;
  v_final_position smallint;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN RAISE EXCEPTION 'Unauthorized: authentication required'; END IF;

  IF coalesce(trim(p_text), '') = '' THEN
    RAISE EXCEPTION 'Checklist item text is required';
  END IF;

  SELECT * INTO v_card FROM board_items WHERE id = p_board_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Card not found: %', p_board_item_id; END IF;

  IF NOT public.can_manage_card_checklist(v_caller.id, p_board_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission, card ownership/authorship, board editor role, or comms team in communication board';
  END IF;

  IF p_position IS NULL THEN
    SELECT COALESCE(MAX(position), 0) + 1 INTO v_final_position
    FROM board_item_checklists WHERE board_item_id = p_board_item_id;
  ELSE
    v_final_position := p_position;
  END IF;

  INSERT INTO board_item_checklists (
    board_item_id, text, position, assigned_to, target_date,
    assigned_at, assigned_by
  )
  VALUES (
    p_board_item_id, p_text, v_final_position, p_assigned_to, p_target_date,
    CASE WHEN p_assigned_to IS NOT NULL THEN now() ELSE NULL END,
    CASE WHEN p_assigned_to IS NOT NULL THEN v_caller.id ELSE NULL END
  )
  RETURNING id INTO v_new_id;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (v_card.board_id, v_card.id, 'activity_added',
    p_text || CASE WHEN p_assigned_to IS NOT NULL
      THEN ' → ' || COALESCE((SELECT m.name FROM members m WHERE m.id = p_assigned_to), '?')
      ELSE '' END,
    v_caller.id);

  RETURN v_new_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_checklist_item(p_checklist_item_id uuid, p_text text DEFAULT NULL::text, p_position smallint DEFAULT NULL::smallint, p_target_date date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_item record;
  v_card record;
  v_old_text text;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: authentication required'; END IF;

  SELECT * INTO v_item FROM board_item_checklists WHERE id = p_checklist_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Checklist item not found'; END IF;

  SELECT * INTO v_card FROM board_items WHERE id = v_item.board_item_id;

  IF NOT public.can_manage_card_checklist(v_caller_id, v_item.board_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission, card ownership/authorship, or board editor role';
  END IF;

  IF p_text IS NOT NULL AND trim(p_text) = '' THEN
    RAISE EXCEPTION 'Text cannot be empty. Use delete_checklist_item to remove.';
  END IF;

  v_old_text := v_item.text;

  UPDATE board_item_checklists
  SET
    text = COALESCE(p_text, text),
    position = COALESCE(p_position, position),
    target_date = CASE WHEN p_target_date IS NOT NULL THEN p_target_date ELSE target_date END
  WHERE id = p_checklist_item_id;

  IF p_text IS NOT NULL AND p_text IS DISTINCT FROM v_old_text THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_card.board_id, v_card.id, 'activity_updated',
      v_old_text || ' → ' || p_text, v_caller_id);
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_checklist_item(p_checklist_item_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_item record;
  v_card record;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: authentication required'; END IF;

  SELECT * INTO v_item FROM board_item_checklists WHERE id = p_checklist_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Checklist item not found'; END IF;

  SELECT * INTO v_card FROM board_items WHERE id = v_item.board_item_id;

  IF NOT public.can_manage_card_checklist(v_caller_id, v_item.board_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission, card ownership/authorship, or board editor role';
  END IF;

  DELETE FROM board_item_checklists WHERE id = p_checklist_item_id;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (v_card.board_id, v_card.id, 'activity_deleted',
    v_item.text || COALESCE(' (motivo: ' || p_reason || ')', ''),
    v_caller_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.assign_checklist_item(p_checklist_item_id uuid, p_assigned_to uuid, p_target_date date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_item record;
  v_card record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_item FROM board_item_checklists WHERE id = p_checklist_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Checklist item not found'; END IF;

  SELECT * INTO v_card FROM board_items WHERE id = v_item.board_item_id;

  IF NOT public.can_manage_card_checklist(v_caller.id, v_item.board_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission or card-owner/author/board-admin role';
  END IF;

  UPDATE board_item_checklists
  SET assigned_to = p_assigned_to,
      target_date = COALESCE(p_target_date, target_date),
      assigned_at = now(),
      assigned_by = v_caller.id
  WHERE id = p_checklist_item_id;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (v_card.board_id, v_card.id, 'activity_assigned',
    v_item.text || ' → ' || coalesce((SELECT m.name FROM members m WHERE m.id = p_assigned_to), '?'),
    v_caller.id);
END;
$function$;

-- O predicado e lido pelo fail-fast do MCP (card_checklist), entao authenticated precisa executar.
REVOKE ALL ON FUNCTION public.can_manage_card_checklist(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_manage_card_checklist(uuid, uuid) TO authenticated, service_role;

-- Deriva antiga: as quatro nasceram com EXECUTE para PUBLIC.
REVOKE ALL ON FUNCTION public.add_checklist_item(uuid, text, smallint, uuid, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_checklist_item(uuid, text, smallint, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_checklist_item(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.assign_checklist_item(uuid, uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_checklist_item(uuid, text, smallint, uuid, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_checklist_item(uuid, text, smallint, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.delete_checklist_item(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.assign_checklist_item(uuid, uuid, date) TO authenticated, service_role;
