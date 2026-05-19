-- p200 (OPP-196.E, ADR-0087 §2 Batch A, 2026-05-19): V4 swap
-- `'curator' = ANY(designations)` → `can_by_member('curate_content')` in
-- 5 board fns. Surgical swap: only the curator clause; other OR clauses
-- (`co_gp`, `tribe_leader`, `comms_*`) preserved as V3 (out of scope).
--
-- Functions touched:
--   admin_archive_board_item — domain=publications_submissions curator clause
--   assign_member_to_item    — p_role=curation_reviewer curator validation
--   create_board_item        — publications_submissions curator clause
--   update_board_item        — publications_submissions curator clause
--   upsert_board_item        — publications_submissions curator clause
--
-- All 5 use CREATE OR REPLACE FUNCTION (same signature; idempotent).
--
-- ROLLBACK: revert each CREATE OR REPLACE to its V3 form (one clause swap
-- per fn). The V3 path `'curator' = ANY(designations)` continues to work
-- because the array is not touched.

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

CREATE OR REPLACE FUNCTION public.assign_member_to_item(p_item_id uuid, p_member_id uuid, p_role text DEFAULT 'author'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller members%rowtype;
  v_item board_items%rowtype;
  v_board record;
  v_member members%rowtype;
  v_assignment_id uuid;
  v_is_board_admin boolean;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;
  SELECT pb.* INTO v_board FROM project_boards pb WHERE pb.id = v_item.board_id;
  v_is_board_admin := EXISTS (
    SELECT 1 FROM board_members bm
    WHERE bm.board_id = v_board.id AND bm.member_id = v_caller.id AND bm.board_role = 'admin'
  );

  -- ADR-0041: V4 catalog OR Path Y (tribe_leader op-role / board_admin / self+author claim / curator+curation_reviewer)
  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
  IF NOT (
    public.can_by_member(v_caller.id, 'participate_in_governance_review')
    OR v_caller.operational_role = 'tribe_leader'
    OR v_is_board_admin
    OR (p_role = 'curation_reviewer' AND public.can_by_member(v_caller.id, 'curate_content'))
    OR (v_caller.id = p_member_id AND p_role = 'author')
  ) THEN
    RAISE EXCEPTION 'Requires participate_in_governance_review, tribe_leader, board admin, curate_content (for curation_reviewer), or self-claim (author)';
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
$function$;

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
  IF NOT public.can_by_member(v_caller.id, 'write_board') AND NOT v_is_tribe_member AND NOT (
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

  -- p180 ADR-0011 V4: hybrid v_is_gp authority. V3 surface preserved
  -- (is_superadmin + operational_role + co_gp designation). V4 path added
  -- via can_by_member('manage_platform') — catalog covers volunteer × {co_gp,
  -- deputy_manager, manager} = same surface today. Defense-in-depth for cache
  -- drift / future seed expansion.
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

  -- New: comms team in communication domain (Item 02 + Item 03 fix)
  v_is_comms_for_domain := coalesce(v_board.domain_key, '') = 'communication' AND (
    v_caller.operational_role = 'communicator'
    OR coalesce('comms_team' = ANY(v_caller.designations), false)
    OR coalesce('comms_leader' = ANY(v_caller.designations), false)
    OR coalesce('comms_member' = ANY(v_caller.designations), false)
  );

  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
  IF NOT public.can_by_member(v_caller.id, 'write_board')
     AND NOT v_is_board_admin AND NOT v_is_card_owner AND NOT v_is_board_editor
     AND NOT v_is_comms_for_domain THEN
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
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin THEN
      RAISE EXCEPTION 'Only Leader or GP can change baseline';
    END IF;
  END IF;

  IF p_fields ? 'forecast_date' THEN
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin AND NOT v_is_card_owner AND NOT v_is_board_editor AND NOT v_is_comms_for_domain THEN
      RAISE EXCEPTION 'Only Leader, GP, card owner, or board editor can change forecast';
    END IF;
  END IF;

  IF p_fields ? 'assignee_id' THEN
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin AND NOT v_is_comms_for_domain THEN
      RAISE EXCEPTION 'Only Leader, GP, Board Admin, or comms team (in communication board) can change assignee';
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

NOTIFY pgrst, 'reload schema';
