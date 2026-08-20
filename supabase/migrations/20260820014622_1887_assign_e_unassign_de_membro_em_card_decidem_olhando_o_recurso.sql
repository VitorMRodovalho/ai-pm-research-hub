-- #1887: assign/unassign de membro em card decidem olhando o RECURSO.
--
-- Defeito: o gate de assign_member_to_item tem 5 ramos e NENHUM consulta `write_board`,
-- a capacidade canonica de escrita no board. Uma pesquisadora com write_board=true so
-- conseguia se auto-atribuir como `author`; atribuir qualquer outra pessoa levantava
-- excecao (PostgREST -> 400). Medido em 19/08: 69 dos 94 membros ativos tem write_board,
-- e 52 deles eram barrados por este gate.
--
-- Correcao: resolver a tribo do board (via initiatives.legacy_tribe_id, mesmo formato que
-- update_board_item e move_board_item ja usam) e decidir contra ELA, com
-- rls_can_for_tribe('write_board', <tribo do board>) -- que respeita o `scope` do catalogo
-- (initiative vs organization). NAO se acrescenta can_by_member('write_board') ao OR:
-- essa e capacidade organizacional SEM escopo, e deixaria uma pesquisadora de uma tribo
-- atribuir gente em card de qualquer outra -- o defeito que o epico #1780 aponta.
--
-- Boards sem tribo resolvida (legacy_tribe_id NULL) mantem exatamente o gate antigo:
-- onde nao ha recurso para escopar, nao se amplia.
--
-- unassign_member_from_item entra na mesma passagem por SIMETRIA: hoje ela tem apenas 2
-- ramos (participate_in_governance_review OR tribe_leader), entao sem isso o conserto
-- criaria uma porta so de ida -- inclusive board admin e o auto-atribuido como `author`
-- podiam atribuir e nao podiam remover. O gate passa a ser identico ao de assign.
--
-- O DEFAULT de p_role fica preservado: sem ele, CREATE OR REPLACE recusa com 42P13.

CREATE OR REPLACE FUNCTION public.assign_member_to_item(
  p_item_id uuid, p_member_id uuid, p_role text DEFAULT 'author'::text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller members%rowtype;
  v_item board_items%rowtype;
  v_board record;
  v_member members%rowtype;
  v_assignment_id uuid;
  v_is_board_admin boolean;
  v_board_legacy_tribe_id int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;
  SELECT pb.* INTO v_board FROM project_boards pb WHERE pb.id = v_item.board_id;

  -- #1887: resolve o recurso para poder escopar a autoridade.
  SELECT i.legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives i WHERE i.id = v_board.initiative_id;

  v_is_board_admin := EXISTS (
    SELECT 1 FROM board_members bm
    WHERE bm.board_id = v_board.id AND bm.member_id = v_caller.id AND bm.board_role = 'admin'
  );

  -- ADR-0041: V4 catalog OR Path Y (tribe_leader op-role / board_admin / self+author claim / curator+curation_reviewer)
  -- p200 ADR-0087: curator V3 designation -> V4 can_by_member('curate_content')
  -- #1887: + write_board ESCOPADO a tribo do board (nao a capacidade organizacional solta)
  IF NOT (
    public.can_by_member(v_caller.id, 'participate_in_governance_review')
    OR v_caller.operational_role = 'tribe_leader'
    OR v_is_board_admin
    OR (p_role = 'curation_reviewer' AND public.can_by_member(v_caller.id, 'curate_content'))
    OR (v_caller.id = p_member_id AND p_role = 'author')
    OR (v_board_legacy_tribe_id IS NOT NULL
        AND public.rls_can_for_tribe('write_board', v_board_legacy_tribe_id))
  ) THEN
    RAISE EXCEPTION 'Requires participate_in_governance_review, tribe_leader, board admin, curate_content (for curation_reviewer), self-claim (author), or write_board on this board''s tribe';
  END IF;

  IF p_role NOT IN ('author', 'reviewer', 'contributor', 'curation_reviewer') THEN
    RAISE EXCEPTION 'Invalid role: %. Must be author|reviewer|contributor|curation_reviewer', p_role;
  END IF;
  SELECT * INTO v_member FROM members WHERE id = p_member_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Member not found'; END IF;

  INSERT INTO board_item_assignments (item_id, member_id, role, assigned_by)
  VALUES (p_item_id, p_member_id, p_role, v_caller.id)
  ON CONFLICT (item_id, member_id, role) DO NOTHING
  RETURNING id INTO v_assignment_id;

  IF v_assignment_id IS NOT NULL THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_item.board_id, p_item_id, 'member_assigned',
      v_member.name || ' como ' || p_role, v_caller.id);
    PERFORM create_notification(
      p_member_id, 'card_assigned', 'board_item', p_item_id, v_item.title, v_caller.id,
      v_caller.name || ' atribuiu voce como ' || p_role
    );
  END IF;

  RETURN coalesce(v_assignment_id, (
    SELECT bia.id FROM board_item_assignments bia
    WHERE bia.item_id = p_item_id AND bia.member_id = p_member_id AND bia.role = p_role
  ));
END;
$$;

CREATE OR REPLACE FUNCTION public.unassign_member_from_item(
  p_item_id uuid, p_member_id uuid, p_role text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller members%rowtype;
  v_item board_items%rowtype;
  v_board record;
  v_member_name text;
  v_deleted int;
  v_is_board_admin boolean;
  v_board_legacy_tribe_id int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;
  SELECT pb.* INTO v_board FROM project_boards pb WHERE pb.id = v_item.board_id;

  -- #1887: resolve o recurso para poder escopar a autoridade.
  SELECT i.legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives i WHERE i.id = v_board.initiative_id;

  v_is_board_admin := EXISTS (
    SELECT 1 FROM board_members bm
    WHERE bm.board_id = v_board.id AND bm.member_id = v_caller.id AND bm.board_role = 'admin'
  );

  -- #1887: gate IDENTICO ao de assign_member_to_item -- quem pode atribuir pode remover.
  -- Antes eram apenas 2 ramos, o que deixava board admin e o auto-atribuido sem volta.
  IF NOT (
    public.can_by_member(v_caller.id, 'participate_in_governance_review')
    OR v_caller.operational_role = 'tribe_leader'
    OR v_is_board_admin
    OR (p_role = 'curation_reviewer' AND public.can_by_member(v_caller.id, 'curate_content'))
    OR (v_caller.id = p_member_id AND p_role = 'author')
    OR (v_board_legacy_tribe_id IS NOT NULL
        AND public.rls_can_for_tribe('write_board', v_board_legacy_tribe_id))
  ) THEN
    RAISE EXCEPTION 'Requires participate_in_governance_review, tribe_leader, board admin, curate_content (for curation_reviewer), self-claim (author), or write_board on this board''s tribe';
  END IF;

  SELECT name INTO v_member_name FROM members WHERE id = p_member_id;

  DELETE FROM board_item_assignments
  WHERE item_id = p_item_id AND member_id = p_member_id AND role = p_role;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  IF v_deleted > 0 THEN
    INSERT INTO board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES
      (v_item.board_id, p_item_id, 'member_unassigned',
       coalesce(v_member_name, 'membro') || ' removido de ' || p_role,
       v_caller.id);
  END IF;
END;
$$;
