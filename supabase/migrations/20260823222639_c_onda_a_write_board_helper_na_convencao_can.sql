-- Renomeia o helper do lote 1 para a convencao `_can_*`, e o motivo e um guard.
--
-- `rpc-v4-auth.test.mjs` (ADR-0011) exige que toda RPC SECDEF com portao de autorizacao chame
-- `can()` / `can_by_member()` / `rls_can()` -- ou um helper cujo NOME comece por `_can_`, que e
-- como `_can_manage_event` e `_can_sign_gate` sao reconhecidos. `_write_board_scope_ok` fugia da
-- convencao, entao `move_board_item` (que ficou sem nenhum outro `can*` no corpo) foi acusado de
-- autoridade V3.
--
-- Instancia exata de `reference-tornar-o-portao-mais-estrito-faz-o-guard-reprovar`: a CI ficou
-- vermelha por termos ESTREITADO a autoridade. A correcao e o nome, nao o guard: afrouxar
-- `usesV4Can` para aceitar um nome fora da convencao apagaria o sinal para todo mundo depois.
--
-- Nenhuma mudanca de comportamento: corpo identico, so o identificador muda. O helper antigo e
-- removido no fim, para nao deixar duas portas com a mesma funcao.

-- ── helper ───────────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._can_write_board(p_member_id uuid, p_board_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT
    -- Escopo organization/global vale para QUALQUER board: e o desenho dos seeds
    -- (manager, co_gp, deputy_manager, comms_leader, curator, volunteer/leader).
    public.can_org_by_member(p_member_id, 'write_board')
    -- ...e o escopado a iniciativa vale SO para a iniciativa DESTE board.
    --
    -- `p_resource_type` tem de ser NAO-NULO e diferente de 'tribe'. Com NULL, o Postgres nao
    -- curto-circuita o ramo legado `p_resource_type = 'tribe' AND ... (p_resource_id::text)::integer`
    -- e o cast ESTOURA para um UUID de iniciativa -- justamente no caminho de negacao, que e o
    -- que este helper precisa saber responder. Mesmo cuidado ja documentado em
    -- `_manage_event_scope_ok`.
    OR EXISTS (
      SELECT 1 FROM public.project_boards pb
      WHERE pb.id = p_board_id
        AND pb.initiative_id IS NOT NULL
        AND public.can_by_member(p_member_id, 'write_board', 'initiative', pb.initiative_id)
    );
$function$;

COMMENT ON FUNCTION public._can_write_board(uuid, uuid) IS
  'write_board escopado ao board: org/global vale para todos, initiative so para a iniciativa deste board. Substitui a forma resourceless can_by_member(x, write_board), que casava grant de QUALQUER iniciativa.';

REVOKE ALL ON FUNCTION public._can_write_board(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._can_write_board(uuid, uuid) TO authenticated, service_role;

-- ── 1/6 create_board_item: board em `p_board_id`, validado ('Board not found') ────────────────

CREATE OR REPLACE FUNCTION public.create_board_item(p_board_id uuid, p_title text, p_description text DEFAULT NULL::text, p_assignee_id uuid DEFAULT NULL::uuid, p_tags text[] DEFAULT '{}'::text[], p_due_date date DEFAULT NULL::date, p_status text DEFAULT 'backlog'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_id uuid;
  v_max_pos int;
  v_caller record;
  v_board record;
  v_board_legacy_tribe_id int;
  v_is_gp boolean;
  v_is_leader boolean;
  v_is_tribe_member boolean;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_board FROM project_boards WHERE id = p_board_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Board not found'; END IF;

  -- ADR-0015 Phase 3d: project_boards.tribe_id dropado; derivar via initiative
  SELECT legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives WHERE id = v_board.initiative_id;

  v_is_gp := coalesce(v_caller.is_superadmin, false)
    OR v_caller.operational_role IN ('manager', 'deputy_manager')
    OR coalesce('co_gp' = ANY(v_caller.designations), false);
  v_is_leader := v_caller.operational_role = 'tribe_leader' AND v_caller.tribe_id = v_board_legacy_tribe_id;
  v_is_tribe_member := v_caller.is_active AND v_caller.tribe_id = v_board_legacy_tribe_id;

  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
  IF NOT public._can_write_board(v_caller.id, p_board_id) AND NOT v_is_tribe_member AND NOT (
    (coalesce(v_board.domain_key, '') = 'communication' AND (
      v_caller.operational_role = 'communicator'
      OR coalesce('comms_team' = ANY(v_caller.designations), false)
      OR coalesce('comms_leader' = ANY(v_caller.designations), false)
      OR coalesce('comms_member' = ANY(v_caller.designations), false)
    ))
    OR (coalesce(v_board.domain_key, '') = 'publications_submissions' AND (
      v_caller.operational_role IN ('tribe_leader', 'communicator')
      OR public.can_by_member(v_caller.id, 'curate_content')
    ))
  ) THEN RAISE EXCEPTION 'Unauthorized to create cards on this board'; END IF;

  SELECT coalesce(max(position), -1) + 1 INTO v_max_pos FROM board_items WHERE board_id = p_board_id AND status = p_status;

  INSERT INTO board_items (board_id, title, description, assignee_id, tags, due_date, position, status, cycle, created_by)
  VALUES (p_board_id, p_title, p_description, COALESCE(p_assignee_id, v_caller.id), p_tags, p_due_date, v_max_pos, p_status, 3, v_caller.id)
  RETURNING id INTO v_id;

  INSERT INTO board_item_assignments (item_id, member_id, role, assigned_by)
  VALUES (v_id, v_caller.id, 'author', v_caller.id)
  ON CONFLICT DO NOTHING;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, new_status, actor_member_id)
  VALUES (p_board_id, v_id, 'created', p_status, v_caller.id);

  RETURN v_id;
END;
$function$;

-- ── 2/6 delete_board_item: board em `v_board_id`, validado ('Card not found') ─────────────────

CREATE OR REPLACE FUNCTION public.delete_board_item(p_item_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_board_id uuid;
  v_old_status text;
  v_actor uuid;
  v_authorized boolean;
BEGIN
  SELECT board_id, status INTO v_board_id, v_old_status
  FROM board_items WHERE id = p_item_id;
  IF v_board_id IS NULL THEN RAISE EXCEPTION 'Card not found'; END IF;

  SELECT m.id INTO v_actor FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Unauthorized: authentication required'; END IF;

  IF NOT public.rls_can_see_item(p_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access this card';
  END IF;

  v_authorized := public._can_write_board(v_actor, v_board_id)
    OR EXISTS (SELECT 1 FROM board_items bi WHERE bi.id = p_item_id AND bi.assignee_id = v_actor)
    OR EXISTS (SELECT 1 FROM board_members bm WHERE bm.board_id = v_board_id AND bm.member_id = v_actor AND bm.board_role IN ('admin', 'editor'));
  IF NOT v_authorized THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission, card ownership, or board editor role';
  END IF;

  UPDATE board_items
  SET status = 'archived', updated_at = now()
  WHERE id = p_item_id;

  INSERT INTO board_lifecycle_events
    (board_id, item_id, action, previous_status, new_status, reason, actor_member_id)
  VALUES
    (v_board_id, p_item_id, 'archived', v_old_status, 'archived', p_reason, v_actor);
END;
$function$;

-- ── 3/6 duplicate_board_item: board em `v_board_id` (alvo ou origem), validado ────────────────

CREATE OR REPLACE FUNCTION public.duplicate_board_item(p_item_id uuid, p_target_board_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_new_id uuid;
  v_board_id uuid;
  v_max_pos int;
  v_actor uuid;
  v_authorized boolean;
BEGIN
  SELECT coalesce(p_target_board_id, board_id) INTO v_board_id
  FROM board_items WHERE id = p_item_id;
  IF v_board_id IS NULL THEN RAISE EXCEPTION 'Source card not found'; END IF;

  SELECT m.id INTO v_actor FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Unauthorized: authentication required'; END IF;

  IF NOT public.rls_can_see_item(p_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access source card';
  END IF;
  IF NOT public.rls_can_see_board(v_board_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access target board';
  END IF;

  v_authorized := public._can_write_board(v_actor, v_board_id)
    OR EXISTS (SELECT 1 FROM board_members bm WHERE bm.board_id = v_board_id AND bm.member_id = v_actor AND bm.board_role IN ('admin', 'editor'));
  IF NOT v_authorized THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission or board editor role on the target board';
  END IF;

  SELECT coalesce(max(position), -1) + 1 INTO v_max_pos
  FROM board_items WHERE board_id = v_board_id AND status = 'backlog';

  INSERT INTO board_items (
    board_id, title, description, tags, labels, checklist, attachments, cycle, position, status
  )
  SELECT v_board_id, title || ' (cópia)', description, tags, labels, checklist, attachments, cycle, v_max_pos, 'backlog'
  FROM board_items WHERE id = p_item_id
  RETURNING id INTO v_new_id;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (v_board_id, v_new_id, 'created', 'Duplicado de ' || p_item_id::text, v_actor);

  RETURN v_new_id;
END;
$function$;

-- ── 4/6 move_board_item: board em `v_board_id`, validado ('Item not found') ───────────────────

CREATE OR REPLACE FUNCTION public.move_board_item(p_item_id uuid, p_new_status text, p_new_position integer DEFAULT 0, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_old_status text;
  v_board_id uuid;
  v_actor record;
  v_board record;
  v_board_legacy_tribe_id int;
  v_is_gp boolean;
  v_is_leader boolean;
  v_is_card_owner boolean;
  v_is_comms_for_domain boolean;
  v_is_initiative_leader boolean;
BEGIN
  SELECT status, board_id INTO v_old_status, v_board_id FROM board_items WHERE id = p_item_id;
  IF v_old_status IS NULL THEN RAISE EXCEPTION 'Item not found'; END IF;
  SELECT * INTO v_actor FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_board FROM project_boards WHERE id = v_board_id;

  SELECT legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives WHERE id = v_board.initiative_id;

  v_is_gp := coalesce(v_actor.is_superadmin, false) OR v_actor.operational_role IN ('manager','deputy_manager') OR coalesce('co_gp' = ANY(v_actor.designations), false);
  v_is_leader := v_actor.operational_role = 'tribe_leader' AND v_actor.tribe_id = v_board_legacy_tribe_id;

  v_is_card_owner := EXISTS (SELECT 1 FROM board_items WHERE id = p_item_id AND (created_by = v_actor.id OR assignee_id = v_actor.id))
    OR EXISTS (SELECT 1 FROM board_item_assignments WHERE item_id = p_item_id AND member_id = v_actor.id);

  v_is_comms_for_domain := coalesce(v_board.domain_key, '') = 'communication' AND (
    v_actor.operational_role = 'communicator'
    OR coalesce('comms_team' = ANY(v_actor.designations), false)
    OR coalesce('comms_leader' = ANY(v_actor.designations), false)
    OR coalesce('comms_member' = ANY(v_actor.designations), false)
  );

  v_is_initiative_leader := v_board.initiative_id IS NOT NULL
    AND v_actor.person_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = v_actor.person_id
        AND e.initiative_id = v_board.initiative_id
        AND e.status = 'active'
        AND e.role IN ('leader', 'coordinator', 'manager', 'co_gp')
    );

  IF p_new_status = 'done' AND NOT v_is_gp AND NOT v_is_leader AND NOT v_is_card_owner AND NOT v_is_comms_for_domain AND NOT v_is_initiative_leader THEN
    RAISE EXCEPTION 'Only Leader, GP, card owner, or comms team (in communication board) can mark as completed';
  END IF;

  IF NOT public._can_write_board(v_actor.id, v_board_id) AND NOT v_is_card_owner AND NOT v_is_comms_for_domain AND NOT v_is_initiative_leader THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission, card ownership, or comms team in communication board';
  END IF;

  UPDATE board_items SET position = position + 1
  WHERE board_id = v_board_id AND status = p_new_status AND position >= p_new_position AND id != p_item_id;

  UPDATE board_items SET status = p_new_status, position = p_new_position,
    actual_completion_date = CASE WHEN p_new_status = 'done' THEN CURRENT_DATE ELSE actual_completion_date END,
    updated_at = now()
  WHERE id = p_item_id;

  IF v_old_status != p_new_status THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, previous_status, new_status, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'status_change', v_old_status, p_new_status, p_reason, v_actor.id);
    INSERT INTO notifications (recipient_id, type, source_type, source_id, title, actor_id)
    SELECT bia.member_id,
      CASE WHEN p_new_status = 'review' THEN 'review_requested' ELSE 'card_status_changed' END,
      'board_item', p_item_id, (SELECT title FROM board_items WHERE id = p_item_id), v_actor.id
    FROM board_item_assignments bia WHERE bia.item_id = p_item_id AND bia.member_id != v_actor.id;
  END IF;
END;
$function$;

-- ── 5/6 update_card_forecast: board em `v_board_id`, validado ('Card not found') ──────────────

CREATE OR REPLACE FUNCTION public.update_card_forecast(p_board_item_id uuid, p_new_forecast date, p_justification text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_member_id uuid;
  v_old_forecast date;
  v_board_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_caller_id LIMIT 1;

  SELECT forecast_date, board_id INTO v_old_forecast, v_board_id
  FROM public.board_items WHERE id = p_board_item_id;
  IF v_board_id IS NULL THEN RAISE EXCEPTION 'Card not found'; END IF;

  IF NOT public.rls_can_see_item(p_board_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access this card';
  END IF;
  IF NOT (public._can_write_board(v_member_id, v_board_id)
          OR EXISTS (SELECT 1 FROM public.board_members bm WHERE bm.board_id = v_board_id AND bm.member_id = v_member_id AND bm.board_role IN ('admin', 'editor'))) THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission or board editor role';
  END IF;

  UPDATE public.board_items
  SET forecast_date = p_new_forecast
  WHERE id = p_board_item_id;

  INSERT INTO public.board_lifecycle_events (
    item_id, board_id, action, previous_status, new_status, reason, actor_member_id
  ) VALUES (
    p_board_item_id,
    v_board_id,
    'forecast_update',
    v_old_forecast::text,
    p_new_forecast::text,
    p_justification,
    v_member_id
  );
END;
$function$;

-- ── 6/6 convert_action_to_card: board em `p_board_id` ─────────────────────────────────────────
--
-- Aqui o portao vem ANTES do `board_not_found`. Para quem so tem escopo de iniciativa, um board
-- inexistente passa a devolver o erro de permissao em vez de `board_not_found`. Quem tem escopo
-- organization segue caindo no `board_not_found`, como antes.

CREATE OR REPLACE FUNCTION public.convert_action_to_card(p_action_item_id uuid, p_board_id uuid, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_status text DEFAULT 'todo'::text, p_due_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_action record;
  v_board record;
  v_new_card_id uuid;
  v_position int;
  v_final_title text;
  v_final_description text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- V4 gate: write_board (creating cards is board mutation)
  IF NOT public._can_write_board(v_caller_id, p_board_id) THEN
    RAISE EXCEPTION 'Requires write_board permission';
  END IF;

  SELECT * INTO v_action FROM public.meeting_action_items WHERE id = p_action_item_id;
  IF v_action.id IS NULL THEN
    RETURN jsonb_build_object('error', 'action_item_not_found');
  END IF;

  IF v_action.board_item_id IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'action_already_linked_to_card',
      'existing_board_item_id', v_action.board_item_id);
  END IF;

  SELECT pb.id, pb.organization_id, pb.is_active INTO v_board
  FROM public.project_boards pb WHERE pb.id = p_board_id;
  IF v_board.id IS NULL THEN
    RETURN jsonb_build_object('error', 'board_not_found');
  END IF;
  IF v_board.is_active = false THEN
    RETURN jsonb_build_object('error', 'board_inactive');
  END IF;

  -- Compute next position (max+1 in board)
  SELECT COALESCE(MAX(position), 0) + 1 INTO v_position
  FROM public.board_items WHERE board_id = p_board_id;

  -- Defaults from action item if not overridden
  v_final_title := COALESCE(NULLIF(trim(p_title), ''), substring(v_action.description from 1 for 80));
  v_final_description := COALESCE(p_description, v_action.description ||
    E'\n\n_Convertido de action item da reunião ' || v_action.event_id::text || '_');

  -- Create the new card
  INSERT INTO public.board_items (
    board_id, title, description, status, assignee_id, due_date, position, created_at, updated_at
  ) VALUES (
    p_board_id, v_final_title, v_final_description, p_status,
    v_action.assignee_id, COALESCE(p_due_date, v_action.due_date), v_position, now(), now()
  )
  RETURNING id INTO v_new_card_id;

  -- Lifecycle event
  INSERT INTO public.board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (p_board_id, v_new_card_id, 'created',
    'Created from action item ' || p_action_item_id::text, v_caller_id);

  -- Update action item to point to the new card
  UPDATE public.meeting_action_items
  SET board_item_id = v_new_card_id, updated_at = now()
  WHERE id = p_action_item_id;

  -- Link the card to the originating event via board_item_event_links
  INSERT INTO public.board_item_event_links (
    organization_id, board_item_id, event_id, link_type, author_id, note
  ) VALUES (
    v_board.organization_id, v_new_card_id, v_action.event_id, 'action_emerged',
    v_caller_id, 'Card created from action item: ' || v_action.description
  )
  ON CONFLICT (board_item_id, event_id, link_type) DO NOTHING;

  RETURN jsonb_build_object(
    'success', true,
    'action_item_id', p_action_item_id,
    'new_board_item_id', v_new_card_id,
    'board_id', p_board_id,
    'position', v_position,
    'created_at', now()
  );
END;
$function$;

DROP FUNCTION IF EXISTS public._write_board_scope_ok(uuid, uuid);
