-- `write_board` perguntado COM o recurso: lote 2, as 8 RPCs que chegam pelo CARD.
--
-- Continuacao do #1945. O lote 1 fechou as 6 que ja tinham o board em maos; estas chegam pelo
-- card (ou por comentario e checklist), entao ganham um helper irmao que resolve o board a partir
-- do item e delega para `_can_write_board`. Um corpo so decide a regra.
--
-- Fora deste lote, por medicao e nao por recorte: `create_publication_submission` e
-- `admin_manage_publication` NAO sao escopaveis. O portao das duas e puro, os identificadores sao
-- anulaveis, e nem submissao nem publicacao vivem num board -- a pergunta ali e genuinamente "pode
-- em algum lugar?", que e a etapa seguinte do procedimento, nao esta.
--
-- Nota de semantica, igual a do `convert_action_to_card` no lote 1: nas RPCs que gateiam ANTES de
-- carregar o card, um id inexistente passa a devolver o erro de permissao em vez de "nao
-- encontrado" para quem so tem escopo de iniciativa. Quem tem escopo organization segue caindo no
-- "nao encontrado", como antes.

CREATE OR REPLACE FUNCTION public._can_write_board_item(p_member_id uuid, p_item_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Resolve o board do card e delega: a regra de escopo vive num lugar so (`_can_write_board`).
  -- Card inexistente resolve para NULL, e ai so o escopo organization/global passa -- que e o
  -- comportamento certo, porque quem tem autoridade global segue alcancando o "nao encontrado".
  SELECT public._can_write_board(
    p_member_id,
    (SELECT bi.board_id FROM public.board_items bi WHERE bi.id = p_item_id)
  );
$function$;

COMMENT ON FUNCTION public._can_write_board_item(uuid, uuid) IS
  'write_board escopado ao board DO CARD. Delega para _can_write_board; existe para que a RPC que so tem o card em maos nao precise resolver o board a mao.';

REVOKE ALL ON FUNCTION public._can_write_board_item(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._can_write_board_item(uuid, uuid) TO authenticated, service_role;

-- ── 1/8 can_manage_card_checklist: card em `p_card_id` ────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.can_manage_card_checklist(p_member_id uuid, p_card_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT p_member_id IS NOT NULL
     AND p_card_id IS NOT NULL
     -- #785/ADR-0105: nao se administra o trabalho de um card que nao se pode ver
     AND public.rls_can_see_item(p_card_id)
     AND (
       -- capacidade organizacional (o caminho de sempre)
       public._can_write_board_item(p_member_id, p_card_id)
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

-- ── 2/8 delete_card_comment: card em `v_comment.board_item_id` ────────────────────────────────

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

-- ── 3/8 register_card_drive_file: card em `p_board_item_id` ───────────────────────────────────

CREATE OR REPLACE FUNCTION public.register_card_drive_file(p_board_item_id uuid, p_drive_file_id text, p_drive_file_url text, p_filename text, p_mime_type text DEFAULT NULL::text, p_size_bytes bigint DEFAULT NULL::bigint, p_uploaded_via text DEFAULT 'platform'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_new_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT public.rls_can_see_item(p_board_item_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: cannot access this card');
  END IF;
  IF NOT public._can_write_board_item(v_caller_id, p_board_item_id)
     AND NOT EXISTS (SELECT 1 FROM public.board_items bi JOIN public.board_members bm ON bm.board_id = bi.board_id WHERE bi.id = p_board_item_id AND bm.member_id = v_caller_id AND bm.board_role IN ('admin', 'editor'))
     AND NOT EXISTS (SELECT 1 FROM public.board_items bi WHERE bi.id = p_board_item_id AND bi.assignee_id = v_caller_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires write_board permission, card ownership, or board editor role');
  END IF;

  IF p_uploaded_via NOT IN ('platform', 'drive_native_synced') THEN
    RETURN jsonb_build_object('error', 'Invalid uploaded_via — must be platform or drive_native_synced');
  END IF;

  INSERT INTO public.board_item_files (
    board_item_id, drive_file_id, drive_file_url, filename, mime_type,
    size_bytes, uploaded_by, uploaded_via
  ) VALUES (
    p_board_item_id, p_drive_file_id, p_drive_file_url, p_filename,
    p_mime_type, p_size_bytes, v_caller_id, p_uploaded_via
  )
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object(
    'success', true,
    'file_id', v_new_id,
    'drive_file_id', p_drive_file_id
  );
END;
$function$;

-- ── 4/8 create_mirror_card: board ALVO em `p_target_board_id` ─────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_mirror_card(p_source_item_id uuid, p_target_board_id uuid, p_target_status text DEFAULT 'backlog'::text, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_member_id uuid;
  v_source record;
  v_mirror_id uuid;
  v_max_pos integer;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_caller_id LIMIT 1;

  SELECT * INTO v_source FROM public.board_items WHERE id = p_source_item_id;
  IF v_source IS NULL THEN RAISE EXCEPTION 'Source card not found'; END IF;

  IF NOT public.rls_can_see_item(p_source_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access source card';
  END IF;
  IF NOT public.rls_can_see_board(p_target_board_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access target board';
  END IF;
  IF NOT (public._can_write_board(v_member_id, p_target_board_id)
          OR EXISTS (SELECT 1 FROM public.board_members bm WHERE bm.board_id = p_target_board_id AND bm.member_id = v_member_id AND bm.board_role IN ('admin', 'editor'))) THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission or board editor role on the target board';
  END IF;

  SELECT COALESCE(MAX(position), 0) + 1 INTO v_max_pos
  FROM public.board_items
  WHERE board_id = p_target_board_id AND status = p_target_status;

  INSERT INTO public.board_items (
    board_id, title, description, status, tags,
    mirror_source_id, is_mirror, position
  ) VALUES (
    p_target_board_id,
    v_source.title,
    COALESCE(p_notes, v_source.description),
    p_target_status,
    v_source.tags,
    p_source_item_id,
    true,
    v_max_pos
  )
  RETURNING id INTO v_mirror_id;

  UPDATE public.board_items
  SET mirror_target_id = v_mirror_id
  WHERE id = p_source_item_id;

  INSERT INTO public.board_lifecycle_events (item_id, board_id, action, new_status, reason, actor_member_id)
  VALUES
    (p_source_item_id, v_source.board_id, 'mirror_created', v_mirror_id::text,
     'Card espelho criado no board ' || p_target_board_id::text, v_member_id),
    (v_mirror_id, p_target_board_id, 'mirror_created', p_source_item_id::text,
     'Espelho do card: ' || v_source.title, v_member_id);

  RETURN v_mirror_id;
END;
$function$;

-- ── 5/8 update_card_during_meeting: card em `p_card_id` ───────────────────────────────────────

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

-- ── 6/8 complete_checklist_item: board ja resolvido em `v_card.board_id` ──────────────────────
--
-- Esta nao precisa do helper de item: o corpo ja carrega o card E o board antes do portao.

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

-- ── 7/8 create_card_comment: card em `p_board_item_id` ────────────────────────────────────────
--
-- Nota: aqui o ramo de `write_board` e REDUNDANTE, porque `rls_is_member()` ja libera qualquer
-- membro a comentar. Escopar nao muda comportamento; tira a forma sem recurso do corpo, que e o
-- objetivo, sem tocar em quem pode comentar.

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

-- ── 8/8 update_board_item: card em `p_item_id` ────────────────────────────────────────────────
--
-- As outras duas chamadas de capacidade do corpo (`manage_platform` e `curate_content`) NAO sao
-- de board e ficam intocadas.

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
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_old FROM board_items WHERE id = p_item_id;
  IF v_old.id IS NULL THEN RAISE EXCEPTION 'Item not found: %', p_item_id; END IF;

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
    curation_status = coalesce(p_fields->>'curation_status', curation_status),
    curation_due_at = CASE WHEN p_fields ? 'curation_due_at' AND p_fields->>'curation_due_at' IS NOT NULL
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
