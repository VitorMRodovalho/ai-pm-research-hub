-- RPCs de escrita de card conferem a visibilidade da iniciativa antes de gravar (ADR-0105).
--
-- As leituras SECURITY DEFINER sobre card aplicam rls_can_see_* desde a #785. Estas 23 funções de escrita não
-- aplicavam: SECURITY DEFINER contorna a RLS, e a autoridade de escrita (write_board de escopo organização, papel no
-- quadro, posse do card) não diz se quem chama enxerga a iniciativa. Cada uma ganha o portão logo depois de resolver
-- quem chama e o card ou o quadro, antes da checagem de autoridade e da primeira escrita, com a forma de recusa que a
-- função já usa (RAISE ou jsonb de erro). RAISE desfaz a chamada inteira, então não fica escrita parcial.
--
-- Para card ou quadro de iniciativa não confidencial, ou sem iniciativa, e para quem enxerga a iniciativa (vínculo
-- autoritativo, superadmin ou manage_platform), o portão é verdadeiro e o comportamento não muda.
--
-- Cada CREATE OR REPLACE é a captura vigente da função, byte a byte, mais o portão. Nenhuma assinatura muda.
-- As 11 que ainda tinham EXECUTE para anon perdem esse grant, como na #1778; todas já recusavam anon por dentro.

-- update_board_item: captura de 20261009144222_card_update_segue_fluxo_da_curadoria.sql
CREATE OR REPLACE FUNCTION public.update_board_item(p_item_id uuid, p_fields jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_board_id uuid;
  v_old record;
  v_caller record;
  v_board record;
  v_board_legacy_tribe_id int;
  v_is_gp boolean;
  v_is_leader boolean;
  v_is_card_owner boolean;
  v_is_board_admin boolean;
  v_is_board_editor boolean;
  v_is_comms_for_domain boolean;
  v_is_initiative_leader boolean;
  v_new_assignee uuid;
  v_curation_repair boolean;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_old FROM board_items WHERE id = p_item_id;
  IF v_old.id IS NULL THEN RAISE EXCEPTION 'Item not found: %', p_item_id; END IF;

  -- ADR-0105: card de iniciativa confidencial, só para quem a enxerga.
  IF NOT public.rls_can_see_item(p_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access this card';
  END IF;

  v_board_id := v_old.board_id;
  SELECT * INTO v_board FROM project_boards WHERE id = v_board_id;

  SELECT legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives WHERE id = v_board.initiative_id;

  v_is_gp := coalesce(v_caller.is_superadmin, false)
    OR v_caller.operational_role IN ('manager', 'deputy_manager')
    OR coalesce('co_gp' = ANY(v_caller.designations), false)
    OR public.can_by_member(v_caller.id, 'manage_platform');

  v_is_leader := v_caller.operational_role = 'tribe_leader'
    AND v_caller.tribe_id = v_board_legacy_tribe_id;

  v_is_card_owner := v_old.assignee_id = v_caller.id;

  v_is_board_admin := EXISTS (
    SELECT 1 FROM board_members bm
    WHERE bm.board_id = v_board.id AND bm.member_id = v_caller.id
    AND bm.board_role = 'admin'
  );
  v_is_board_editor := EXISTS (
    SELECT 1 FROM board_members bm
    WHERE bm.board_id = v_board.id AND bm.member_id = v_caller.id
    AND bm.board_role IN ('admin', 'editor')
  );

  v_is_comms_for_domain := coalesce(v_board.domain_key, '') = 'communication' AND (
    v_caller.operational_role = 'communicator'
    OR coalesce('comms_team' = ANY(v_caller.designations), false)
    OR coalesce('comms_leader' = ANY(v_caller.designations), false)
    OR coalesce('comms_member' = ANY(v_caller.designations), false)
  );

  v_is_initiative_leader := v_board.initiative_id IS NOT NULL
    AND v_caller.person_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = v_caller.person_id
        AND e.initiative_id = v_board.initiative_id
        AND e.status = 'active'
        AND e.role IN ('leader', 'coordinator', 'manager', 'co_gp')
    );

  IF NOT public._can_write_board_item(v_caller.id, p_item_id)
     AND NOT v_is_board_admin AND NOT v_is_card_owner AND NOT v_is_board_editor
     AND NOT v_is_comms_for_domain
     AND NOT v_is_initiative_leader THEN
    IF NOT (
      coalesce(v_board.domain_key, '') = 'publications_submissions' AND (
        v_caller.operational_role IN ('tribe_leader', 'communicator')
        OR public.can_by_member(v_caller.id, 'curate_content')
        OR coalesce('co_gp' = ANY(v_caller.designations), false)
        OR coalesce('comms_leader' = ANY(v_caller.designations), false)
        OR coalesce('comms_member' = ANY(v_caller.designations), false)
      )
    ) THEN
      RAISE EXCEPTION 'Insufficient permissions to edit this card';
    END IF;
  END IF;

  -- Estado e prazo da curadoria seguem o fluxo da curadoria. Aqui, so reparo administrativo.
  v_curation_repair := (p_fields->>'curation_status' IS NOT NULL
        AND p_fields->>'curation_status' IS DISTINCT FROM v_old.curation_status)
     OR (p_fields->>'curation_due_at' IS NOT NULL
        AND (p_fields->>'curation_due_at')::timestamptz IS DISTINCT FROM v_old.curation_due_at);
  IF v_curation_repair AND NOT public.can_by_member(v_caller.id, 'manage_platform') THEN
    RAISE EXCEPTION 'Insufficient permissions to edit this field';
  END IF;

  IF p_fields ? 'baseline_date' THEN
    IF v_old.baseline_locked_at IS NOT NULL AND NOT v_is_gp THEN
      RAISE EXCEPTION 'Baseline is locked. Only GP can change it.';
    END IF;
    IF v_old.baseline_locked_at IS NOT NULL AND v_is_gp AND NOT (p_fields ? 'reason') THEN
      RAISE EXCEPTION 'Reason required to change locked baseline';
    END IF;
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin AND NOT v_is_initiative_leader THEN
      RAISE EXCEPTION 'Only Leader or GP can change baseline';
    END IF;
  END IF;

  IF p_fields ? 'forecast_date' THEN
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin AND NOT v_is_card_owner AND NOT v_is_board_editor AND NOT v_is_comms_for_domain AND NOT v_is_initiative_leader THEN
      RAISE EXCEPTION 'Only Leader, GP, card owner, or board editor can change forecast';
    END IF;
  END IF;

  IF p_fields ? 'assignee_id' THEN
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin AND NOT v_is_comms_for_domain AND NOT v_is_initiative_leader THEN
      RAISE EXCEPTION 'Only Leader, GP, Board Admin, or comms team (in communication board) can change assignee';
    END IF;
  END IF;

  IF p_fields ? 'is_portfolio_item' THEN
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin AND NOT v_is_initiative_leader THEN
      RAISE EXCEPTION 'Only Leader or GP can change portfolio flag';
    END IF;
  END IF;

  IF v_old.baseline_date IS NOT NULL
    AND v_old.baseline_locked_at IS NULL
    AND v_old.baseline_date <= CURRENT_DATE - 7
  THEN
    UPDATE board_items SET baseline_locked_at = now() WHERE id = p_item_id;
    v_old.baseline_locked_at := now();
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'baseline_locked', 'Auto-lock após 7 dias de grace period', v_caller.id);
  END IF;

  UPDATE board_items SET
    title = coalesce(p_fields->>'title', title),
    description = CASE WHEN p_fields ? 'description' THEN p_fields->>'description' ELSE description END,
    assignee_id = CASE WHEN p_fields ? 'assignee_id' AND p_fields->>'assignee_id' IS NOT NULL
                       THEN (p_fields->>'assignee_id')::uuid
                       WHEN p_fields ? 'assignee_id' AND p_fields->>'assignee_id' IS NULL THEN NULL
                       ELSE assignee_id END,
    reviewer_id = CASE WHEN p_fields ? 'reviewer_id' AND p_fields->>'reviewer_id' IS NOT NULL
                       THEN (p_fields->>'reviewer_id')::uuid
                       WHEN p_fields ? 'reviewer_id' AND p_fields->>'reviewer_id' IS NULL THEN NULL
                       ELSE reviewer_id END,
    tags = CASE WHEN p_fields ? 'tags' THEN ARRAY(SELECT jsonb_array_elements_text(p_fields->'tags')) ELSE tags END,
    labels = CASE WHEN p_fields ? 'labels' THEN p_fields->'labels' ELSE labels END,
    due_date = CASE WHEN p_fields ? 'due_date' AND p_fields->>'due_date' IS NOT NULL THEN (p_fields->>'due_date')::date
                    WHEN p_fields ? 'due_date' AND p_fields->>'due_date' IS NULL THEN NULL ELSE due_date END,
    baseline_date = CASE WHEN p_fields ? 'baseline_date' AND p_fields->>'baseline_date' IS NOT NULL THEN (p_fields->>'baseline_date')::date
                         WHEN p_fields ? 'baseline_date' AND p_fields->>'baseline_date' IS NULL THEN NULL ELSE baseline_date END,
    forecast_date = CASE WHEN p_fields ? 'forecast_date' AND p_fields->>'forecast_date' IS NOT NULL THEN (p_fields->>'forecast_date')::date
                         WHEN p_fields ? 'forecast_date' AND p_fields->>'forecast_date' IS NULL THEN NULL ELSE forecast_date END,
    is_portfolio_item = CASE WHEN p_fields ? 'is_portfolio_item' THEN (p_fields->>'is_portfolio_item')::boolean ELSE is_portfolio_item END,
    baseline_locked_at = CASE WHEN p_fields ? 'baseline_locked_at' AND p_fields->>'baseline_locked_at' IS NOT NULL
                               THEN (p_fields->>'baseline_locked_at')::timestamptz ELSE baseline_locked_at END,
    checklist = CASE WHEN p_fields ? 'checklist' THEN p_fields->'checklist' ELSE checklist END,
    attachments = CASE WHEN p_fields ? 'attachments' THEN p_fields->'attachments' ELSE attachments END,
    curation_status = CASE WHEN v_curation_repair
                           THEN coalesce(p_fields->>'curation_status', curation_status) ELSE curation_status END,
    curation_due_at = CASE WHEN v_curation_repair AND p_fields->>'curation_due_at' IS NOT NULL
                           THEN (p_fields->>'curation_due_at')::timestamptz ELSE curation_due_at END,
    updated_at = now()
  WHERE id = p_item_id;

  IF p_fields ? 'baseline_date' THEN
    IF v_old.baseline_date IS NULL AND p_fields->>'baseline_date' IS NOT NULL THEN
      INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
      VALUES (v_board_id, p_item_id, 'baseline_set', 'Baseline definida: ' || (p_fields->>'baseline_date'), v_caller.id);
    ELSIF v_old.baseline_date IS NOT NULL AND p_fields->>'baseline_date' IS NOT NULL
      AND v_old.baseline_date::text != p_fields->>'baseline_date' THEN
      INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
      VALUES (v_board_id, p_item_id, 'baseline_changed',
        v_old.baseline_date::text || ' → ' || (p_fields->>'baseline_date')
        || CASE WHEN p_fields ? 'reason' THEN ' | Razão: ' || (p_fields->>'reason') ELSE '' END, v_caller.id);
    END IF;
  END IF;

  IF p_fields ? 'forecast_date' AND p_fields->>'forecast_date' IS DISTINCT FROM v_old.forecast_date::text THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'forecast_changed',
      coalesce(v_old.forecast_date::text, 'null') || ' → ' || coalesce(p_fields->>'forecast_date', 'null'), v_caller.id);
  END IF;

  IF p_fields ? 'title' AND p_fields->>'title' IS DISTINCT FROM v_old.title THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'title_changed', 'Título alterado', v_caller.id);
  END IF;

  IF v_curation_repair THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'status_change',
      'Reparo administrativo da curadoria: ' || coalesce(v_old.curation_status, 'null') || ' → '
        || coalesce(p_fields->>'curation_status', v_old.curation_status, 'null')
        || CASE WHEN p_fields->>'curation_due_at' IS NOT NULL
                THEN ' | prazo: ' || coalesce(v_old.curation_due_at::text, 'null') || ' → ' || (p_fields->>'curation_due_at')
                ELSE '' END
        || CASE WHEN p_fields ? 'reason' THEN ' | Razão: ' || (p_fields->>'reason') ELSE '' END,
      v_caller.id);
  END IF;

  v_new_assignee := CASE WHEN p_fields ? 'assignee_id' AND p_fields->>'assignee_id' IS NOT NULL
                         THEN (p_fields->>'assignee_id')::uuid
                         WHEN p_fields ? 'assignee_id' THEN NULL ELSE v_old.assignee_id END;
  IF v_new_assignee IS DISTINCT FROM v_old.assignee_id THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'assigned',
      'Atribuído a ' || coalesce((SELECT name FROM members WHERE id = v_new_assignee), 'ninguém'), v_caller.id);
  END IF;

  IF p_fields ? 'is_portfolio_item'
    AND (p_fields->>'is_portfolio_item')::boolean IS DISTINCT FROM v_old.is_portfolio_item THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'portfolio_flag_changed',
      CASE WHEN (p_fields->>'is_portfolio_item')::boolean THEN 'Marcado como entregável' ELSE 'Removido de entregáveis' END, v_caller.id);
  END IF;
END;
$function$;

-- create_board_item: captura de 20261006161737_2565_2a_pr2_ciclo_corrente_e_portfolio.sql
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
  -- ADR-0105: quadro de iniciativa confidencial, só para quem o enxerga.
  IF NOT public.rls_can_see_board(p_board_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access this board';
  END IF;

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

  -- #2565 2A: o ciclo sai do gatilho trg_board_items_stamp_cycle (ciclo corrente), nunca de literal.
  INSERT INTO board_items (board_id, title, description, assignee_id, tags, due_date, position, status, created_by)
  VALUES (p_board_id, p_title, p_description, COALESCE(p_assignee_id, v_caller.id), p_tags, p_due_date, v_max_pos, p_status, v_caller.id)
  RETURNING id INTO v_id;

  INSERT INTO board_item_assignments (item_id, member_id, role, assigned_by)
  VALUES (v_id, v_caller.id, 'author', v_caller.id)
  ON CONFLICT DO NOTHING;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, new_status, actor_member_id)
  VALUES (p_board_id, v_id, 'created', p_status, v_caller.id);

  RETURN v_id;
END;
$function$;

-- move_board_item: captura de 20260823222639_c_onda_a_write_board_helper_na_convencao_can.sql
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
  -- ADR-0105: card de iniciativa confidencial, só para quem a enxerga.
  IF NOT public.rls_can_see_item(p_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access this card';
  END IF;
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

-- create_card_comment: captura de 20260824094756_c_write_board_lote2_repassa_recurso_via_card.sql
CREATE OR REPLACE FUNCTION public.create_card_comment(p_board_item_id uuid, p_body text, p_parent_comment_id uuid DEFAULT NULL::uuid, p_mentioned_member_ids uuid[] DEFAULT '{}'::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller record;
  v_card record;
  v_board record;
  v_authorized boolean;
  v_new_id uuid;
  v_parent_author_id uuid;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF coalesce(trim(p_body), '') = '' THEN
    RETURN jsonb_build_object('error', 'Comment body required');
  END IF;

  SELECT * INTO v_card FROM public.board_items WHERE id = p_board_item_id;
  IF v_card.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Card not found');
  END IF;

  -- ADR-0105: card de iniciativa confidencial, só para quem a enxerga.
  IF NOT public.rls_can_see_item(p_board_item_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: cannot access this card');
  END IF;

  SELECT * INTO v_board FROM public.project_boards WHERE id = v_card.board_id;

  v_authorized := public.rls_is_member()
    OR public._can_write_board_item(v_caller.id, p_board_item_id)
    OR (coalesce(v_board.domain_key, '') = 'communication' AND (
      v_caller.operational_role = 'communicator'
      OR coalesce('comms_team' = ANY(v_caller.designations), false)
      OR coalesce('comms_leader' = ANY(v_caller.designations), false)
      OR coalesce('comms_member' = ANY(v_caller.designations), false)
    ));

  IF NOT v_authorized THEN
    RETURN jsonb_build_object('error', 'Unauthorized: must be a member or have write_board to comment');
  END IF;

  IF p_parent_comment_id IS NOT NULL THEN
    SELECT author_id INTO v_parent_author_id
    FROM public.board_item_comments
    WHERE id = p_parent_comment_id AND board_item_id = p_board_item_id AND deleted_at IS NULL;
    IF v_parent_author_id IS NULL THEN
      RETURN jsonb_build_object('error', 'Parent comment not found or deleted');
    END IF;
  END IF;

  INSERT INTO public.board_item_comments (
    board_item_id, author_id, body, parent_comment_id, mentioned_member_ids
  )
  VALUES (
    p_board_item_id, v_caller.id, p_body, p_parent_comment_id, COALESCE(p_mentioned_member_ids, '{}'::uuid[])
  )
  RETURNING id INTO v_new_id;

  INSERT INTO public.board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (v_card.board_id, v_card.id, 'comment_added',
    substring(p_body from 1 for 100) || CASE WHEN length(p_body) > 100 THEN '...' ELSE '' END,
    v_caller.id);

  -- Notify @mentions (transactional_immediate)
  IF p_mentioned_member_ids IS NOT NULL AND array_length(p_mentioned_member_ids, 1) > 0 THEN
    INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id, link, actor_id, delivery_mode)
    SELECT
      mid,
      'card_comment_mention',
      v_caller.name || ' mencionou você em ' || coalesce(v_card.title, 'um card'),
      p_body,
      'board_item',
      v_card.id,
      '/boards/' || v_board.id || '/items/' || v_card.id,
      v_caller.id,
      'transactional_immediate'
    FROM unnest(p_mentioned_member_ids) AS mid
    WHERE mid != v_caller.id;
  END IF;

  -- NEW: Notify parent comment author on reply (transactional_immediate; skip if same as caller or already mentioned)
  IF v_parent_author_id IS NOT NULL
     AND v_parent_author_id != v_caller.id
     AND NOT (v_parent_author_id = ANY(coalesce(p_mentioned_member_ids, '{}'::uuid[]))) THEN
    INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id, link, actor_id, delivery_mode)
    VALUES (
      v_parent_author_id,
      'card_comment_reply',
      v_caller.name || ' respondeu seu comentário em ' || coalesce(v_card.title, 'um card'),
      p_body,
      'board_item',
      v_card.id,
      '/boards/' || v_board.id || '/items/' || v_card.id,
      v_caller.id,
      'transactional_immediate'
    );
  END IF;

  -- Notify card assignee (digest_weekly; skip if author or already in mention/parent paths)
  IF v_card.assignee_id IS NOT NULL
     AND v_card.assignee_id != v_caller.id
     AND NOT (v_card.assignee_id = ANY(coalesce(p_mentioned_member_ids, '{}'::uuid[])))
     AND v_card.assignee_id IS DISTINCT FROM v_parent_author_id THEN
    INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id, link, actor_id, delivery_mode)
    VALUES (
      v_card.assignee_id,
      'card_comment_new',
      v_caller.name || ' comentou em ' || coalesce(v_card.title, 'um card'),
      p_body,
      'board_item',
      v_card.id,
      '/boards/' || v_board.id || '/items/' || v_card.id,
      v_caller.id,
      'digest_weekly'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'comment_id', v_new_id,
    'author_id', v_caller.id,
    'mentioned_count', array_length(coalesce(p_mentioned_member_ids, '{}'::uuid[]), 1),
    'replied_to_author', v_parent_author_id IS NOT NULL AND v_parent_author_id != v_caller.id
  );
END;
$function$;

-- update_card_comment: captura de 20260686000000_p178_phase_b_drift_capture_1_touch_q_z_underscore_63fns.sql
CREATE OR REPLACE FUNCTION public.update_card_comment(p_comment_id uuid, p_new_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_comment record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT * INTO v_comment FROM public.board_item_comments WHERE id = p_comment_id;
  IF v_comment.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Comment not found');
  END IF;

  -- ADR-0105: card de iniciativa confidencial, só para quem a enxerga.
  IF NOT public.rls_can_see_item(v_comment.board_item_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: cannot access this card');
  END IF;

  -- Only author can edit own comment
  IF v_comment.author_id != v_caller_id THEN
    RETURN jsonb_build_object('error', 'Only author can edit own comment');
  END IF;

  IF v_comment.deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Cannot edit deleted comment');
  END IF;

  IF coalesce(trim(p_new_body), '') = '' THEN
    RETURN jsonb_build_object('error', 'Body required');
  END IF;

  UPDATE public.board_item_comments
  SET body = p_new_body, edited_at = now(), updated_at = now()
  WHERE id = p_comment_id;

  RETURN jsonb_build_object('success', true, 'comment_id', p_comment_id);
END;
$function$;

-- delete_card_comment: captura de 20260824094756_c_write_board_lote2_repassa_recurso_via_card.sql
CREATE OR REPLACE FUNCTION public.delete_card_comment(p_comment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_comment record;
  v_authorized boolean;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT * INTO v_comment FROM public.board_item_comments WHERE id = p_comment_id;
  IF v_comment.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Comment not found');
  END IF;

  -- ADR-0105: card de iniciativa confidencial, só para quem a enxerga.
  IF NOT public.rls_can_see_item(v_comment.board_item_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: cannot access this card');
  END IF;

  -- Author OR write_board OR admin
  v_authorized := v_comment.author_id = v_caller_id
    OR public._can_write_board_item(v_caller_id, v_comment.board_item_id)
    OR public.can_by_member(v_caller_id, 'manage_member');

  IF NOT v_authorized THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  UPDATE public.board_item_comments
  SET deleted_at = now(), updated_at = now()
  WHERE id = p_comment_id;

  RETURN jsonb_build_object('success', true, 'comment_id', p_comment_id);
END;
$function$;

-- assign_member_to_item: captura de 20260820014622_1887_assign_e_unassign_de_membro_em_card_decidem_olhando_o_recurso.sql
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
  -- ADR-0105: card de iniciativa confidencial, só para quem a enxerga.
  IF NOT public.rls_can_see_item(p_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access this card';
  END IF;
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

-- unassign_member_from_item: captura de 20260820014622_1887_assign_e_unassign_de_membro_em_card_decidem_olhando_o_recurso.sql
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
  -- ADR-0105: card de iniciativa confidencial, só para quem a enxerga.
  IF NOT public.rls_can_see_item(p_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access this card';
  END IF;
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

-- complete_checklist_item: captura de 20260824094756_c_write_board_lote2_repassa_recurso_via_card.sql
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
  -- ADR-0105: card de iniciativa confidencial, só para quem a enxerga.
  IF NOT public.rls_can_see_item(v_item.board_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access this card';
  END IF;

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

  IF NOT public._can_write_board(v_caller.id, v_card.board_id) AND NOT v_is_card_owner AND NOT v_is_activity_owner THEN
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

-- convert_action_to_card: captura de 20260823222639_c_onda_a_write_board_helper_na_convencao_can.sql
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

  -- ADR-0105: quadro de iniciativa confidencial, só para quem o enxerga.
  -- O texto do card novo vem do item de ação: o evento dele também tem de ser visível.
  IF NOT public.rls_can_see_board(p_board_id)
     OR NOT public.rls_can_see_initiative((SELECT e.initiative_id FROM public.meeting_action_items a
                                            JOIN public.events e ON e.id = a.event_id
                                           WHERE a.id = p_action_item_id)) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access this board';
  END IF;

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

-- update_card_during_meeting: captura de 20260824094756_c_write_board_lote2_repassa_recurso_via_card.sql
CREATE OR REPLACE FUNCTION public.update_card_during_meeting(p_card_id uuid, p_event_id uuid, p_new_status text DEFAULT NULL::text, p_fields jsonb DEFAULT NULL::jsonb, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_card record;
  v_event record;
  v_old_status text;
  v_status_changed boolean := false;
  v_fields_applied boolean := false;
  v_link_type text;
  v_link_note text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- ADR-0105: card de iniciativa confidencial, só para quem a enxerga.
  IF NOT public.rls_can_see_item(p_card_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access this card';
  END IF;

  IF NOT public._can_write_board_item(v_caller_id, p_card_id) THEN
    RAISE EXCEPTION 'Requires write_board permission';
  END IF;

  SELECT id, status, organization_id, title INTO v_card
  FROM public.board_items WHERE id = p_card_id;
  IF v_card.id IS NULL THEN
    RETURN jsonb_build_object('error', 'card_not_found');
  END IF;
  v_old_status := v_card.status;

  SELECT id, title, initiative_id INTO v_event
  FROM public.events WHERE id = p_event_id;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  IF p_new_status IS NOT NULL AND p_new_status <> v_old_status THEN
    PERFORM public.move_board_item(
      p_card_id,
      p_new_status,
      NULL,
      COALESCE(p_note, 'Updated during meeting ' || COALESCE(v_event.title, p_event_id::text))
    );
    v_status_changed := true;
  END IF;

  IF p_fields IS NOT NULL AND p_fields <> '{}'::jsonb THEN
    PERFORM public.update_board_item(p_card_id, p_fields);
    v_fields_applied := true;
  END IF;

  v_link_type := CASE WHEN v_status_changed THEN 'status_changed' ELSE 'discussed' END;

  v_link_note := COALESCE(
    p_note,
    CASE
      WHEN v_status_changed AND v_fields_applied
        THEN 'Status: ' || v_old_status || ' → ' || p_new_status || ' (and fields updated)'
      WHEN v_status_changed
        THEN 'Status: ' || v_old_status || ' → ' || p_new_status
      WHEN v_fields_applied
        THEN 'Card fields updated during meeting'
      ELSE 'Discussed during meeting'
    END
  );

  INSERT INTO public.board_item_event_links (
    organization_id, board_item_id, event_id, link_type, author_id, note
  ) VALUES (
    v_card.organization_id, p_card_id, p_event_id, v_link_type, v_caller_id, v_link_note
  )
  ON CONFLICT (board_item_id, event_id, link_type) DO UPDATE
    SET note = EXCLUDED.note;

  RETURN jsonb_build_object(
    'success', true,
    'card_id', p_card_id,
    'event_id', p_event_id,
    'old_status', v_old_status,
    'new_status', CASE WHEN v_status_changed THEN p_new_status ELSE v_old_status END,
    'status_changed', v_status_changed,
    'fields_applied', v_fields_applied,
    'link_type', v_link_type,
    'updated_at', now()
  );
END;
$function$;

-- upsert_board_item: captura de 20260519183234_p200_v4_curate_content_batch_a_board_fns.sql
CREATE OR REPLACE FUNCTION public.upsert_board_item(p_item_id uuid DEFAULT NULL::uuid, p_board_id uuid DEFAULT NULL::uuid, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_status text DEFAULT 'backlog'::text, p_assignee_id uuid DEFAULT NULL::uuid, p_due_date date DEFAULT NULL::date, p_tags text[] DEFAULT NULL::text[], p_labels jsonb DEFAULT '[]'::jsonb, p_checklist jsonb DEFAULT '[]'::jsonb, p_attachments jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_member public.members%rowtype; v_board public.project_boards%rowtype;
  v_board_tribe_id int; v_item_id uuid; v_board_id uuid;
  v_allowed boolean := false; v_designations text[] := '{}';
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_member from public.members where auth_id = auth.uid();
  if v_member.id is null then raise exception 'Member not found'; end if;
  v_designations := coalesce(v_member.designations, '{}'::text[]);
  if p_item_id is not null then
    select pb.* into v_board
    from public.project_boards pb
    join public.board_items bi on bi.board_id = pb.id
    where bi.id = p_item_id limit 1;
    v_board_id := v_board.id;
  else
    select * into v_board from public.project_boards where id = p_board_id limit 1;
    v_board_id := p_board_id;
  end if;
  if v_board.id is null then raise exception 'Board not found'; end if;
  -- ADR-0105: quadro de iniciativa confidencial, só para quem o enxerga.
  if not public.rls_can_see_board(v_board_id) then raise exception 'Unauthorized: cannot access this board'; end if;
  SELECT legacy_tribe_id INTO v_board_tribe_id FROM public.initiatives WHERE id = v_board.initiative_id;
  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
  v_allowed := (
    coalesce(v_member.is_superadmin, false)
    or v_member.operational_role in ('manager', 'deputy_manager')
    or coalesce('co_gp' = any(v_designations), false)
    or (v_member.operational_role = 'tribe_leader' and v_member.tribe_id = v_board_tribe_id)
    or (coalesce(v_board.domain_key, '') = 'communication'
      and (v_member.operational_role = 'communicator'
        or coalesce('comms_team' = any(v_designations), false)
        or coalesce('comms_leader' = any(v_designations), false)
        or coalesce('comms_member' = any(v_designations), false)))
    or (coalesce(v_board.domain_key, '') = 'publications_submissions'
      and (v_member.operational_role in ('tribe_leader', 'communicator')
        or public.can_by_member(v_member.id, 'curate_content')
        or coalesce('co_gp' = any(v_designations), false)
        or coalesce('comms_leader' = any(v_designations), false)
        or coalesce('comms_member' = any(v_designations), false)))
  );
  if not v_allowed then raise exception 'Project management access required'; end if;
  if p_item_id is null then
    if coalesce(trim(p_title), '') = '' then raise exception 'Title is required'; end if;
    insert into public.board_items (board_id, title, description, status, assignee_id, due_date,
      tags, labels, checklist, attachments, position)
    values (v_board_id, trim(p_title),
      nullif(trim(coalesce(p_description, '')), ''),
      coalesce(nullif(trim(coalesce(p_status, '')), ''), 'backlog'),
      p_assignee_id, p_due_date, p_tags,
      coalesce(p_labels, '[]'::jsonb),
      coalesce(p_checklist, '[]'::jsonb),
      coalesce(p_attachments, '[]'::jsonb),
      coalesce((select max(position) + 1 from public.board_items where board_id = v_board_id), 1))
    returning id into v_item_id;
    return v_item_id;
  end if;
  update public.board_items
  set title = coalesce(nullif(trim(coalesce(p_title, '')), ''), title),
    description = case when p_description is null then description else nullif(trim(p_description), '') end,
    status = coalesce(nullif(trim(coalesce(p_status, '')), ''), status),
    assignee_id = p_assignee_id, due_date = p_due_date, tags = p_tags,
    labels = coalesce(p_labels, labels), checklist = coalesce(p_checklist, checklist),
    attachments = coalesce(p_attachments, attachments), updated_at = now()
  where id = p_item_id returning id into v_item_id;
  if v_item_id is null then raise exception 'Board item not found'; end if;
  return v_item_id;
end;
$function$;

-- publish_board_item_from_curation: captura de 20260427233000_adr_0041_governance_review_action_and_9_fns.sql
CREATE OR REPLACE FUNCTION public.publish_board_item_from_curation(
  p_item_id uuid
) RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller     public.members%rowtype;
  v_item       public.board_items%rowtype;
  v_pub_board  uuid;
  v_new_id     uuid;
  v_pos        int;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- ADR-0105: card de iniciativa confidencial, só para quem a enxerga.
  IF NOT public.rls_can_see_item(p_item_id) THEN
    RAISE EXCEPTION 'Board item not found';
  END IF;

  -- ADR-0041: strict V4 catalog (defense-in-depth; called internally by submit_curation_review)
  IF NOT public.can_by_member(v_caller.id, 'participate_in_governance_review') THEN
    RAISE EXCEPTION 'Requires participate_in_governance_review';
  END IF;

  SELECT bi.* INTO v_item
  FROM public.board_items bi
  JOIN public.project_boards pb ON pb.id = bi.board_id
  WHERE bi.id = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Board item not found';
  END IF;
  IF v_item.curation_status <> 'curation_pending' THEN
    RAISE EXCEPTION 'Only curation_pending items can be published';
  END IF;

  SELECT id INTO v_pub_board
  FROM public.project_boards
  WHERE coalesce(domain_key, '') = 'publications_submissions'
    AND is_active = true
  ORDER BY updated_at DESC NULLS LAST
  LIMIT 1;

  IF v_pub_board IS NULL THEN
    RAISE EXCEPTION 'Publications board not found';
  END IF;

  SELECT coalesce(max(position), 0) + 1 INTO v_pos
  FROM public.board_items WHERE board_id = v_pub_board;

  INSERT INTO public.board_items (
    board_id, title, description, status, curation_status,
    assignee_id, due_date, position, created_at, updated_at,
    cycle, tags, labels, checklist, attachments, source_board, source_card_id
  ) VALUES (
    v_pub_board, v_item.title, v_item.description, 'done', 'published',
    v_item.assignee_id, v_item.due_date, v_pos, now(), now(),
    v_item.cycle, v_item.tags, v_item.labels, v_item.checklist, v_item.attachments,
    'tribe_curation', v_item.id::text
  )
  RETURNING id INTO v_new_id;

  UPDATE public.board_items
  SET curation_status = 'published', updated_at = now()
  WHERE id = p_item_id;

  RETURN v_new_id;
END;
$function$;

-- admin_archive_board_item: captura de 20260519183234_p200_v4_curate_content_batch_a_board_fns.sql
CREATE OR REPLACE FUNCTION public.admin_archive_board_item(p_item_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_caller record;
  v_item record;
  v_prev_status text;
  v_designations text[] := '{}';
begin
  select * into v_caller from public.get_my_member_record();
  select bi.*, i.legacy_tribe_id as board_tribe_id, pb.domain_key
    into v_item
  from public.board_items bi
  join public.project_boards pb on pb.id = bi.board_id
  left join public.initiatives i on i.id = pb.initiative_id
  where bi.id = p_item_id;

  if v_item is null then
    raise exception 'Board item not found: %', p_item_id;
  end if;

  -- ADR-0105: card de iniciativa confidencial, só para quem a enxerga.
  if not public.rls_can_see_item(p_item_id) then
    raise exception 'Unauthorized: cannot access this card';
  end if;

  v_designations := coalesce(v_caller.designations, '{}'::text[]);

  if v_caller is null
    or not (
      v_caller.is_superadmin is true
      or public.can_by_member(v_caller.id, 'manage_member')
      or coalesce('co_gp' = any(v_designations), false)
      or (v_caller.operational_role = 'tribe_leader' and v_caller.tribe_id = v_item.board_tribe_id)
      or (
        coalesce(v_item.domain_key, '') = 'communication'
        and (
          v_caller.operational_role = 'communicator'
          or coalesce('comms_team' = any(v_designations), false)
          or coalesce('comms_leader' = any(v_designations), false)
          or coalesce('comms_member' = any(v_designations), false)
        )
      )
      or (
        coalesce(v_item.domain_key, '') = 'publications_submissions'
        and (
          v_caller.operational_role in ('tribe_leader', 'communicator')
          or public.can_by_member(v_caller.id, 'curate_content')
          or coalesce('co_gp' = any(v_designations), false)
          or coalesce('comms_leader' = any(v_designations), false)
          or coalesce('comms_member' = any(v_designations), false)
        )
      )
    ) then
    raise exception 'Insufficient permissions';
  end if;

  v_prev_status := v_item.status;

  update public.board_items
  set status = 'archived',
      updated_at = now()
  where id = p_item_id;

  insert into public.board_lifecycle_events (
    board_id, item_id, action, previous_status, new_status, reason, actor_member_id
  ) values (
    v_item.board_id, p_item_id, 'item_archived', v_prev_status, 'archived',
    nullif(trim(coalesce(p_reason, '')), ''), v_caller.id
  );

  return jsonb_build_object(
    'success', true,
    'item_id', p_item_id,
    'previous_status', v_prev_status,
    'new_status', 'archived'
  );
end;
$function$;

-- admin_restore_board_item: captura de 20260428100000_adr0015_phase3d_pb_tribe_id_cleanup.sql
CREATE OR REPLACE FUNCTION public.admin_restore_board_item(p_item_id uuid, p_restore_status text DEFAULT 'backlog'::text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_caller record;
  v_item record;
  v_prev_status text;
begin
  if p_restore_status not in ('backlog', 'todo', 'in_progress', 'review', 'done') then
    raise exception 'Invalid restore status: %', p_restore_status;
  end if;

  select * into v_caller from public.get_my_member_record();
  select bi.*, i.legacy_tribe_id as board_tribe_id
    into v_item
  from public.board_items bi
  join public.project_boards pb on pb.id = bi.board_id
  left join public.initiatives i on i.id = pb.initiative_id
  where bi.id = p_item_id;

  if v_item is null then
    raise exception 'Board item not found: %', p_item_id;
  end if;

  -- ADR-0105: card de iniciativa confidencial, só para quem a enxerga.
  if not public.rls_can_see_item(p_item_id) then
    raise exception 'Unauthorized: cannot access this card';
  end if;

  if v_caller is null
    or not (
      v_caller.is_superadmin is true
      or public.can_by_member(v_caller.id, 'manage_member')
      or coalesce('co_gp' = any(v_caller.designations), false)
      or (v_caller.operational_role = 'tribe_leader' and v_caller.tribe_id = v_item.board_tribe_id)
    ) then
    raise exception 'Insufficient permissions';
  end if;

  v_prev_status := v_item.status;

  update public.board_items
  set status = p_restore_status,
      updated_at = now()
  where id = p_item_id;

  insert into public.board_lifecycle_events (
    board_id, item_id, action, previous_status, new_status, reason, actor_member_id
  ) values (
    v_item.board_id, p_item_id, 'item_restored', v_prev_status, p_restore_status,
    nullif(trim(coalesce(p_reason, '')), ''), v_caller.id
  );

  return jsonb_build_object(
    'success', true,
    'item_id', p_item_id,
    'previous_status', v_prev_status,
    'new_status', p_restore_status
  );
end;
$function$;

-- admin_archive_project_board: captura de 20260682000000_p176_phase_b_drift_capture_2_touch_28fns.sql
CREATE OR REPLACE FUNCTION public.admin_archive_project_board(p_board_id uuid, p_reason text DEFAULT NULL::text, p_archive_items boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  v_caller_id uuid;
  v_board record;
  v_archived_items integer := 0;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Auth required';
  END IF;

  SELECT * INTO v_board FROM public.project_boards WHERE id = p_board_id;
  IF v_board IS NULL THEN
    RAISE EXCEPTION 'Board not found: %', p_board_id;
  END IF;

  -- ADR-0105: quadro de iniciativa confidencial, só para quem o enxerga.
  IF NOT public.rls_can_see_board(p_board_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access this board';
  END IF;

  -- V4 gate: org-wide manage_board_admin OR initiative-scoped
  IF NOT public.can_by_member(v_caller_id, 'manage_board_admin', 'initiative', v_board.initiative_id) THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;

  UPDATE public.project_boards
  SET is_active = false, updated_at = now()
  WHERE id = p_board_id;

  IF p_archive_items THEN
    UPDATE public.board_items
    SET status = 'archived', updated_at = now()
    WHERE board_id = p_board_id AND status <> 'archived';
    GET DIAGNOSTICS v_archived_items = ROW_COUNT;
  END IF;

  INSERT INTO public.board_lifecycle_events (board_id, action, reason, actor_member_id)
  VALUES (p_board_id, 'board_archived', NULLIF(TRIM(COALESCE(p_reason, '')), ''), v_caller_id);

  RETURN jsonb_build_object('success', true, 'board_id', p_board_id, 'archived_items', v_archived_items);
END;
$$;

-- admin_restore_project_board: captura de 20260682000000_p176_phase_b_drift_capture_2_touch_28fns.sql
CREATE OR REPLACE FUNCTION public.admin_restore_project_board(p_board_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  v_caller_id uuid;
  v_board record;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Auth required';
  END IF;

  SELECT * INTO v_board FROM public.project_boards WHERE id = p_board_id;
  IF v_board IS NULL THEN
    RAISE EXCEPTION 'Board not found: %', p_board_id;
  END IF;

  -- ADR-0105: quadro de iniciativa confidencial, só para quem o enxerga.
  IF NOT public.rls_can_see_board(p_board_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access this board';
  END IF;

  -- V4 gate: org-wide manage_board_admin OR initiative-scoped
  IF NOT public.can_by_member(v_caller_id, 'manage_board_admin', 'initiative', v_board.initiative_id) THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;

  UPDATE public.project_boards
  SET is_active = true, updated_at = now()
  WHERE id = p_board_id;

  INSERT INTO public.board_lifecycle_events (board_id, action, reason, actor_member_id)
  VALUES (p_board_id, 'board_restored', NULLIF(TRIM(COALESCE(p_reason, '')), ''), v_caller_id);

  RETURN jsonb_build_object('success', true, 'board_id', p_board_id);
END;
$$;

-- move_item_to_board: captura de 20260805000410_1289_harden_move_item_to_board.sql
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

  -- ADR-0105: card de iniciativa confidencial, só para quem a enxerga. A origem também, não só o destino.
  IF NOT public.rls_can_see_item(p_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: source card not visible' USING ERRCODE = 'insufficient_privilege';
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

-- create_action_item: captura de 20260805000455_1383_w3_event_authority_scoping.sql
CREATE OR REPLACE FUNCTION public.create_action_item(p_event_id uuid, p_description text, p_assignee_id uuid DEFAULT NULL::uuid, p_due_date date DEFAULT NULL::date, p_board_item_id uuid DEFAULT NULL::uuid, p_checklist_item_id uuid DEFAULT NULL::uuid, p_kind text DEFAULT 'action'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_action_id uuid;
  v_assignee_name text;
  v_event record;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- ADR-0105: card de iniciativa confidencial, só para quem a enxerga. Vale para o card e para o item de checklist ligados.
  IF (p_board_item_id IS NOT NULL AND NOT public.rls_can_see_item(p_board_item_id))
     OR (p_checklist_item_id IS NOT NULL AND NOT public.rls_can_see_item(
           (SELECT c.board_item_id FROM public.board_item_checklists c WHERE c.id = p_checklist_item_id))) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access this card';
  END IF;

  -- V4 gate: manage_event (mirrors ADR-0045 RLS on board_item_event_links)
  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Requires manage_event permission';
  END IF;

  -- Validate event exists
  SELECT id, title INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event.id IS NULL THEN RETURN jsonb_build_object('error', 'event_not_found'); END IF;

  -- #1383 W3: scope manage_event to this event's initiative (was resourceless).
  IF NOT public._manage_event_scope_ok(v_caller_id, p_event_id) THEN
    RAISE EXCEPTION 'Requires manage_event permission for this event';
  END IF;

  -- Validate kind
  IF p_kind NOT IN ('action','decision','followup','general') THEN
    RETURN jsonb_build_object('error', 'invalid_kind',
      'valid_kinds', jsonb_build_array('action','decision','followup','general'));
  END IF;

  -- Validate description
  IF p_description IS NULL OR length(trim(p_description)) = 0 THEN
    RETURN jsonb_build_object('error', 'description_required');
  END IF;

  -- Lookup assignee name (snapshot, even if assignee gets renamed later)
  IF p_assignee_id IS NOT NULL THEN
    SELECT name INTO v_assignee_name FROM public.members WHERE id = p_assignee_id;
    IF v_assignee_name IS NULL THEN
      RETURN jsonb_build_object('error', 'assignee_not_found', 'assignee_id', p_assignee_id);
    END IF;
  END IF;

  INSERT INTO public.meeting_action_items (
    event_id, description, assignee_id, assignee_name, due_date,
    board_item_id, checklist_item_id, kind, status, created_by
  ) VALUES (
    p_event_id, trim(p_description), p_assignee_id, v_assignee_name, p_due_date,
    p_board_item_id, p_checklist_item_id, p_kind,
    CASE WHEN p_kind = 'decision' THEN 'done' ELSE 'open' END,
    v_caller_id
  )
  RETURNING id INTO v_action_id;

  -- If linked to a board_item, also create board_item_event_links entry
  IF p_board_item_id IS NOT NULL THEN
    INSERT INTO public.board_item_event_links (
      organization_id, board_item_id, event_id, link_type, author_id, note
    )
    SELECT bi.organization_id, p_board_item_id, p_event_id,
      CASE p_kind
        WHEN 'decision' THEN 'decision'
        WHEN 'action' THEN 'action_emerged'
        ELSE 'discussed'
      END,
      v_caller_id, trim(p_description)
    FROM public.board_items bi
    WHERE bi.id = p_board_item_id
    ON CONFLICT (board_item_id, event_id, link_type) DO NOTHING;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'action_item_id', v_action_id,
    'event_id', p_event_id,
    'kind', p_kind,
    'created_at', now()
  );
END;
$function$;

-- register_decision: captura de 20260805000455_1383_w3_event_authority_scoping.sql
CREATE OR REPLACE FUNCTION public.register_decision(p_event_id uuid, p_title text, p_description text DEFAULT NULL::text, p_related_card_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_action_id uuid;
  v_event record;
  v_full_text text;
  v_card_id uuid;
  v_links_created int := 0;
  v_card_org uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- ADR-0105: card de iniciativa confidencial, só para quem a enxerga. Todos os cards da lista, antes da primeira escrita.
  IF EXISTS (SELECT 1 FROM unnest(coalesce(p_related_card_ids, '{}'::uuid[])) AS rc(id)
             WHERE NOT public.rls_can_see_item(rc.id)) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access this card';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Requires manage_event permission';
  END IF;

  SELECT id INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  -- #1383 W3: scope manage_event to this event's initiative (was resourceless).
  IF NOT public._manage_event_scope_ok(v_caller_id, p_event_id) THEN
    RAISE EXCEPTION 'Requires manage_event permission for this event';
  END IF;

  IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
    RETURN jsonb_build_object('error', 'title_required');
  END IF;

  v_full_text := trim(p_title) ||
    CASE WHEN p_description IS NOT NULL AND length(trim(p_description)) > 0
      THEN E'\n\n' || trim(p_description)
      ELSE ''
    END;

  -- Decision is an action item with kind='decision' (terminal status 'done')
  INSERT INTO public.meeting_action_items (
    event_id, description, kind, status, created_by
  ) VALUES (
    p_event_id, v_full_text, 'decision', 'done', v_caller_id
  )
  RETURNING id INTO v_action_id;

  -- Mark resolved with timestamp
  UPDATE public.meeting_action_items
  SET resolved_at = now(),
      resolved_by = v_caller_id,
      resolution_note = 'Decision registered',
      updated_at = now()
  WHERE id = v_action_id;

  -- Fanout: link decision to each related card via board_item_event_links
  IF p_related_card_ids IS NOT NULL AND array_length(p_related_card_ids, 1) > 0 THEN
    FOREACH v_card_id IN ARRAY p_related_card_ids
    LOOP
      SELECT organization_id INTO v_card_org FROM public.board_items WHERE id = v_card_id;
      IF v_card_org IS NOT NULL THEN
        INSERT INTO public.board_item_event_links (
          organization_id, board_item_id, event_id, link_type, author_id, note
        ) VALUES (
          v_card_org, v_card_id, p_event_id, 'decision', v_caller_id,
          'Decision: ' || trim(p_title)
        )
        ON CONFLICT (board_item_id, event_id, link_type) DO NOTHING;
        GET DIAGNOSTICS v_links_created = ROW_COUNT;
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'decision_id', v_action_id,
    'event_id', p_event_id,
    'title', trim(p_title),
    'related_cards_linked', COALESCE(array_length(p_related_card_ids, 1), 0),
    'created_at', now()
  );
END;
$function$;

-- link_partner_to_card: captura de 20260685000000_p178_phase_b_drift_capture_1_touch_h_p_25fns.sql
CREATE OR REPLACE FUNCTION public.link_partner_to_card(p_partner_entity_id uuid, p_board_item_id uuid, p_link_role text DEFAULT 'general'::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_partner_exists boolean;
  v_card_exists boolean;
  v_link_id uuid;
  v_was_update boolean := false;
BEGIN
  SELECT m.id, m.name INTO v_member
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- ADR-0105: card de iniciativa confidencial, só para quem a enxerga.
  IF NOT public.rls_can_see_item(p_board_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access this card' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_partner') THEN
    RAISE EXCEPTION 'Access denied: manage_partner required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT EXISTS(SELECT 1 FROM public.partner_entities WHERE id = p_partner_entity_id) INTO v_partner_exists;
  IF NOT v_partner_exists THEN
    RAISE EXCEPTION 'partner_entity not found (id=%)', p_partner_entity_id USING ERRCODE = 'no_data_found';
  END IF;

  SELECT EXISTS(SELECT 1 FROM public.board_items WHERE id = p_board_item_id) INTO v_card_exists;
  IF NOT v_card_exists THEN
    RAISE EXCEPTION 'board_item not found (id=%)', p_board_item_id USING ERRCODE = 'no_data_found';
  END IF;

  IF p_link_role NOT IN ('general','pipeline','deliverable','follow_up','contract','onboarding') THEN
    RAISE EXCEPTION 'invalid link_role: %. Must be: general|pipeline|deliverable|follow_up|contract|onboarding', p_link_role
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  INSERT INTO public.partner_cards (partner_entity_id, board_item_id, link_role, notes, created_by)
  VALUES (p_partner_entity_id, p_board_item_id, p_link_role, p_notes, v_member.id)
  ON CONFLICT (partner_entity_id, board_item_id) DO UPDATE
    SET link_role = EXCLUDED.link_role,
        notes = COALESCE(EXCLUDED.notes, public.partner_cards.notes),
        updated_at = now()
  RETURNING id, (xmax <> 0) INTO v_link_id, v_was_update;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_member.id,
    CASE WHEN v_was_update THEN 'partner_card.updated' ELSE 'partner_card.linked' END,
    'partner_card', v_link_id,
    jsonb_build_object('partner_entity_id', p_partner_entity_id, 'board_item_id', p_board_item_id, 'link_role', p_link_role)
  );

  RETURN jsonb_build_object(
    'success', true,
    'link_id', v_link_id,
    'was_update', v_was_update,
    'partner_entity_id', p_partner_entity_id,
    'board_item_id', p_board_item_id,
    'link_role', p_link_role
  );
END;
$function$;

-- unlink_partner_from_card: captura de 20260686000000_p178_phase_b_drift_capture_1_touch_q_z_underscore_63fns.sql
CREATE OR REPLACE FUNCTION public.unlink_partner_from_card(p_partner_entity_id uuid, p_board_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_deleted_id uuid;
BEGIN
  SELECT m.id, m.name INTO v_member
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- ADR-0105: card de iniciativa confidencial, só para quem a enxerga.
  IF NOT public.rls_can_see_item(p_board_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access this card' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_partner') THEN
    RAISE EXCEPTION 'Access denied: manage_partner required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  DELETE FROM public.partner_cards
  WHERE partner_entity_id = p_partner_entity_id AND board_item_id = p_board_item_id
  RETURNING id INTO v_deleted_id;

  IF v_deleted_id IS NOT NULL THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (
      v_member.id, 'partner_card.unlinked', 'partner_card', v_deleted_id,
      jsonb_build_object('partner_entity_id', p_partner_entity_id, 'board_item_id', p_board_item_id)
    );
  END IF;

  RETURN jsonb_build_object('success', (v_deleted_id IS NOT NULL), 'deleted_id', v_deleted_id);
END;
$function$;

-- upsert_publication_submission_event: captura de 20260519183955_p200_v4_curate_content_batch_c_governance_fns.sql
CREATE OR REPLACE FUNCTION public.upsert_publication_submission_event(p_board_item_id uuid, p_channel text DEFAULT 'projectmanagement_com'::text, p_submitted_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_outcome text DEFAULT 'pending'::text, p_notes text DEFAULT NULL::text, p_external_link text DEFAULT NULL::text, p_published_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS publication_submission_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor uuid;
  v_member public.members%rowtype;
  v_row public.publication_submission_events%rowtype;
begin
  v_actor := auth.uid();
  if v_actor is null then raise exception 'Auth required'; end if;
  select * into v_member from public.members where auth_id = v_actor and is_active = true limit 1;
  if v_member.id is null then raise exception 'Member not found'; end if;
  -- ADR-0105: card de iniciativa confidencial, só para quem a enxerga.
  if not public.rls_can_see_item(p_board_item_id) then raise exception 'Unauthorized: cannot access this card'; end if;
  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
  -- Other designations (co_gp, comms_leader, comms_member) preserved as V3.
  if not (
    coalesce(v_member.is_superadmin, false)
    or v_member.operational_role in ('manager', 'deputy_manager', 'communicator')
    or public.can_by_member(v_member.id, 'curate_content')
    or exists (select 1 from unnest(coalesce(v_member.designations, array[]::text[])) d where d in ('co_gp', 'comms_leader', 'comms_member'))
  ) then raise exception 'Publication workflow access required'; end if;
  insert into public.publication_submission_events (board_item_id, channel, submitted_at, outcome, notes, external_link, published_at, updated_by)
  values (p_board_item_id, coalesce(nullif(trim(p_channel), ''), 'projectmanagement_com'), p_submitted_at, p_outcome, nullif(trim(p_notes), ''), nullif(trim(p_external_link), ''), p_published_at, v_member.id)
  returning * into v_row;
  return v_row;
end;
$function$;

-- EXECUTE de anon (o comportamento para anon não muda: já era recusado por dentro).
REVOKE ALL ON FUNCTION public.assign_member_to_item(p_item_id uuid, p_member_id uuid, p_role text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_member_to_item(p_item_id uuid, p_member_id uuid, p_role text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.convert_action_to_card(p_action_item_id uuid, p_board_id uuid, p_title text, p_description text, p_status text, p_due_date date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.convert_action_to_card(p_action_item_id uuid, p_board_id uuid, p_title text, p_description text, p_status text, p_due_date date) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_action_item(p_event_id uuid, p_description text, p_assignee_id uuid, p_due_date date, p_board_item_id uuid, p_checklist_item_id uuid, p_kind text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_action_item(p_event_id uuid, p_description text, p_assignee_id uuid, p_due_date date, p_board_item_id uuid, p_checklist_item_id uuid, p_kind text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_board_item(p_board_id uuid, p_title text, p_description text, p_assignee_id uuid, p_tags text[], p_due_date date, p_status text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_board_item(p_board_id uuid, p_title text, p_description text, p_assignee_id uuid, p_tags text[], p_due_date date, p_status text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.move_item_to_board(p_item_id uuid, p_target_board_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.move_item_to_board(p_item_id uuid, p_target_board_id uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.publish_board_item_from_curation(p_item_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.publish_board_item_from_curation(p_item_id uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.register_decision(p_event_id uuid, p_title text, p_description text, p_related_card_ids uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_decision(p_event_id uuid, p_title text, p_description text, p_related_card_ids uuid[]) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.unassign_member_from_item(p_item_id uuid, p_member_id uuid, p_role text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unassign_member_from_item(p_item_id uuid, p_member_id uuid, p_role text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.update_board_item(p_item_id uuid, p_fields jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_board_item(p_item_id uuid, p_fields jsonb) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.upsert_board_item(p_item_id uuid, p_board_id uuid, p_title text, p_description text, p_status text, p_assignee_id uuid, p_due_date date, p_tags text[], p_labels jsonb, p_checklist jsonb, p_attachments jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_board_item(p_item_id uuid, p_board_id uuid, p_title text, p_description text, p_status text, p_assignee_id uuid, p_due_date date, p_tags text[], p_labels jsonb, p_checklist jsonb, p_attachments jsonb) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.upsert_publication_submission_event(p_board_item_id uuid, p_channel text, p_submitted_at timestamp with time zone, p_outcome text, p_notes text, p_external_link text, p_published_at timestamp with time zone) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_publication_submission_event(p_board_item_id uuid, p_channel text, p_submitted_at timestamp with time zone, p_outcome text, p_notes text, p_external_link text, p_published_at timestamp with time zone) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
