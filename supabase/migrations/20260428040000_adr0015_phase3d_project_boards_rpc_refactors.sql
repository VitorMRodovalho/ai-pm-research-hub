-- ADR-0015 Phase 3d — RPC refactors (companion to 20260428030000)
--
-- 10 RPCs refactored to use initiative_id (derive legacy_tribe_id via JOIN initiatives):
--   list_project_boards, admin_archive_project_board, admin_restore_project_board,
--   admin_update_board_columns, upsert_board_item, admin_data_quality_audit,
--   admin_detect_board_taxonomy_drift, admin_run_portfolio_data_sanity,
--   exec_tribe_dashboard, enforce_board_item_source_tribe_integrity
--
-- Applied AFTER 20260428030000 (policy fixes + DROP COLUMN).
-- CREATE OR REPLACE is idempotent; safe to re-run.

-- 1. list_project_boards
CREATE OR REPLACE FUNCTION public.list_project_boards(p_tribe_id integer DEFAULT NULL::integer)
 RETURNS SETOF json
 LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      pb.id, pb.board_name,
      i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name,
      pb.source, pb.columns, pb.is_active,
      pb.board_scope, pb.domain_key, pb.cycle_scope, pb.created_at,
      (SELECT count(*) FROM public.board_items bi WHERE bi.board_id = pb.id) AS item_count
    FROM public.project_boards pb
    LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
    WHERE pb.is_active IS TRUE
      AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
    ORDER BY
      CASE pb.board_scope WHEN 'global' THEN 0 WHEN 'operational' THEN 1 ELSE 2 END,
      pb.created_at DESC
  ) r;
END;
$function$;

-- 2. admin_archive_project_board
CREATE OR REPLACE FUNCTION public.admin_archive_project_board(p_board_id uuid, p_reason text DEFAULT NULL::text, p_archive_items boolean DEFAULT true)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_caller record; v_board record; v_board_tribe_id integer; v_archived_items integer := 0;
begin
  select * into v_caller from public.get_my_member_record();
  select * into v_board from public.project_boards where id = p_board_id;
  if v_board is null then raise exception 'Board not found: %', p_board_id; end if;
  SELECT legacy_tribe_id INTO v_board_tribe_id FROM public.initiatives WHERE id = v_board.initiative_id;
  if v_caller is null or not (
      v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
      or (v_caller.operational_role = 'tribe_leader' and v_caller.tribe_id = v_board_tribe_id)
    ) then raise exception 'Insufficient permissions'; end if;
  update public.project_boards set is_active = false, updated_at = now() where id = p_board_id;
  if p_archive_items then
    update public.board_items set status = 'archived', updated_at = now()
    where board_id = p_board_id and status <> 'archived';
    get diagnostics v_archived_items = row_count;
  end if;
  insert into public.board_lifecycle_events (board_id, action, reason, actor_member_id)
  values (p_board_id, 'board_archived', nullif(trim(coalesce(p_reason, '')), ''), v_caller.id);
  return jsonb_build_object('success', true, 'board_id', p_board_id, 'archived_items', v_archived_items);
end;
$function$;

-- 3. admin_restore_project_board
CREATE OR REPLACE FUNCTION public.admin_restore_project_board(p_board_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_caller record; v_board record; v_board_tribe_id integer;
begin
  select * into v_caller from public.get_my_member_record();
  select * into v_board from public.project_boards where id = p_board_id;
  if v_board is null then raise exception 'Board not found: %', p_board_id; end if;
  SELECT legacy_tribe_id INTO v_board_tribe_id FROM public.initiatives WHERE id = v_board.initiative_id;
  if v_caller is null or not (
      v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
      or (v_caller.operational_role = 'tribe_leader' and v_caller.tribe_id = v_board_tribe_id)
    ) then raise exception 'Insufficient permissions'; end if;
  update public.project_boards set is_active = true, updated_at = now() where id = p_board_id;
  insert into public.board_lifecycle_events (board_id, action, reason, actor_member_id)
  values (p_board_id, 'board_restored', nullif(trim(coalesce(p_reason, '')), ''), v_caller.id);
  return jsonb_build_object('success', true, 'board_id', p_board_id);
end;
$function$;

-- 4. admin_update_board_columns
CREATE OR REPLACE FUNCTION public.admin_update_board_columns(p_board_id uuid, p_columns jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_role text; v_is_admin boolean; v_member_tribe_id int; v_board_tribe_id int;
BEGIN
  SELECT operational_role, is_superadmin, tribe_id INTO v_role, v_is_admin, v_member_tribe_id
  FROM public.members WHERE auth_id = auth.uid();
  IF NOT (v_is_admin OR v_role IN ('manager', 'deputy_manager')) THEN
    IF v_role = 'tribe_leader' THEN
      SELECT i.legacy_tribe_id INTO v_board_tribe_id
      FROM public.project_boards pb JOIN public.initiatives i ON i.id = pb.initiative_id
      WHERE pb.id = p_board_id;
      IF v_board_tribe_id IS NULL OR v_board_tribe_id <> v_member_tribe_id THEN
        RETURN jsonb_build_object('success', false, 'error', 'permission_denied');
      END IF;
    ELSE
      RETURN jsonb_build_object('success', false, 'error', 'permission_denied');
    END IF;
  END IF;
  IF jsonb_array_length(p_columns) < 2 THEN RETURN jsonb_build_object('success', false, 'error', 'minimum_2_columns'); END IF;
  IF jsonb_array_length(p_columns) > 8 THEN RETURN jsonb_build_object('success', false, 'error', 'maximum_8_columns'); END IF;
  UPDATE public.project_boards SET columns = p_columns, updated_at = now() WHERE id = p_board_id;
  RETURN jsonb_build_object('success', true);
END;
$function$;

-- 5. upsert_board_item
CREATE OR REPLACE FUNCTION public.upsert_board_item(p_item_id uuid DEFAULT NULL::uuid, p_board_id uuid DEFAULT NULL::uuid, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_status text DEFAULT 'backlog'::text, p_assignee_id uuid DEFAULT NULL::uuid, p_due_date date DEFAULT NULL::date, p_tags text[] DEFAULT NULL::text[], p_labels jsonb DEFAULT '[]'::jsonb, p_checklist jsonb DEFAULT '[]'::jsonb, p_attachments jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
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
        or coalesce('curator' = any(v_designations), false)
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

-- 6. admin_data_quality_audit
CREATE OR REPLACE FUNCTION public.admin_data_quality_audit()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_caller record; v_result jsonb;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null or not (
      auth.role() = 'service_role' or v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
      or coalesce('chapter_liaison' = any(v_caller.designations), false)
      or coalesce('sponsor' = any(v_caller.designations), false)
    ) then raise exception 'Internal audit access required'; end if;
  with tribe6 as (
    select t.id, t.name, t.is_active,
      (select count(*) from public.project_boards pb
        JOIN public.initiatives i ON i.id = pb.initiative_id
        where i.legacy_tribe_id = t.id)::integer as board_count
    from public.tribes t where t.id = 6 limit 1
  ),
  communication_tribe as (
    select t.id, t.name, t.is_active from public.tribes t
    where lower(trim(t.name)) in ('tribo comunicacao','tribo comunicação','time de comunicacao','time de comunicação','comunicacao','comunicação')
    order by t.updated_at desc nulls last limit 1
  ),
  communication_boards as (
    select
      count(*)::integer as total_communication_boards,
      count(*) filter (where i.legacy_tribe_id = (select id from communication_tribe))::integer as linked_to_communication_tribe
    from public.project_boards pb
    LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
    where coalesce(pb.domain_key, '') = 'communication'
      or lower(coalesce(pb.board_name, '')) like '%comunic%'
      or lower(coalesce(pb.board_name, '')) like '%midias%'
      or exists (select 1 from public.board_items bi
        where bi.board_id = pb.id
          and bi.source_board in ('comunicacao_ciclo3', 'midias_sociais', 'social_media', 'comms_c3'))
  ),
  legacy_summary as (
    select count(*)::integer as legacy_tribes_total,
      count(*) filter (where cycle_code in ('cycle_1', 'cycle_2'))::integer as legacy_cycle_1_2_total,
      count(*) filter (where status = 'inactive')::integer as legacy_inactive_total
    from public.legacy_tribes
  ),
  lineage_summary as (
    select count(*)::integer as lineage_total,
      count(*) filter (where relation_type in ('renumbered_to', 'continues_as', 'legacy_of'))::integer as continuity_links_total
    from public.tribe_lineage
  ),
  link_quality as (
    select count(*)::integer as legacy_board_links_total,
      count(*) filter (where ltbl.relation_type = 'renumbered_continuity')::integer as renumbered_links_total
    from public.legacy_tribe_board_links ltbl
  )
  select jsonb_build_object(
    'generated_at', now(),
    'tribe_6', coalesce((select to_jsonb(t6) from tribe6 t6), '{}'::jsonb),
    'communication_tribe', coalesce((select to_jsonb(ct) from communication_tribe ct), '{}'::jsonb),
    'communication_boards', coalesce((select to_jsonb(cb) from communication_boards cb), '{}'::jsonb),
    'legacy_summary', coalesce((select to_jsonb(ls) from legacy_summary ls), '{}'::jsonb),
    'lineage_summary', coalesce((select to_jsonb(lis) from lineage_summary lis), '{}'::jsonb),
    'legacy_link_summary', coalesce((select to_jsonb(lq) from link_quality lq), '{}'::jsonb),
    'flags', jsonb_build_object(
      'tribe_6_missing', coalesce((select id is null from tribe6), true),
      'tribe_6_without_boards', coalesce((select board_count = 0 from tribe6), true),
      'communication_tribe_missing', coalesce((select id is null from communication_tribe), true),
      'legacy_cycle_1_2_empty', coalesce((select legacy_cycle_1_2_total = 0 from legacy_summary), true),
      'lineage_empty', coalesce((select lineage_total = 0 from lineage_summary), true)
    )
  ) into v_result;
  return v_result;
end;
$function$;

-- 7. admin_detect_board_taxonomy_drift
CREATE OR REPLACE FUNCTION public.admin_detect_board_taxonomy_drift()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_actor uuid; v_member public.members%rowtype; v_new_alerts integer := 0;
begin
  v_actor := auth.uid();
  if v_actor is null then raise exception 'Auth required'; end if;
  select * into v_member from public.members where auth_id = v_actor and is_active = true limit 1;
  if v_member.id is null then raise exception 'Member not found'; end if;
  if not (coalesce(v_member.is_superadmin, false) or v_member.operational_role in ('manager', 'deputy_manager')) then
    raise exception 'Admin project management access required';
  end if;
  insert into public.board_taxonomy_alerts(alert_code, severity, board_id, payload)
  select 'GLOBAL_WITH_TRIBE', 'critical', pb.id,
    jsonb_build_object('board_scope', pb.board_scope, 'tribe_id', i.legacy_tribe_id, 'domain_key', pb.domain_key)
  from public.project_boards pb
  LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
  where pb.board_scope = 'global' and pb.initiative_id is not null
    and not exists (select 1 from public.board_taxonomy_alerts a
      where a.alert_code = 'GLOBAL_WITH_TRIBE' and a.board_id = pb.id and a.resolved_at is null);
  GET DIAGNOSTICS v_new_alerts = ROW_COUNT;
  insert into public.board_taxonomy_alerts(alert_code, severity, board_id, payload)
  select 'SCOPE_DOMAIN_MISMATCH', 'warning', pb.id,
    jsonb_build_object('board_scope', pb.board_scope, 'domain_key', pb.domain_key)
  from public.project_boards pb
  where pb.board_scope = 'tribe'
    and coalesce(pb.domain_key, '') not in ('', 'research_delivery', 'tribe_general')
    and not exists (select 1 from public.board_taxonomy_alerts a
      where a.alert_code = 'SCOPE_DOMAIN_MISMATCH' and a.board_id = pb.id and a.resolved_at is null);
  return jsonb_build_object(
    'success', true, 'new_alerts_inserted', v_new_alerts,
    'open_alerts', (select count(*) from public.board_taxonomy_alerts where resolved_at is null)
  );
end;
$function$;

-- 8. admin_run_portfolio_data_sanity
CREATE OR REPLACE FUNCTION public.admin_run_portfolio_data_sanity()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_actor uuid; v_member public.members%rowtype; v_summary jsonb;
begin
  v_actor := auth.uid();
  if v_actor is null then raise exception 'Auth required'; end if;
  select * into v_member from public.members where auth_id = v_actor and is_active = true limit 1;
  if v_member.id is null then raise exception 'Member not found'; end if;
  if not (coalesce(v_member.is_superadmin, false) or v_member.operational_role in ('manager', 'deputy_manager')) then
    raise exception 'Admin project management access required';
  end if;
  v_summary := jsonb_build_object(
    'orphan_items', (select count(*) from public.board_items bi
      left join public.project_boards pb on pb.id = bi.board_id
      where pb.id is null),
    'items_in_inactive_board', (select count(*) from public.board_items bi
      join public.project_boards pb on pb.id = bi.board_id
      where pb.is_active = false and bi.status <> 'archived'),
    'global_with_tribe_id', (select count(*) from public.project_boards
      where board_scope = 'global' and initiative_id is not null),
    'tribe_without_tribe_id', (select count(*) from public.project_boards
      where board_scope = 'tribe' and initiative_id is null)
  );
  insert into public.portfolio_data_sanity_runs(run_by, summary)
  values (v_member.id, v_summary);
  return jsonb_build_object('success', true, 'summary', v_summary);
end;
$function$;

-- 9. exec_tribe_dashboard
CREATE OR REPLACE FUNCTION public.exec_tribe_dashboard(p_tribe_id integer, p_cycle text DEFAULT NULL::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record; v_tribe record; v_leader record; v_cycle_start date; v_result jsonb;
  v_members_total int; v_members_active int; v_members_by_role jsonb; v_members_by_chapter jsonb; v_members_list jsonb;
  v_board record; v_prod_total int := 0; v_prod_by_status jsonb := '{}'::jsonb;
  v_articles_submitted int := 0; v_articles_approved int := 0; v_articles_published int := 0;
  v_curation_pending int := 0; v_avg_days_to_approval numeric := 0;
  v_attendance_rate numeric := 0; v_total_meetings int := 0; v_total_hours numeric := 0;
  v_avg_attendance numeric := 0; v_members_with_streak int := 0; v_members_inactive_30d int := 0;
  v_last_meeting_date date; v_next_meeting jsonb := '{}'::jsonb;
  v_tribe_total_xp int := 0; v_tribe_avg_xp numeric := 0;
  v_top_contributors jsonb := '[]'::jsonb; v_cpmai_certified int := 0;
  v_attendance_by_month jsonb := '[]'::jsonb; v_production_by_month jsonb := '[]'::jsonb;
  v_meeting_slots jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;
  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe IS NULL THEN RAISE EXCEPTION 'Tribe not found'; END IF;
  IF v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
    AND NOT (v_caller.operational_role = 'tribe_leader' AND v_caller.tribe_id = p_tribe_id)
    AND NOT (v_caller.tribe_id = p_tribe_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.members m2
      WHERE m2.id = v_caller.id
        AND ('sponsor' = ANY(m2.designations) OR 'chapter_liaison' = ANY(m2.designations))
        AND m2.chapter IN (SELECT chapter FROM public.members WHERE tribe_id = p_tribe_id AND chapter IS NOT NULL LIMIT 1)
    )
  THEN RAISE EXCEPTION 'Unauthorized: insufficient permissions for tribe %', p_tribe_id; END IF;
  v_cycle_start := COALESCE(
    (SELECT MIN(date) FROM public.events WHERE title ILIKE '%kick%off%' AND date >= '2026-01-01'),
    '2026-03-05'::date
  );
  SELECT id, name, photo_url INTO v_leader FROM public.members WHERE id = v_tribe.leader_member_id;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('day_of_week', tms.day_of_week, 'time_start', tms.time_start, 'time_end', tms.time_end)), '[]'::jsonb)
  INTO v_meeting_slots
  FROM public.tribe_meeting_slots tms WHERE tms.tribe_id = p_tribe_id AND tms.is_active = true;
  SELECT COUNT(*) INTO v_members_total FROM public.members WHERE tribe_id = p_tribe_id AND is_active = true;
  SELECT COUNT(*) INTO v_members_active FROM public.members WHERE tribe_id = p_tribe_id AND is_active = true AND current_cycle_active = true;
  SELECT COALESCE(jsonb_object_agg(role, cnt), '{}'::jsonb) INTO v_members_by_role
  FROM (SELECT operational_role AS role, COUNT(*) AS cnt FROM public.members
    WHERE tribe_id = p_tribe_id AND is_active = true GROUP BY operational_role) sub;
  SELECT COALESCE(jsonb_object_agg(ch, cnt), '{}'::jsonb) INTO v_members_by_chapter
  FROM (SELECT COALESCE(chapter, 'N/A') AS ch, COUNT(*) AS cnt FROM public.members
    WHERE tribe_id = p_tribe_id AND is_active = true GROUP BY chapter) sub;
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', m.id, 'name', m.name, 'chapter', m.chapter, 'operational_role', m.operational_role,
      'xp_total', COALESCE((SELECT SUM(points) FROM public.gamification_points WHERE member_id = m.id), 0),
      'attendance_rate', COALESCE(
        (SELECT ROUND(COUNT(*) FILTER (WHERE a.present = true)::numeric / NULLIF(COUNT(*), 0), 2)
         FROM public.attendance a JOIN public.events e ON e.id = a.event_id
         WHERE a.member_id = m.id AND e.tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE), 0),
      'cpmai_certified', COALESCE(m.cpmai_certified, false),
      'last_activity_at', GREATEST(m.updated_at, (SELECT MAX(a2.created_at) FROM public.attendance a2 WHERE a2.member_id = m.id))
    ) ORDER BY COALESCE((SELECT SUM(points) FROM public.gamification_points WHERE member_id = m.id), 0) DESC
  ), '[]'::jsonb) INTO v_members_list
  FROM public.members m WHERE m.tribe_id = p_tribe_id AND m.is_active = true;
  SELECT pb.* INTO v_board
  FROM public.project_boards pb
  JOIN public.initiatives i ON i.id = pb.initiative_id
  WHERE i.legacy_tribe_id = p_tribe_id AND pb.domain_key = 'research_delivery' AND pb.is_active = true
  LIMIT 1;
  IF v_board.id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_prod_total FROM public.board_items WHERE board_id = v_board.id;
    SELECT COALESCE(jsonb_object_agg(status, cnt), '{}'::jsonb) INTO v_prod_by_status
    FROM (SELECT status, COUNT(*) AS cnt FROM public.board_items WHERE board_id = v_board.id GROUP BY status) sub;
    SELECT COUNT(*) FILTER (WHERE curation_status IN ('submitted', 'under_review', 'approved', 'published')) INTO v_articles_submitted
    FROM public.board_items WHERE board_id = v_board.id;
    SELECT COUNT(*) FILTER (WHERE curation_status = 'approved') INTO v_articles_approved FROM public.board_items WHERE board_id = v_board.id;
    SELECT COUNT(*) FILTER (WHERE curation_status = 'published') INTO v_articles_published FROM public.board_items WHERE board_id = v_board.id;
    SELECT COUNT(*) FILTER (WHERE curation_status IN ('submitted', 'under_review')) INTO v_curation_pending FROM public.board_items WHERE board_id = v_board.id;
  END IF;
  SELECT COUNT(DISTINCT e.id), COALESCE(SUM(COALESCE(e.duration_actual, e.duration_minutes, 60)) / 60.0, 0)
  INTO v_total_meetings, v_total_hours
  FROM public.events e WHERE e.tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE;
  IF v_total_meetings > 0 AND v_members_active > 0 THEN
    SELECT ROUND(COUNT(*) FILTER (WHERE a.present = true)::numeric / NULLIF(v_members_active * v_total_meetings, 0), 2)
    INTO v_attendance_rate
    FROM public.attendance a JOIN public.events e ON e.id = a.event_id
    WHERE e.tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE;
    SELECT ROUND(COUNT(*) FILTER (WHERE a.present = true)::numeric / NULLIF(v_total_meetings, 0), 1)
    INTO v_avg_attendance
    FROM public.attendance a JOIN public.events e ON e.id = a.event_id
    WHERE e.tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE;
  END IF;
  SELECT MAX(e.date) INTO v_last_meeting_date FROM public.events e WHERE e.tribe_id = p_tribe_id AND e.date <= CURRENT_DATE;
  SELECT COUNT(*) INTO v_members_inactive_30d
  FROM public.members m WHERE m.tribe_id = p_tribe_id AND m.is_active = true
    AND NOT EXISTS (SELECT 1 FROM public.attendance a JOIN public.events e ON e.id = a.event_id
      WHERE a.member_id = m.id AND a.present = true AND e.date >= (CURRENT_DATE - INTERVAL '30 days'));
  SELECT jsonb_build_object('day_of_week', tms.day_of_week, 'time_start', tms.time_start) INTO v_next_meeting
  FROM public.tribe_meeting_slots tms WHERE tms.tribe_id = p_tribe_id AND tms.is_active = true LIMIT 1;
  SELECT COALESCE(SUM(gp.points), 0) INTO v_tribe_total_xp
  FROM public.gamification_points gp WHERE gp.member_id IN (SELECT id FROM public.members WHERE tribe_id = p_tribe_id AND is_active = true);
  v_tribe_avg_xp := CASE WHEN v_members_active > 0 THEN ROUND(v_tribe_total_xp::numeric / v_members_active, 1) ELSE 0 END;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', sub.name, 'xp', sub.xp, 'rank', sub.rn)), '[]'::jsonb) INTO v_top_contributors
  FROM (SELECT m.name, SUM(gp.points) AS xp, ROW_NUMBER() OVER (ORDER BY SUM(gp.points) DESC) AS rn
    FROM public.gamification_points gp JOIN public.members m ON m.id = gp.member_id
    WHERE m.tribe_id = p_tribe_id AND m.is_active = true GROUP BY m.id, m.name
    ORDER BY xp DESC LIMIT 5) sub;
  SELECT COUNT(*) INTO v_cpmai_certified FROM public.members
  WHERE tribe_id = p_tribe_id AND is_active = true AND cpmai_certified = true;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('month', sub.month, 'rate', sub.rate) ORDER BY sub.month), '[]'::jsonb) INTO v_attendance_by_month
  FROM (SELECT TO_CHAR(e.date, 'YYYY-MM') AS month,
      ROUND(COUNT(*) FILTER (WHERE a.present = true)::numeric / NULLIF(COUNT(*), 0), 2) AS rate
    FROM public.attendance a JOIN public.events e ON e.id = a.event_id
    WHERE e.tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE
    GROUP BY TO_CHAR(e.date, 'YYYY-MM')) sub;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('month', sub.month, 'cards_created', sub.created, 'cards_completed', sub.completed) ORDER BY sub.month), '[]'::jsonb) INTO v_production_by_month
  FROM (SELECT TO_CHAR(bi.created_at, 'YYYY-MM') AS month, COUNT(*) AS created,
      COUNT(*) FILTER (WHERE bi.status = 'done') AS completed
    FROM public.board_items bi WHERE bi.board_id = v_board.id AND bi.created_at >= v_cycle_start
    GROUP BY TO_CHAR(bi.created_at, 'YYYY-MM')) sub;
  v_result := jsonb_build_object(
    'tribe', jsonb_build_object('id', v_tribe.id, 'name', v_tribe.name,
      'quadrant', v_tribe.quadrant, 'quadrant_name', v_tribe.quadrant_name,
      'leader', CASE WHEN v_leader.id IS NOT NULL THEN jsonb_build_object('id', v_leader.id, 'name', v_leader.name, 'avatar_url', v_leader.photo_url) ELSE NULL END,
      'meeting_slots', v_meeting_slots, 'whatsapp_url', v_tribe.whatsapp_url, 'drive_url', v_tribe.drive_url),
    'members', jsonb_build_object('total', v_members_total, 'active', v_members_active,
      'by_role', v_members_by_role, 'by_chapter', v_members_by_chapter, 'list', v_members_list),
    'production', jsonb_build_object('total_cards', v_prod_total, 'by_status', v_prod_by_status,
      'articles_submitted', v_articles_submitted, 'articles_approved', v_articles_approved,
      'articles_published', v_articles_published, 'curation_pending', v_curation_pending,
      'avg_days_to_approval', v_avg_days_to_approval),
    'engagement', jsonb_build_object('attendance_rate', v_attendance_rate, 'total_meetings', v_total_meetings,
      'total_hours', ROUND(v_total_hours, 1), 'avg_attendance_per_meeting', v_avg_attendance,
      'members_inactive_30d', v_members_inactive_30d, 'last_meeting_date', v_last_meeting_date, 'next_meeting', v_next_meeting),
    'gamification', jsonb_build_object('tribe_total_xp', v_tribe_total_xp, 'tribe_avg_xp', v_tribe_avg_xp,
      'top_contributors', v_top_contributors,
      'certification_progress', jsonb_build_object('cpmai_certified', v_cpmai_certified)),
    'trends', jsonb_build_object('attendance_by_month', v_attendance_by_month, 'production_by_month', v_production_by_month)
  );
  RETURN v_result;
END;
$function$;

-- 10. enforce_board_item_source_tribe_integrity
CREATE OR REPLACE FUNCTION public.enforce_board_item_source_tribe_integrity()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
declare v_expected_tribe integer; v_board_tribe integer; v_board_scope text;
begin
  if new.source_board is null or trim(new.source_board) = '' then return new; end if;
  new.source_board := lower(trim(new.source_board));
  SELECT i.legacy_tribe_id, pb.board_scope INTO v_board_tribe, v_board_scope
  FROM public.project_boards pb
  LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
  WHERE pb.id = new.board_id;
  if coalesce(v_board_scope, 'tribe') = 'global' then return new; end if;
  if v_board_tribe is null then
    raise exception 'Board % must have initiative (tribe-mapped) before linking source_board %', new.board_id, new.source_board;
  end if;
  select m.tribe_id into v_expected_tribe from public.board_source_tribe_map m
  where m.source_board = new.source_board and m.is_active is true limit 1;
  if v_expected_tribe is not null and v_expected_tribe is distinct from v_board_tribe then
    raise exception 'Source board % expects tribe %, but board % is linked to tribe %',
      new.source_board, v_expected_tribe, new.board_id, v_board_tribe;
  end if;
  return new;
end;
$function$;

NOTIFY pgrst, 'reload schema';
