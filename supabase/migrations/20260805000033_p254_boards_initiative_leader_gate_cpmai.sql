-- ============================================================
-- p254 — Boards hotfix: initiative-leader engagement gate (CPMAI/Fernando)
-- ------------------------------------------------------------
-- WHAT: Adds an engagement-derived "initiative leader" predicate to two
--   board write RPCs so initiative leaders / coordinators / managers / co_gps
--   of THAT initiative can edit and move cards on THAT initiative's board(s).
--
--   1. CREATE OR REPLACE public.update_board_item(uuid, jsonb) — same sig.
--      Declares v_is_initiative_leader boolean. Computes it from EXISTS on
--      public.engagements (status=active, initiative_id = board.initiative_id,
--      role IN ('leader','coordinator','manager','co_gp')) keyed on caller's
--      person_id (V4 ladder). Threads v_is_initiative_leader through the
--      outer "Insufficient permissions" gate AND the per-field gates
--      (baseline_date, forecast_date, assignee_id, is_portfolio_item) so
--      initiative leaders can adjust the same fields a tribe_leader can.
--      All other gates (V4 can_by_member('write_board'), v_is_gp,
--      v_is_card_owner, v_is_board_admin, v_is_board_editor,
--      v_is_comms_for_domain, v_is_leader legacy-tribe-match,
--      publications_submissions domain carve-out) PRESERVED verbatim.
--
--   2. CREATE OR REPLACE public.move_board_item(uuid, text, integer, text)
--      — same sig. Declares v_is_initiative_leader (same predicate). Adds
--      it to BOTH "mark as done" and "Unauthorized requires write_board"
--      gates so a leader can move + close cards on their initiative's
--      board. All other gates PRESERVED.
--
-- WHY: Bug surfaced via CPMAI study group — Fernando Maquiaveli has active
--   engagements as study_group_owner (role='leader') on the parent CPMAI
--   study group AND workgroup_coordinator (role='coordinator') on the
--   Capilarização CPMAI child workgroup, but cannot edit/move cards on
--   either board because:
--     - v_is_leader uses operational_role='tribe_leader' + members.tribe_id
--       = initiative.legacy_tribe_id. Study groups / workgroups have NULL
--       legacy_tribe_id so the predicate never fires for non-research-tribe
--       initiatives.
--     - V4 can_by_member('write_board') catalog seeds tribe_leader role,
--       not study_group_owner / workgroup_coordinator.
--     - No board_members row added manually for Fernando (data-fix path
--       PM ruled out as paliativo).
--   PM rule: the structural fix is "initiative leader by engagement,
--   regardless of initiative kind". Narrow predicate based on the V4
--   engagements graph.
--
-- ROLES INCLUDED ('leader','coordinator','manager','co_gp'):
--   - 'leader'      — research-tribe + study-group owner + volunteer leader
--   - 'coordinator' — workgroup_coordinator (Fernando's child engagement)
--   - 'manager'     — initiative manager role
--   - 'co_gp'       — co-GP of initiative
--
-- ROLES EXCLUDED (drift watch — these must NOT inherit edit rights):
--   - 'researcher','participant','board_member','observer','ambassador',
--     'reviewer','liaison','sponsor','curator','co_presenter','founder',
--     'lead_presenter'
--   → Common participants keep read-only / card-owner rights only.
--
-- SPEC DRIFT RESOLVED: none — forward-looking hotfix.
--
-- ROLLBACK: re-apply the prior bodies from
--   supabase/migrations/20260802000001_p209_issue_226_phase_b_drift_capture_26_fns.sql
--   Safe (same signatures, additive predicate).
--
-- INVARIANTS: 19/19=0 unchanged. No tables / FKs / RLS / triggers touched.
--   ACL preserved (CREATE OR REPLACE keeps EXECUTE grants intact).
--
-- SEDIMENT-246.B FOOTNOTE: bodies below match live byte-for-byte
--   (post-apply_migration). Original draft had inline -- comments
--   documenting the predicate intent; apply_migration MCP silently
--   strips inline -- inside AS $$ ... $$. Replaced with live capture
--   to keep Phase C body-drift gate green. WHY documentation lives in
--   this header instead.
--
-- CROSS-REF:
--   This PR scope: BOARDS — paired with HF2 in same bundle PR.
-- ============================================================

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

  IF NOT public.can_by_member(v_caller.id, 'write_board')
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

  IF NOT public.can_by_member(v_actor.id, 'write_board') AND NOT v_is_card_owner AND NOT v_is_comms_for_domain AND NOT v_is_initiative_leader THEN
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

NOTIFY pgrst, 'reload schema';
