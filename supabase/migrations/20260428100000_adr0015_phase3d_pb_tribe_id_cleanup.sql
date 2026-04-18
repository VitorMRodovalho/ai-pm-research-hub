-- ADR-0015 Phase 3d follow-up — sweep 15 RPCs referencing stale `pb.tribe_id`
--
-- Context: Phase 3d (2026-04-18, commit 40ed5c2) dropped project_boards.tribe_id but
-- refatorou apenas 10 das 30 funções que referenciavam a coluna. As 20 restantes ficaram
-- silently broken (plpgsql) ou parse-broken (sql). Phase 3e (commit 4d2a10d) varreu 5
-- delas incidentalmente. Este commit fecha as 15 restantes.
--
-- Pattern: `pb.tribe_id` → `i.legacy_tribe_id` via JOIN initiatives i ON i.id = pb.initiative_id.
-- Special case: admin_link_communication_boards (writer) — update pb.initiative_id via lookup
-- (antes tentava UPDATE em coluna dropada — função 100% broken desde Phase 3d).

-- notify_on_assignment (trigger function)
CREATE OR REPLACE FUNCTION public.notify_on_assignment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_title text;
  v_tribe_id int;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT bi.title INTO v_title FROM board_items bi WHERE bi.id = NEW.item_id;
    BEGIN
      SELECT i.legacy_tribe_id INTO v_tribe_id
      FROM board_items bi
      JOIN project_boards pb ON pb.id = bi.board_id
      LEFT JOIN initiatives i ON i.id = pb.initiative_id
      WHERE bi.id = NEW.item_id;
    EXCEPTION WHEN OTHERS THEN v_tribe_id := NULL;
    END;

    PERFORM create_notification(
      NEW.member_id,
      'assignment_new',
      'Novo card atribuído',
      'Você foi atribuído ao card "' || COALESCE(v_title, '?') || '" como ' || NEW.role,
      CASE WHEN v_tribe_id IS NOT NULL THEN '/tribe/' || v_tribe_id || '?tab=board' ELSE '/workspace' END,
      'board_item',
      NEW.item_id
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.search_board_items(p_query text, p_tribe_id integer DEFAULT NULL::integer)
 RETURNS SETOF json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member_id uuid;
  v_tribe_id integer;
BEGIN
  SELECT id, tribe_id INTO v_member_id, v_tribe_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'auth_required'; END IF;

  IF p_tribe_id IS NULL THEN p_tribe_id := v_tribe_id; END IF;

  RETURN QUERY
  SELECT row_to_json(r)
  FROM (
    SELECT bi.id, bi.title, bi.description, bi.status, bi.tags, bi.due_date, bi.assignee_id
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    JOIN initiatives i ON i.id = pb.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id
      AND bi.status != 'archived'
      AND (bi.title ILIKE '%' || p_query || '%' OR bi.description ILIKE '%' || p_query || '%')
    ORDER BY bi.updated_at DESC
    LIMIT 20
  ) r;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_global_research_pipeline()
 RETURNS json
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT json_build_object(
    'in_progress', (
      SELECT coalesce(json_agg(row_to_json(r)), '[]')
      FROM (
        SELECT bi.id, bi.title, bi.status, bi.due_date, bi.updated_at,
          pb.board_name, i.legacy_tribe_id AS tribe_id,
          i.title as tribe_name,
          (SELECT string_agg(m.name, ', ') FROM board_item_assignments bia JOIN members m ON m.id = bia.member_id WHERE bia.item_id = bi.id AND bia.role = 'author') as authors
        FROM board_items bi
        JOIN project_boards pb ON pb.id = bi.board_id
        LEFT JOIN initiatives i ON i.id = pb.initiative_id
        WHERE pb.domain_key = 'research_delivery' AND bi.status IN ('in_progress', 'review')
        ORDER BY bi.updated_at DESC
      ) r
    ),
    'recently_done', (
      SELECT coalesce(json_agg(row_to_json(r)), '[]')
      FROM (
        SELECT bi.id, bi.title, bi.updated_at,
          i.legacy_tribe_id AS tribe_id,
          i.title as tribe_name
        FROM board_items bi
        JOIN project_boards pb ON pb.id = bi.board_id
        LEFT JOIN initiatives i ON i.id = pb.initiative_id
        WHERE pb.domain_key = 'research_delivery' AND bi.status = 'done'
        ORDER BY bi.updated_at DESC LIMIT 5
      ) r
    ),
    'summary', (
      SELECT json_object_agg(status, cnt)
      FROM (SELECT bi.status, count(*) as cnt FROM board_items bi JOIN project_boards pb ON pb.id = bi.board_id WHERE pb.domain_key = 'research_delivery' AND bi.status NOT IN ('archived') GROUP BY bi.status) s
    )
  );
$function$;

-- admin_link_communication_boards — BROKEN writer (UPDATE pb SET tribe_id em coluna dropada).
-- Refactor: write pb.initiative_id (lookup via legacy_tribe_id).
CREATE OR REPLACE FUNCTION public.admin_link_communication_boards(p_tribe_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_caller record;
  v_target_tribe_id integer;
  v_target_initiative_id uuid;
  v_updated integer := 0;
  v_result jsonb;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      v_caller.is_superadmin is true
      or public.can_by_member(v_caller.id, 'manage_member')
      or coalesce('co_gp' = any(v_caller.designations), false)
    ) then
    raise exception 'Project management access required';
  end if;

  if p_tribe_id is null then
    select (public.admin_ensure_communication_tribe() ->> 'tribe_id')::integer into v_target_tribe_id;
  else
    v_target_tribe_id := p_tribe_id;
  end if;

  SELECT id INTO v_target_initiative_id FROM public.initiatives WHERE legacy_tribe_id = v_target_tribe_id LIMIT 1;

  update public.project_boards pb
  set initiative_id = v_target_initiative_id,
      domain_key = 'communication',
      updated_at = now()
  where (
    lower(coalesce(pb.board_name, '')) like '%comunic%'
    or lower(coalesce(pb.board_name, '')) like '%midias%'
    or exists (
      select 1
      from public.board_items bi
      where bi.board_id = pb.id
        and bi.source_board in ('comunicacao_ciclo3', 'midias_sociais', 'social_media', 'comms_c3')
    )
  )
    and (pb.initiative_id is distinct from v_target_initiative_id or coalesce(pb.domain_key, '') <> 'communication');

  get diagnostics v_updated = row_count;

  v_result := jsonb_build_object(
    'success', true,
    'tribe_id', v_target_tribe_id,
    'initiative_id', v_target_initiative_id,
    'boards_linked', v_updated
  );

  return v_result;
end;
$function$;

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
          or coalesce('curator' = any(v_designations), false)
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

CREATE OR REPLACE FUNCTION public.advance_board_item_curation(p_item_id uuid, p_action text, p_reviewer_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_curation   text;
  v_assignee   uuid;
  v_reviewer   uuid;
  v_tribe_id   integer;
  v_caller     public.members%rowtype;
  v_designations text[];
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  v_designations := coalesce(v_caller.designations, array[]::text[]);

  SELECT bi.curation_status, bi.assignee_id, bi.reviewer_id, i.legacy_tribe_id
    INTO v_curation, v_assignee, v_reviewer, v_tribe_id
  FROM public.board_items bi
  JOIN public.project_boards pb ON pb.id = bi.board_id
  LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
  WHERE bi.id = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Board item not found';
  END IF;

  IF p_action = 'request_review' THEN
    IF v_curation <> 'draft' THEN
      RAISE EXCEPTION 'Only draft items can request peer review';
    END IF;
    IF v_assignee IS DISTINCT FROM v_caller.id THEN
      RAISE EXCEPTION 'Only the author can request peer review';
    END IF;
    IF p_reviewer_id IS NULL THEN
      RAISE EXCEPTION 'Reviewer is required';
    END IF;
    UPDATE public.board_items
    SET curation_status = 'peer_review', reviewer_id = p_reviewer_id, updated_at = now()
    WHERE id = p_item_id;
    RETURN;
  END IF;

  IF p_action = 'approve_peer' THEN
    IF v_curation <> 'peer_review' THEN
      RAISE EXCEPTION 'Only peer_review items can be peer-approved';
    END IF;
    IF v_reviewer IS DISTINCT FROM v_caller.id THEN
      RAISE EXCEPTION 'Only the assigned reviewer can approve';
    END IF;
    UPDATE public.board_items
    SET curation_status = 'leader_review', updated_at = now()
    WHERE id = p_item_id;
    RETURN;
  END IF;

  IF p_action = 'approve_leader' THEN
    IF v_curation <> 'leader_review' THEN
      RAISE EXCEPTION 'Only leader_review items can be leader-approved';
    END IF;
    IF NOT (
      v_caller.is_superadmin = true
      OR public.can_by_member(v_caller.id, 'manage_member')
      OR (v_caller.operational_role = 'tribe_leader' AND v_caller.tribe_id = v_tribe_id)
    ) THEN
      RAISE EXCEPTION 'Only tribe leader or management can approve for curation';
    END IF;
    UPDATE public.board_items
    SET curation_status = 'curation_pending', updated_at = now()
    WHERE id = p_item_id;
    RETURN;
  END IF;

  RAISE EXCEPTION 'Unknown action: %', p_action;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_curation_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_member_id, 'write_board') THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;

  SELECT jsonb_build_object(
    'items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id, 'title', bi.title, 'description', bi.description,
        'status', bi.status, 'curation_status', bi.curation_status,
        'curation_due_at', bi.curation_due_at, 'board_id', bi.board_id,
        'board_name', pb.board_name, 'tribe_id', i.legacy_tribe_id, 'tribe_name', i.title,
        'assignee_id', bi.assignee_id, 'assignee_name', am.name,
        'reviewer_id', bi.reviewer_id, 'reviewer_name', rm.name,
        'tags', bi.tags, 'attachments', bi.attachments,
        'created_at', bi.created_at, 'updated_at', bi.updated_at,
        'review_count', (SELECT count(*) FROM curation_review_log crl WHERE crl.board_item_id = bi.id),
        'reviews_approved', (SELECT count(*) FROM curation_review_log crl WHERE crl.board_item_id = bi.id AND crl.decision = 'approved'),
        'reviewers_required', COALESCE(sc.reviewers_required, 2),
        'sla_status', CASE
          WHEN bi.curation_due_at IS NULL THEN 'no_sla'
          WHEN bi.curation_due_at < now() THEN 'overdue'
          WHEN bi.curation_due_at < now() + interval '2 days' THEN 'warning'
          ELSE 'on_time'
        END,
        'review_history', (
          SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', crl2.id, 'curator_name', cm.name, 'decision', crl2.decision,
            'feedback', crl2.feedback_notes, 'scores', crl2.criteria_scores,
            'completed_at', crl2.completed_at
          ) ORDER BY crl2.completed_at DESC), '[]'::jsonb)
          FROM curation_review_log crl2
          LEFT JOIN members cm ON cm.id = crl2.curator_id
          WHERE crl2.board_item_id = bi.id
        )
      ) ORDER BY
        CASE
          WHEN bi.curation_due_at IS NOT NULL AND bi.curation_due_at < now() THEN 0
          WHEN bi.curation_due_at IS NOT NULL AND bi.curation_due_at < now() + interval '2 days' THEN 1
          ELSE 2
        END,
        bi.curation_due_at ASC NULLS LAST
      )
      FROM board_items bi
      JOIN project_boards pb ON pb.id = bi.board_id
      LEFT JOIN initiatives i ON i.id = pb.initiative_id
      LEFT JOIN members am ON am.id = bi.assignee_id
      LEFT JOIN members rm ON rm.id = bi.reviewer_id
      LEFT JOIN board_sla_config sc ON sc.board_id = bi.board_id
      WHERE bi.curation_status IN ('curation_pending', 'revision_requested')
        AND bi.status <> 'archived'
        AND pb.is_active = true
    ), '[]'::jsonb),
    'summary', jsonb_build_object(
      'total_pending', (SELECT count(*) FROM board_items bi2 JOIN project_boards pb2 ON pb2.id = bi2.board_id WHERE bi2.curation_status = 'curation_pending' AND bi2.status <> 'archived' AND pb2.is_active = true),
      'overdue', (SELECT count(*) FROM board_items bi3 JOIN project_boards pb3 ON pb3.id = bi3.board_id WHERE bi3.curation_status = 'curation_pending' AND bi3.curation_due_at < now() AND bi3.status <> 'archived' AND pb3.is_active = true)
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_cycle_report(p_cycle integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  v_result := jsonb_build_object(
    'cycle', p_cycle,
    'generated_at', now(),
    'members', (SELECT jsonb_build_object(
      'total', count(*),
      'active', count(*) FILTER (WHERE is_active),
      'observers', count(*) FILTER (WHERE member_status = 'observer'),
      'alumni', count(*) FILTER (WHERE member_status = 'alumni'),
      'by_role', (SELECT coalesce(jsonb_object_agg(operational_role, cnt), '{}') FROM (
        SELECT operational_role, count(*) as cnt FROM members WHERE is_active GROUP BY operational_role
      ) r)
    ) FROM members),
    'tribes', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'name', t.name,
      'member_count', (SELECT count(*) FROM members WHERE tribe_id = t.id AND is_active),
      'board_progress', (
        SELECT CASE WHEN count(*) = 0 THEN 0
          ELSE round(100.0 * count(*) FILTER (WHERE bi.status = 'done') / count(*))
        END
        FROM project_boards pb
        JOIN initiatives i ON i.id = pb.initiative_id
        JOIN board_items bi ON bi.board_id = pb.id
        WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived'
      )
    ) ORDER BY t.id), '[]') FROM tribes t WHERE t.is_active),
    'events', (SELECT jsonb_build_object(
      'total', count(*),
      'total_impact_hours', (SELECT * FROM get_homepage_stats())->'impact_hours'
    ) FROM events WHERE date >= '2026-01-01'),
    'boards', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', pb.id, 'title', pb.board_name,
      'total_items', (SELECT count(*) FROM board_items WHERE board_id = pb.id AND status != 'archived'),
      'done_items', (SELECT count(*) FROM board_items WHERE board_id = pb.id AND status = 'done'),
      'progress', (SELECT CASE WHEN count(*) = 0 THEN 0
        ELSE round(100.0 * count(*) FILTER (WHERE status = 'done') / count(*))
      END FROM board_items WHERE board_id = pb.id AND status != 'archived')
    )), '[]') FROM project_boards pb WHERE pb.is_active),
    'kpis', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'name', k.kpi_label_pt, 'name_en', k.kpi_label_en,
      'target', k.target_value, 'current', k.current_value,
      'pct', CASE WHEN k.target_value > 0 THEN round(100.0 * k.current_value / k.target_value) ELSE 0 END
    )), '[]') FROM annual_kpi_targets k WHERE k.year = 2026),
    'platform', jsonb_build_object(
      'releases_count', (SELECT count(*) FROM releases),
      'governance_entries', 125,
      'zero_cost', true,
      'stack', 'Astro 5 + React 19 + Tailwind 4 + Supabase + Cloudflare Pages'
    )
  );
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.exec_portfolio_board_summary(p_include_inactive boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH boards AS (
    SELECT
      pb.id AS board_id, pb.board_name, pb.board_scope,
      COALESCE(pb.domain_key, 'tribe_general') AS domain_key,
      i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name
    FROM public.project_boards pb
    LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
    WHERE (p_include_inactive OR pb.is_active = true)
  ),
  items AS (
    SELECT
      b.board_scope, b.domain_key,
      count(bi.id) AS total_cards,
      count(*) FILTER (WHERE bi.status = 'backlog') AS backlog,
      count(*) FILTER (WHERE bi.status = 'todo') AS todo,
      count(*) FILTER (WHERE bi.status = 'in_progress') AS in_progress,
      count(*) FILTER (WHERE bi.status = 'review') AS review,
      count(*) FILTER (WHERE bi.status = 'done') AS done,
      count(*) FILTER (WHERE bi.status = 'archived') AS archived,
      count(*) FILTER (WHERE bi.assignee_id IS NULL AND bi.status <> 'archived') AS orphan_cards,
      count(*) FILTER (WHERE bi.due_date::date < current_date AND bi.status NOT IN ('done', 'archived')) AS overdue_cards
    FROM boards b
    LEFT JOIN public.board_items bi ON bi.board_id = b.board_id
    GROUP BY b.board_scope, b.domain_key
  )
  SELECT jsonb_build_object(
    'generated_at', now(),
    'by_lane', COALESCE(jsonb_agg(jsonb_build_object(
      'board_scope', i.board_scope, 'domain_key', i.domain_key,
      'total_cards', i.total_cards, 'backlog', i.backlog, 'todo', i.todo,
      'in_progress', i.in_progress, 'review', i.review, 'done', i.done,
      'archived', i.archived, 'orphan_cards', i.orphan_cards, 'overdue_cards', i.overdue_cards
    ) ORDER BY i.board_scope, i.domain_key), '[]'::jsonb)
  )
  FROM items i;
$function$;

CREATE OR REPLACE FUNCTION public.list_curation_pending_board_items()
 RETURNS SETOF json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_member_id, 'write_board') THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;

  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      bi.id, bi.title, bi.description, bi.status,
      bi.curation_status, bi.assignee_id, bi.reviewer_id,
      bi.due_date, bi.curation_due_at, bi.board_id,
      i.legacy_tribe_id AS tribe_id, i.title AS tribe_name,
      am.name AS assignee_name, rm.name AS reviewer_name,
      bi.created_at, bi.updated_at, bi.attachments,
      (SELECT count(*) FROM public.curation_review_log crl WHERE crl.board_item_id = bi.id) AS review_count,
      (SELECT json_agg(json_build_object(
        'id', crl2.id, 'curator_name', cm.name,
        'decision', crl2.decision, 'feedback', crl2.feedback_notes,
        'scores', crl2.criteria_scores, 'completed_at', crl2.completed_at
       ) ORDER BY crl2.completed_at DESC)
       FROM public.curation_review_log crl2
       LEFT JOIN public.members cm ON cm.id = crl2.curator_id
       WHERE crl2.board_item_id = bi.id
      ) AS review_history
    FROM public.board_items bi
    JOIN public.project_boards pb ON pb.id = bi.board_id
    LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
    LEFT JOIN public.members am ON am.id = bi.assignee_id
    LEFT JOIN public.members rm ON rm.id = bi.reviewer_id
    WHERE bi.curation_status = 'curation_pending'
      AND bi.status <> 'archived'
      AND pb.is_active = true
    ORDER BY bi.curation_due_at ASC NULLS LAST, bi.updated_at DESC
  ) r;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_portfolio_timeline()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_tribe_id integer;
  v_chapter text;
  v_is_admin boolean;
  v_result jsonb;
BEGIN
  SELECT id, tribe_id, chapter INTO v_member_id, v_tribe_id, v_chapter
    FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RETURN '[]'::jsonb; END IF;

  v_is_admin := public.can_by_member(v_member_id, 'manage_member');

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', bi.id, 'title', bi.title, 'status', bi.status,
    'tribe_id', i.legacy_tribe_id, 'tribe_name', i.title,
    'baseline_date', bi.baseline_date, 'forecast_date', bi.forecast_date,
    'actual_completion_date', bi.actual_completion_date,
    'is_portfolio_item', true, 'assignee_name', m.name,
    'deviation_days', CASE
      WHEN bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
      THEN bi.forecast_date - bi.baseline_date ELSE 0 END
  ) ORDER BY i.legacy_tribe_id, COALESCE(bi.baseline_date, bi.forecast_date, '2099-12-31'::date)), '[]'::jsonb)
  INTO v_result
  FROM board_items bi
  JOIN project_boards pb ON pb.id = bi.board_id AND pb.is_active = true
  LEFT JOIN initiatives i ON i.id = pb.initiative_id
  LEFT JOIN members m ON m.id = bi.assignee_id
  WHERE bi.status <> 'archived'
    AND bi.is_portfolio_item = true
    AND (pb.initiative_id IS NULL OR EXISTS (
      SELECT 1 FROM tribes tr WHERE tr.id = i.legacy_tribe_id AND tr.is_active = true
    ));

  IF NOT v_is_admin AND v_tribe_id IS NOT NULL THEN
    SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb) INTO v_result
    FROM jsonb_array_elements(v_result) elem
    WHERE (elem->>'tribe_id')::integer = v_tribe_id;
  END IF;

  IF NOT v_is_admin AND public.can_by_member(v_member_id, 'manage_partner') AND v_chapter IS NOT NULL THEN
    SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb) INTO v_result
    FROM jsonb_array_elements(v_result) elem
    WHERE (elem->>'tribe_id')::integer IN (
      SELECT i2.legacy_tribe_id
      FROM project_boards pb2
      JOIN initiatives i2 ON i2.id = pb2.initiative_id
      JOIN tribes t2 ON t2.id = i2.legacy_tribe_id
      WHERE EXISTS (SELECT 1 FROM members m2 WHERE m2.tribe_id = t2.id AND m2.chapter = v_chapter)
    );
  END IF;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_legacy_board_items_for_tribe(p_current_tribe_id integer)
 RETURNS SETOF json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_leader_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_caller_id IS NULL THEN RETURN; END IF;

  SELECT m.id INTO v_leader_id
  FROM public.members m
  WHERE m.tribe_id = p_current_tribe_id
    AND m.operational_role = 'tribe_leader'
    AND m.is_active = true
  LIMIT 1;

  IF v_leader_id IS NULL THEN RETURN; END IF;

  IF NOT (
    v_caller_id = v_leader_id
    OR public.can_by_member(v_caller_id, 'manage_member')
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      bi.id, bi.title, bi.description, bi.status,
      bi.curation_status, bi.reviewer_id,
      bi.tags, bi.labels, bi.due_date, bi.position,
      bi.cycle, bi.attachments, bi.checklist,
      bi.created_at, bi.updated_at,
      am.name AS assignee_name, am.photo_url AS assignee_photo,
      rm.name AS reviewer_name,
      i.legacy_tribe_id AS origin_tribe_id,
      i.title AS origin_tribe_name
    FROM public.board_items bi
    JOIN public.project_boards pb ON pb.id = bi.board_id
    LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
    LEFT JOIN public.members am ON am.id = bi.assignee_id
    LEFT JOIN public.members rm ON rm.id = bi.reviewer_id
    WHERE i.legacy_tribe_id <> p_current_tribe_id
      AND pb.is_active = true
      AND bi.status <> 'archived'
      AND (
        bi.assignee_id = v_leader_id
        OR i.legacy_tribe_id IN (
          SELECT mch.tribe_id
          FROM public.member_cycle_history mch
          WHERE mch.member_id = v_leader_id
            AND mch.operational_role = 'tribe_leader'
            AND mch.tribe_id IS NOT NULL
        )
        OR i.legacy_tribe_id IN (
          SELECT tr.id
          FROM public.member_cycle_history mch2
          JOIN public.tribes tr ON mch2.tribe_name ILIKE '%' || tr.name || '%'
          WHERE mch2.member_id = v_leader_id
            AND mch2.operational_role = 'tribe_leader'
            AND mch2.tribe_id IS NULL
            AND mch2.tribe_name IS NOT NULL
        )
      )
    ORDER BY bi.updated_at DESC NULLS LAST
    LIMIT 200
  ) r;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_portfolio_planned_vs_actual(p_cycle integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;

  SELECT coalesce(jsonb_agg(row_data ORDER BY row_data->>'tribe_name'), '[]'::jsonb) INTO v_result
  FROM (
    SELECT jsonb_build_object(
      'tribe_id', t.id,
      'tribe_name', t.name,
      'chapter', (SELECT chapter FROM members WHERE tribe_id = t.id AND operational_role = 'tribe_leader' LIMIT 1),
      'total_cards', count(bi.id),
      'portfolio_cards', count(bi.id) FILTER (WHERE bi.is_portfolio_item = true),
      'planned', count(bi.id) FILTER (WHERE bi.baseline_date IS NOT NULL AND bi.is_portfolio_item = true),
      'in_progress', count(bi.id) FILTER (WHERE bi.status IN ('in_progress', 'review') AND bi.is_portfolio_item = true),
      'done', count(bi.id) FILTER (WHERE bi.status = 'done' AND bi.is_portfolio_item = true),
      'backlog', count(bi.id) FILTER (WHERE bi.status = 'backlog' AND bi.is_portfolio_item = true),
      'on_time', count(bi.id) FILTER (WHERE bi.is_portfolio_item = true AND bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL AND bi.forecast_date <= bi.baseline_date),
      'at_risk', count(bi.id) FILTER (WHERE bi.is_portfolio_item = true AND bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL AND bi.forecast_date > bi.baseline_date AND bi.forecast_date <= bi.baseline_date + 14),
      'delayed', count(bi.id) FILTER (WHERE bi.is_portfolio_item = true AND bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL AND bi.forecast_date > bi.baseline_date + 14),
      'avg_deviation_days', round(coalesce(avg(
        CASE WHEN bi.is_portfolio_item = true AND bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
        THEN bi.forecast_date - bi.baseline_date END
      ), 0)),
      'spi', CASE
        WHEN count(bi.id) FILTER (WHERE bi.baseline_date IS NOT NULL AND bi.is_portfolio_item = true) = 0 THEN null
        ELSE round(
          count(bi.id) FILTER (WHERE bi.status = 'done' AND bi.is_portfolio_item = true)::numeric /
          NULLIF(count(bi.id) FILTER (WHERE bi.baseline_date IS NOT NULL AND bi.is_portfolio_item = true), 0),
          2
        )
      END,
      'completion_pct', CASE
        WHEN count(bi.id) FILTER (WHERE bi.is_portfolio_item = true) = 0 THEN 0
        ELSE round(
          count(bi.id) FILTER (WHERE bi.status = 'done' AND bi.is_portfolio_item = true)::numeric * 100 /
          NULLIF(count(bi.id) FILTER (WHERE bi.is_portfolio_item = true), 0),
          1
        )
      END
    ) as row_data
    FROM tribes t
    JOIN initiatives i ON i.legacy_tribe_id = t.id
    JOIN project_boards pb ON pb.initiative_id = i.id AND pb.is_active = true
    JOIN board_items bi ON bi.board_id = pb.id AND bi.status != 'archived' AND bi.cycle = p_cycle
    WHERE t.is_active = true
    GROUP BY t.id, t.name
  ) sub;

  IF v_caller.operational_role IN ('sponsor', 'chapter_liaison') AND NOT coalesce(v_caller.is_superadmin, false) THEN
    SELECT coalesce(jsonb_agg(elem), '[]'::jsonb) INTO v_result
    FROM jsonb_array_elements(v_result) elem
    WHERE elem->>'chapter' = v_caller.chapter OR elem->>'chapter' IS NULL;
  END IF;

  IF v_caller.operational_role = 'tribe_leader' AND NOT coalesce(v_caller.is_superadmin, false) THEN
    SELECT coalesce(jsonb_agg(elem), '[]'::jsonb) INTO v_result
    FROM jsonb_array_elements(v_result) elem
    WHERE (elem->>'tribe_id')::integer = v_caller.tribe_id;
  END IF;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_portfolio_dashboard(p_cycle integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
  v_artifacts jsonb;
  v_summary jsonb;
  v_by_tribe jsonb;
  v_by_type jsonb;
  v_by_month jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(sub.*) ORDER BY sub.tribe_id, sub.baseline_date NULLS LAST)
  INTO v_artifacts
  FROM (
    SELECT
      bi.id, bi.title, bi.description, bi.status,
      bi.baseline_date, bi.forecast_date, bi.actual_completion_date,
      CASE
        WHEN bi.baseline_date IS NOT NULL AND bi.forecast_date IS NOT NULL
        THEN (bi.forecast_date - bi.baseline_date) ELSE NULL
      END AS variance_days,
      CASE
        WHEN bi.actual_completion_date IS NOT NULL THEN 'completed'
        WHEN bi.baseline_date IS NULL OR bi.forecast_date IS NULL THEN 'no_baseline'
        WHEN bi.forecast_date < CURRENT_DATE AND bi.actual_completion_date IS NULL THEN 'overdue'
        WHEN bi.forecast_date <= bi.baseline_date THEN 'on_track'
        WHEN (bi.forecast_date - bi.baseline_date) <= 7 THEN 'at_risk'
        ELSE 'delayed'
      END AS health,
      i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name,
      m.name AS leader_name,
      bi.tags AS legacy_tags,
      (SELECT jsonb_agg(jsonb_build_object('name', tg.name, 'label', tg.label_pt, 'color', tg.color))
       FROM board_item_tag_assignments bita JOIN tags tg ON tg.id = bita.tag_id
       WHERE bita.board_item_id = bi.id AND tg.name NOT IN ('entregavel_lider', 'ciclo_3')) AS unified_tags,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id) AS checklist_total,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id AND bic.is_completed = true) AS checklist_done,
      CASE WHEN bi.baseline_date IS NOT NULL THEN 'Q' || EXTRACT(QUARTER FROM bi.baseline_date)::text ELSE 'TBD' END AS quarter,
      CASE WHEN bi.baseline_date IS NOT NULL THEN to_char(bi.baseline_date, 'YYYY-MM') ELSE 'TBD' END AS baseline_month
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    LEFT JOIN initiatives i ON i.id = pb.initiative_id
    LEFT JOIN members m ON m.id = bi.assignee_id
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle AND bi.is_portfolio_item = true
  ) sub;

  SELECT jsonb_build_object(
    'total_artifacts', count(*),
    'completed', count(*) FILTER (WHERE sub.health = 'completed'),
    'on_track', count(*) FILTER (WHERE sub.health = 'on_track'),
    'at_risk', count(*) FILTER (WHERE sub.health = 'at_risk'),
    'delayed', count(*) FILTER (WHERE sub.health = 'delayed'),
    'no_baseline', count(*) FILTER (WHERE sub.health = 'no_baseline'),
    'avg_variance_days', ROUND(AVG(sub.variance_days) FILTER (WHERE sub.variance_days IS NOT NULL), 1),
    'checklist_total', SUM(sub.checklist_total),
    'checklist_done', SUM(sub.checklist_done),
    'pct_with_baseline', ROUND(count(*) FILTER (WHERE sub.baseline_date IS NOT NULL)::numeric / NULLIF(count(*), 0) * 100, 1)
  )
  INTO v_summary
  FROM (
    SELECT bi.baseline_date, bi.forecast_date, bi.actual_completion_date,
      CASE
        WHEN bi.actual_completion_date IS NOT NULL THEN 'completed'
        WHEN bi.baseline_date IS NULL OR bi.forecast_date IS NULL THEN 'no_baseline'
        WHEN bi.forecast_date < CURRENT_DATE AND bi.actual_completion_date IS NULL THEN 'overdue'
        WHEN bi.forecast_date <= bi.baseline_date THEN 'on_track'
        WHEN (bi.forecast_date - bi.baseline_date) <= 7 THEN 'at_risk'
        ELSE 'delayed'
      END AS health,
      (bi.forecast_date - bi.baseline_date) AS variance_days,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id) AS checklist_total,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id AND bic.is_completed = true) AS checklist_done
    FROM board_items bi
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle AND bi.is_portfolio_item = true
  ) sub;

  SELECT jsonb_agg(jsonb_build_object(
    'tribe_id', sub.tribe_id, 'tribe_name', sub.tribe_name,
    'leader', sub.leader_name, 'total', sub.total,
    'completed', sub.completed, 'on_track', sub.on_track,
    'at_risk', sub.at_risk, 'delayed', sub.delayed,
    'no_baseline', sub.no_baseline, 'next_deadline', sub.next_deadline,
    'checklist_pct', sub.checklist_pct
  ) ORDER BY sub.tribe_id)
  INTO v_by_tribe
  FROM (
    SELECT
      i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name,
      m.name AS leader_name,
      count(*) AS total,
      count(*) FILTER (WHERE bi.actual_completion_date IS NOT NULL) AS completed,
      count(*) FILTER (WHERE bi.forecast_date IS NOT NULL AND bi.forecast_date <= bi.baseline_date AND bi.actual_completion_date IS NULL) AS on_track,
      count(*) FILTER (WHERE bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL AND (bi.forecast_date - bi.baseline_date) BETWEEN 1 AND 7 AND bi.actual_completion_date IS NULL) AS at_risk,
      count(*) FILTER (WHERE bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL AND (bi.forecast_date - bi.baseline_date) > 7 AND bi.actual_completion_date IS NULL) AS delayed,
      count(*) FILTER (WHERE bi.baseline_date IS NULL) AS no_baseline,
      MIN(bi.forecast_date) FILTER (WHERE bi.actual_completion_date IS NULL AND bi.forecast_date >= CURRENT_DATE) AS next_deadline,
      CASE WHEN SUM(chk.total) > 0 THEN ROUND(SUM(chk.done)::numeric / SUM(chk.total) * 100, 1) ELSE 0 END AS checklist_pct
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    LEFT JOIN initiatives i ON i.id = pb.initiative_id
    LEFT JOIN members m ON m.id = bi.assignee_id
    LEFT JOIN LATERAL (
      SELECT count(*) AS total, count(*) FILTER (WHERE is_completed) AS done
      FROM board_item_checklists WHERE board_item_id = bi.id
    ) chk ON true
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle AND bi.is_portfolio_item = true
    GROUP BY i.legacy_tribe_id, i.title, m.name
  ) sub;

  SELECT jsonb_agg(jsonb_build_object(
    'type', sub.tag_name, 'label', sub.tag_label, 'color', sub.tag_color, 'count', sub.cnt
  ) ORDER BY sub.cnt DESC)
  INTO v_by_type
  FROM (
    SELECT tg.name AS tag_name, tg.label_pt AS tag_label, tg.color AS tag_color, count(DISTINCT bi.id) AS cnt
    FROM board_items bi
    JOIN board_item_tag_assignments bita ON bita.board_item_id = bi.id
    JOIN tags tg ON tg.id = bita.tag_id
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle
      AND tg.name NOT IN ('entregavel_lider', 'ciclo_3')
      AND tg.tier = 'system' AND bi.is_portfolio_item = true
    GROUP BY tg.name, tg.label_pt, tg.color
  ) sub;

  SELECT jsonb_agg(jsonb_build_object(
    'month', sub.month, 'count', sub.cnt, 'tribes', sub.tribes
  ) ORDER BY sub.month)
  INTO v_by_month
  FROM (
    SELECT
      to_char(bi.baseline_date, 'YYYY-MM') AS month,
      count(*) AS cnt,
      jsonb_agg(DISTINCT i.legacy_tribe_id) AS tribes
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    LEFT JOIN initiatives i ON i.id = pb.initiative_id
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle
      AND bi.baseline_date IS NOT NULL AND bi.is_portfolio_item = true
    GROUP BY to_char(bi.baseline_date, 'YYYY-MM')
  ) sub;

  v_result := jsonb_build_object(
    'cycle', p_cycle,
    'generated_at', now(),
    'summary', COALESCE(v_summary, '{}'::jsonb),
    'artifacts', COALESCE(v_artifacts, '[]'::jsonb),
    'by_tribe', COALESCE(v_by_tribe, '[]'::jsonb),
    'by_type', COALESCE(v_by_type, '[]'::jsonb),
    'by_month', COALESCE(v_by_month, '[]'::jsonb)
  );

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.exec_cycle_report(p_cycle_code text DEFAULT 'cycle3-2026'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record; v_result jsonb; v_kpis jsonb; v_members jsonb; v_tribes jsonb;
  v_production jsonb; v_engagement jsonb; v_curation jsonb; v_cycle jsonb; v_attendance jsonb;
  v_total_members int; v_active_members int;
  v_start date := '2026-01-01';
  v_end date := '2026-06-30';
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager', 'deputy_manager') AND NOT (v_caller.designations && ARRAY['sponsor', 'chapter_liaison']) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT jsonb_build_object(
    'code', COALESCE(c.cycle_code, p_cycle_code),
    'name', COALESCE(c.cycle_label, 'Ciclo 3 — 2026/1'),
    'start_date', c.cycle_start, 'end_date', c.cycle_end
  ) INTO v_cycle FROM public.cycles c WHERE c.cycle_code = p_cycle_code OR c.is_current = true LIMIT 1;
  IF v_cycle IS NULL THEN v_cycle := jsonb_build_object('code', p_cycle_code, 'name', 'Ciclo 3', 'start_date', v_start, 'end_date', v_end); END IF;

  v_kpis := public.get_kpi_dashboard(v_start, v_end);

  SELECT COUNT(*) INTO v_total_members FROM public.members;
  SELECT COUNT(*) INTO v_active_members FROM public.members WHERE current_cycle_active = true;

  SELECT jsonb_build_object(
    'total', v_total_members, 'active', v_active_members,
    'by_chapter', COALESCE((SELECT jsonb_agg(jsonb_build_object('chapter', chapter, 'count', cnt) ORDER BY cnt DESC) FROM (SELECT chapter, count(*) AS cnt FROM public.members WHERE current_cycle_active = true AND chapter IS NOT NULL GROUP BY chapter) sub), '[]'::jsonb),
    'by_role', COALESCE((SELECT jsonb_agg(jsonb_build_object('role', operational_role, 'count', cnt) ORDER BY cnt DESC) FROM (SELECT COALESCE(operational_role, 'none') AS operational_role, count(*) AS cnt FROM public.members WHERE current_cycle_active = true GROUP BY operational_role) sub), '[]'::jsonb),
    'retention_rate', ROUND(COALESCE((SELECT COUNT(*) FILTER (WHERE COALESCE(array_length(cycles, 1), 0) > 1)::numeric * 100 / NULLIF(COUNT(*), 0) FROM public.members WHERE current_cycle_active = true AND cycles IS NOT NULL), 0)),
    'new_this_cycle', (SELECT COUNT(*) FROM public.members WHERE current_cycle_active = true AND (cycles IS NULL OR COALESCE(array_length(cycles, 1), 0) <= 1))
  ) INTO v_members;

  SELECT COALESCE(jsonb_agg(tribe_data ORDER BY tribe_data->>'name'), '[]'::jsonb) INTO v_tribes
  FROM (SELECT jsonb_build_object('id', t.id, 'name', t.name,
    'leader', COALESCE((SELECT m.name FROM public.members m WHERE m.tribe_id = t.id AND m.operational_role = 'tribe_leader' LIMIT 1), '—'),
    'member_count', (SELECT COUNT(*) FROM public.members m WHERE m.tribe_id = t.id AND m.current_cycle_active = true),
    'board_items_total', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived'), 0),
    'board_items_completed', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status = 'done'), 0),
    'completion_pct', COALESCE((SELECT ROUND(COUNT(*) FILTER (WHERE bi.status = 'done')::numeric * 100 / NULLIF(COUNT(*), 0)) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived'), 0),
    'articles_produced', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status IN ('done', 'published') AND (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')), 0)
  ) AS tribe_data FROM public.tribes t WHERE t.is_active = true) sub;

  SELECT jsonb_build_object(
    'articles_submitted', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')), 0),
    'articles_published', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%') AND bi.status IN ('done', 'published')), 0),
    'articles_in_review', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%') AND bi.status IN ('review', 'in_progress')), 0),
    'webinars_completed', (SELECT COUNT(*) FROM public.events WHERE type = 'webinar' AND date <= now()),
    'webinars_planned', (SELECT COUNT(*) FROM public.events WHERE type = 'webinar' AND date > now())
  ) INTO v_production;

  SELECT jsonb_build_object(
    'total_events', (SELECT COUNT(*) FROM public.events WHERE date BETWEEN v_start AND v_end),
    'total_attendance_hours', COALESCE((SELECT round(sum(COALESCE(e.duration_actual, e.duration_minutes, 60)::numeric * (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present)) / 60) FROM events e WHERE e.date BETWEEN v_start AND v_end), 0),
    'avg_attendance_per_event', COALESCE((SELECT ROUND(AVG(ac)) FROM (SELECT COUNT(*) AS ac FROM public.attendance a JOIN events e ON e.id = a.event_id WHERE a.present = true AND e.date BETWEEN v_start AND v_end GROUP BY a.event_id) sub), 0),
    'total_attendance_records', (SELECT COUNT(*) FROM public.attendance WHERE present = true),
    'certification_completion_rate', ROUND(COALESCE((SELECT COUNT(*) FILTER (WHERE cpmai_certified = true)::numeric * 100 / NULLIF(COUNT(*), 0) FROM public.members WHERE current_cycle_active = true), 0))
  ) INTO v_engagement;

  SELECT jsonb_build_object(
    'items_submitted', COALESCE((SELECT COUNT(*) FROM public.curation_review_log), 0),
    'items_approved', COALESCE((SELECT COUNT(*) FROM public.curation_review_log WHERE decision = 'approved'), 0),
    'items_in_review', COALESCE((SELECT COUNT(*) FROM public.board_items WHERE status = 'review'), 0),
    'avg_review_days', COALESCE((SELECT ROUND(AVG(EXTRACT(EPOCH FROM (completed_at - created_at)) / 86400)::numeric, 1) FROM public.curation_review_log), 0),
    'sla_compliance_rate', COALESCE((SELECT ROUND(COUNT(*) FILTER (WHERE completed_at <= due_date)::numeric * 100 / NULLIF(COUNT(*) FILTER (WHERE due_date IS NOT NULL), 0)) FROM public.curation_review_log), 0)
  ) INTO v_curation;

  SELECT COALESCE(jsonb_agg(att_row ORDER BY att_row->>'tribe_name'), '[]'::jsonb) INTO v_attendance
  FROM (SELECT jsonb_build_object('tribe_id', t.id, 'tribe_name', t.name,
    'members_count', (SELECT count(*) FROM members m WHERE m.tribe_id = t.id AND m.is_active AND m.operational_role NOT IN ('sponsor','chapter_liaison','guest','none')),
    'avg_geral_pct', COALESCE((SELECT round(avg(sub.geral_pct), 1) FROM get_attendance_summary(v_start, v_end, t.id) sub), 0),
    'avg_tribe_pct', COALESCE((SELECT round(avg(sub.tribe_pct), 1) FROM get_attendance_summary(v_start, v_end, t.id) sub), 0),
    'avg_combined_pct', COALESCE((SELECT round(avg(sub.combined_pct), 1) FROM get_attendance_summary(v_start, v_end, t.id) sub), 0),
    'at_risk_count', COALESCE((SELECT count(*) FROM get_attendance_summary(v_start, v_end, t.id) sub WHERE sub.combined_pct < 50 AND sub.combined_pct > 0), 0)
  ) AS att_row FROM tribes t WHERE t.is_active = true) sub;

  v_result := jsonb_build_object('cycle', v_cycle, 'kpis', v_kpis, 'members', v_members, 'tribes', v_tribes, 'production', v_production, 'engagement', v_engagement, 'curation', v_curation, 'attendance', v_attendance);
  RETURN v_result;
END; $function$;

NOTIFY pgrst, 'reload schema';
