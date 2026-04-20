-- ADR-0015 sweep follow-up: 9 funções com refs stale a project_boards.tribe_id
-- (Phase 3d, dropado commit 40ed5c2), board_items.tribe_id, e events.tribe_id
-- (Phase 3e, dropado commit 4d2a10d). Descobertas via sweep p36 — trigger
-- enforce_project_board_taxonomy estava silenciosamente bloqueando TODAS writes
-- em project_boards há 5 dias (último write 2026-04-15).
--
-- Padrão de fix: derivar legacy_tribe_id via initiative_id → initiatives.legacy_tribe_id.
-- Lista de funções refatoradas:
--   1. enforce_project_board_taxonomy (TRIGGER BEFORE INSERT/UPDATE em project_boards)
--   2. assign_checklist_item
--   3. complete_checklist_item
--   4. create_board_item
--   5. move_board_item
--   6. update_board_item
--   7. get_board_members
--   8. get_my_cards
--   9. get_dropout_risk_members
--
-- Rollback: migration anterior a esta preserva a lógica literal pré-fix (stale refs).
-- Reverter apenas se uma função específica precisar reverter — todas são refatorações
-- independentes via mesmo padrão. Sem side-effects: signatures + shapes inalterados.

BEGIN;

-- =============================================================================
-- 1. TRIGGER: enforce_project_board_taxonomy
-- =============================================================================
-- Substitui new.tribe_id por lookup em initiatives.legacy_tribe_id via initiative_id.
-- Semântica preservada:
--   - global boards: initiative sem legacy_tribe_id (ou sem initiative_id)
--   - tribe/operational boards: initiative com legacy_tribe_id NOT NULL
--
-- Data validada: 5 global boards (3 com initiative study_group/workgroup
-- legacy_tribe_id=null + 2 sem initiative), 9 tribe boards (todos com research_tribe
-- initiative legacy_tribe_id NOT NULL). Todos aprovam o novo check.

CREATE OR REPLACE FUNCTION public.enforce_project_board_taxonomy()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_legacy_tribe_id int;
BEGIN
  SELECT legacy_tribe_id INTO v_legacy_tribe_id
  FROM public.initiatives WHERE id = new.initiative_id;

  IF new.board_scope = 'global' AND v_legacy_tribe_id IS NOT NULL THEN
    RAISE EXCEPTION 'Global boards must not point to a tribe-scoped initiative';
  END IF;

  IF new.board_scope = 'tribe' AND v_legacy_tribe_id IS NULL THEN
    RAISE EXCEPTION 'Tribe boards require initiative_id pointing to tribe-scoped initiative';
  END IF;

  IF new.board_scope = 'operational' AND v_legacy_tribe_id IS NULL THEN
    RAISE EXCEPTION 'Operational boards require initiative_id pointing to tribe-scoped initiative';
  END IF;

  IF coalesce(new.domain_key, '') = '' AND new.board_scope IN ('global', 'operational') THEN
    RAISE EXCEPTION 'domain_key is required for global and operational boards';
  END IF;

  RETURN new;
END;
$function$;

-- =============================================================================
-- 2. assign_checklist_item
-- =============================================================================
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
  v_board record;
  v_board_legacy_tribe_id int;
  v_is_gp boolean;
  v_is_leader boolean;
  v_is_card_owner boolean;
  v_is_board_admin boolean;
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

  v_is_card_owner := v_card.assignee_id = v_caller.id;

  v_is_board_admin := EXISTS (
    SELECT 1 FROM board_members bm
    WHERE bm.board_id = v_board.id AND bm.member_id = v_caller.id
    AND bm.board_role = 'admin'
  );

  IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_card_owner AND NOT v_is_board_admin THEN
    RAISE EXCEPTION 'Only Leader, GP, or card owner can assign activities';
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

-- =============================================================================
-- 3. complete_checklist_item
-- =============================================================================
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

  v_is_card_owner := v_card.assignee_id = v_caller.id;
  v_is_activity_owner := v_item.assigned_to = v_caller.id OR v_item.assigned_to IS NULL;

  IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_card_owner AND NOT v_is_activity_owner THEN
    RAISE EXCEPTION 'You can only complete activities assigned to you';
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

-- =============================================================================
-- 4. create_board_item
-- =============================================================================
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

  IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_tribe_member AND NOT (
    (coalesce(v_board.domain_key, '') = 'communication' AND (
      v_caller.operational_role = 'communicator'
      OR coalesce('comms_team' = ANY(v_caller.designations), false)
      OR coalesce('comms_leader' = ANY(v_caller.designations), false)
      OR coalesce('comms_member' = ANY(v_caller.designations), false)
    ))
    OR (coalesce(v_board.domain_key, '') = 'publications_submissions' AND (
      v_caller.operational_role IN ('tribe_leader', 'communicator')
      OR coalesce('curator' = ANY(v_caller.designations), false)
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

-- =============================================================================
-- 5. move_board_item
-- =============================================================================
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
BEGIN
  SELECT status, board_id INTO v_old_status, v_board_id FROM board_items WHERE id = p_item_id;
  IF v_old_status IS NULL THEN RAISE EXCEPTION 'Item not found'; END IF;
  SELECT * INTO v_actor FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_board FROM project_boards WHERE id = v_board_id;

  -- ADR-0015 Phase 3d: project_boards.tribe_id dropado; derivar via initiative
  SELECT legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives WHERE id = v_board.initiative_id;

  v_is_gp := coalesce(v_actor.is_superadmin, false) OR v_actor.operational_role IN ('manager','deputy_manager') OR coalesce('co_gp' = ANY(v_actor.designations), false);
  v_is_leader := v_actor.operational_role = 'tribe_leader' AND v_actor.tribe_id = v_board_legacy_tribe_id;

  v_is_card_owner := EXISTS (SELECT 1 FROM board_items WHERE id = p_item_id AND (created_by = v_actor.id OR assignee_id = v_actor.id))
    OR EXISTS (SELECT 1 FROM board_item_assignments WHERE item_id = p_item_id AND member_id = v_actor.id);

  IF p_new_status = 'done' AND NOT v_is_gp AND NOT v_is_leader THEN
    RAISE EXCEPTION 'Only Leader or GP can mark as completed';
  END IF;

  IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_card_owner THEN
    RAISE EXCEPTION 'You can only move your own cards';
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

-- =============================================================================
-- 6. update_board_item
-- =============================================================================
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
  v_new_assignee uuid;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_old FROM board_items WHERE id = p_item_id;
  IF v_old.id IS NULL THEN RAISE EXCEPTION 'Item not found: %', p_item_id; END IF;

  v_board_id := v_old.board_id;
  SELECT * INTO v_board FROM project_boards WHERE id = v_board_id;

  -- ADR-0015 Phase 3d: project_boards.tribe_id dropado; derivar via initiative
  SELECT legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives WHERE id = v_board.initiative_id;

  v_is_gp := coalesce(v_caller.is_superadmin, false)
    OR v_caller.operational_role IN ('manager', 'deputy_manager')
    OR coalesce('co_gp' = ANY(v_caller.designations), false);

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

  IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin AND NOT v_is_card_owner AND NOT v_is_board_editor THEN
    IF NOT (
      (coalesce(v_board.domain_key, '') = 'communication' AND (
        v_caller.operational_role = 'communicator'
        OR coalesce('comms_team' = ANY(v_caller.designations), false)
        OR coalesce('comms_leader' = ANY(v_caller.designations), false)
        OR coalesce('comms_member' = ANY(v_caller.designations), false)
      ))
      OR (coalesce(v_board.domain_key, '') = 'publications_submissions' AND (
        v_caller.operational_role IN ('tribe_leader', 'communicator')
        OR coalesce('curator' = ANY(v_caller.designations), false)
        OR coalesce('co_gp' = ANY(v_caller.designations), false)
        OR coalesce('comms_leader' = ANY(v_caller.designations), false)
        OR coalesce('comms_member' = ANY(v_caller.designations), false)
      ))
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
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin THEN
      RAISE EXCEPTION 'Only Leader or GP can change baseline';
    END IF;
  END IF;

  IF p_fields ? 'forecast_date' THEN
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin AND NOT v_is_card_owner AND NOT v_is_board_editor THEN
      RAISE EXCEPTION 'Only Leader, GP, or card owner can change forecast';
    END IF;
  END IF;

  IF p_fields ? 'assignee_id' THEN
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin THEN
      RAISE EXCEPTION 'Only Leader or GP can change assignee';
    END IF;
  END IF;

  IF p_fields ? 'is_portfolio_item' THEN
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin THEN
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

-- =============================================================================
-- 7. get_board_members
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_board_members(p_board_id uuid)
 RETURNS TABLE(id uuid, name text, photo_url text, operational_role text, board_role text, designations text[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_board record;
  v_board_legacy_tribe_id int;
BEGIN
  SELECT pb.* INTO v_board FROM project_boards pb WHERE pb.id = p_board_id;
  IF NOT FOUND THEN RETURN; END IF;

  -- ADR-0015 Phase 3d: project_boards.tribe_id dropado; derivar via initiative
  -- OBS: usa alias i.* para desambiguar de OUT param `id` do TABLE signature
  SELECT i.legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives i WHERE i.id = v_board.initiative_id;

  RETURN QUERY
  SELECT DISTINCT ON (q.id) q.id, q.name, q.photo_url, q.operational_role, q.board_role, q.designations
  FROM (
    SELECT m.id, m.name, m.photo_url, m.operational_role, 'tribe_member'::text as board_role, m.designations, 1 as priority
    FROM members m
    WHERE v_board_legacy_tribe_id IS NOT NULL
      AND m.tribe_id = v_board_legacy_tribe_id
      AND m.is_active = true
      AND m.member_status = 'active'

    UNION ALL

    SELECT bm.member_id, m.name, m.photo_url, m.operational_role, bm.board_role, m.designations, 2
    FROM board_members bm
    JOIN members m ON m.id = bm.member_id
    WHERE bm.board_id = p_board_id
      AND m.is_active = true

    UNION ALL

    SELECT m.id, m.name, m.photo_url, m.operational_role, 'curator'::text, m.designations, 3
    FROM members m
    WHERE 'curator' = ANY(m.designations)
      AND m.is_active = true

    UNION ALL

    SELECT m.id, m.name, m.photo_url, m.operational_role, 'gp'::text, m.designations, 4
    FROM members m
    WHERE m.is_active = true
      AND (m.is_superadmin = true OR m.operational_role IN ('manager', 'deputy_manager'))
  ) q
  ORDER BY q.id, q.priority;
END;
$function$;

-- =============================================================================
-- 8. get_my_cards
-- =============================================================================
-- Refactor: substitui JOIN tribes via bi.tribe_id (dropado board_items) por
-- JOIN via pb.initiative_id → initiatives.legacy_tribe_id → tribes.id
CREATE OR REPLACE FUNCTION public.get_my_cards()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RETURN json_build_object('error', 'Not authenticated'); END IF;

  RETURN (
    SELECT json_agg(row_to_json(r) ORDER BY r.sort_priority, r.updated_at DESC)
    FROM (
      SELECT
        bi.id,
        bi.title,
        bi.status,
        bi.due_date,
        bi.forecast_date,
        bi.tags,
        bi.updated_at,
        bia.role as my_role,
        pb.board_name as board_name,
        t.name as tribe_name,
        t.id as tribe_id,
        CASE bi.status
          WHEN 'in_progress' THEN 1
          WHEN 'review' THEN 2
          WHEN 'backlog' THEN 3
          WHEN 'todo' THEN 4
          ELSE 5
        END as sort_priority
      FROM board_item_assignments bia
      JOIN board_items bi ON bi.id = bia.item_id
      JOIN project_boards pb ON pb.id = bi.board_id
      LEFT JOIN initiatives ini ON ini.id = pb.initiative_id
      LEFT JOIN tribes t ON t.id = ini.legacy_tribe_id
      WHERE bia.member_id = v_member_id
        AND bi.status NOT IN ('archived', 'done')
    ) r
  );
END;
$function$;

-- =============================================================================
-- 9. get_dropout_risk_members
-- =============================================================================
-- Refactor: substitui e2.tribe_id (events dropado) por EXISTS via initiatives
CREATE OR REPLACE FUNCTION public.get_dropout_risk_members(p_threshold integer DEFAULT 3)
 RETURNS TABLE(member_id uuid, member_name text, tribe_id integer, tribe_name text, operational_role text, last_attendance_date date, days_since_last bigint, missed_events integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  WITH active_members AS (
    SELECT m.id, m.name, m.tribe_id, t.name as tname, m.operational_role
    FROM members m
    LEFT JOIN tribes t ON t.id = m.tribe_id
    WHERE m.is_active AND m.operational_role IN ('researcher','tribe_leader','manager')
  ),
  member_expected_events AS (
    SELECT am.id as mid, e.id as eid, e.date,
      ROW_NUMBER() OVER (PARTITION BY am.id ORDER BY e.date DESC) as rn
    FROM active_members am
    CROSS JOIN LATERAL (
      SELECT e2.id, e2.date FROM events e2
      LEFT JOIN initiatives ini ON ini.id = e2.initiative_id
      WHERE e2.date <= current_date
        AND (
          e2.type IN ('general_meeting','kickoff')
          OR (e2.type = 'tribe_meeting' AND ini.legacy_tribe_id = am.tribe_id)
          OR (e2.type = 'leadership_meeting' AND am.operational_role IN ('manager','tribe_leader'))
        )
      ORDER BY e2.date DESC
      LIMIT p_threshold
    ) e
  ),
  member_misses AS (
    SELECT mee.mid,
      count(*) FILTER (WHERE a.id IS NULL) as missed,
      count(*) as expected
    FROM member_expected_events mee
    LEFT JOIN attendance a ON a.event_id = mee.eid AND a.member_id = mee.mid AND a.present
    WHERE mee.rn <= p_threshold
    GROUP BY mee.mid
  ),
  last_att AS (
    SELECT a.member_id as mid, max(e.date) as last_date
    FROM attendance a JOIN events e ON e.id = a.event_id
    WHERE a.present
    GROUP BY a.member_id
  )
  SELECT am.id, am.name, am.tribe_id, am.tname, am.operational_role,
    la.last_date,
    (current_date - COALESCE(la.last_date, '2025-01-01'))::bigint,
    mm.missed::integer
  FROM active_members am
  JOIN member_misses mm ON mm.mid = am.id
  LEFT JOIN last_att la ON la.mid = am.id
  WHERE mm.missed >= p_threshold
  ORDER BY la.last_date ASC NULLS FIRST;
END;
$function$;

COMMIT;
