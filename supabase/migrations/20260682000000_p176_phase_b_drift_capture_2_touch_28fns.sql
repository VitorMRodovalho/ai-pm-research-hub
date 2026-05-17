-- Phase B drift capture — 2-touch bucket (28 fns)
-- Session: p176 (2026-05-17)
-- Strategy: Idempotent capture. Live body IS the canonical reference; this migration
--           writes the live body into a migration file so the Phase C body-hash audit
--           contract test (tests/contracts/rpc-migration-coverage.test.mjs) accepts it.
-- Apply via: supabase migration repair --status applied 20260682000000 (no apply_migration
--            needed since live IS canonical; running CREATE OR REPLACE on identical body
--            is a no-op).
-- Allowlist impact: 185 → 157 (28 fns removed from baseline).
-- Per p175 sediment: this is the recommended cadence — bucket-by-bucket ratchet DOWN.
-- Captured via pg_get_functiondef + canonical dollar-quote normalization
--   (AS $function$ → AS $$, except when the body itself contains $$).

-- ============================================================
-- 2-touch bucket (28 functions)
-- ============================================================

CREATE OR REPLACE FUNCTION public._auto_audience_rule_on_meeting_tag()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_tag_name text;
  v_legacy_tribe_id int;
BEGIN
  SELECT name INTO v_tag_name FROM public.tags WHERE id = NEW.tag_id;

  IF v_tag_name NOT IN ('general_meeting', 'tribe_meeting', 'leadership_meeting') THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.event_audience_rules
    WHERE event_id = NEW.event_id AND attendance_type = 'mandatory'
  ) THEN
    RETURN NEW;
  END IF;

  IF v_tag_name = 'general_meeting' THEN
    INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type, target_value)
    VALUES (NEW.event_id, 'mandatory', 'all_active_operational', NULL);

  ELSIF v_tag_name = 'tribe_meeting' THEN
    SELECT i.legacy_tribe_id INTO v_legacy_tribe_id
    FROM public.events e
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.id = NEW.event_id;

    IF v_legacy_tribe_id IS NOT NULL THEN
      INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type, target_value)
      VALUES (NEW.event_id, 'mandatory', 'tribe', v_legacy_tribe_id::text);
    END IF;

  ELSIF v_tag_name = 'leadership_meeting' THEN
    INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type, target_value)
    VALUES
      (NEW.event_id, 'mandatory', 'role', 'manager'),
      (NEW.event_id, 'mandatory', 'role', 'deputy_manager'),
      (NEW.event_id, 'mandatory', 'role', 'tribe_leader');
  END IF;

  RETURN NEW;
END;
$$


CREATE OR REPLACE FUNCTION public.add_checklist_item(p_board_item_id uuid, p_text text, p_position smallint DEFAULT NULL::smallint, p_assigned_to uuid DEFAULT NULL::uuid, p_target_date date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record;
  v_card record;
  v_board record;
  v_authorized boolean;
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

  SELECT * INTO v_board FROM project_boards WHERE id = v_card.board_id;

  v_authorized := public.can_by_member(v_caller.id, 'write_board')
    OR v_card.assignee_id = v_caller.id
    OR EXISTS (
      SELECT 1 FROM board_members bm
      WHERE bm.board_id = v_board.id AND bm.member_id = v_caller.id
      AND bm.board_role IN ('admin', 'editor')
    )
    -- Item 03 fix: comms team in communication domain
    OR (coalesce(v_board.domain_key, '') = 'communication' AND (
      v_caller.operational_role = 'communicator'
      OR coalesce('comms_team' = ANY(v_caller.designations), false)
      OR coalesce('comms_leader' = ANY(v_caller.designations), false)
      OR coalesce('comms_member' = ANY(v_caller.designations), false)
    ));

  IF NOT v_authorized THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission, card ownership, board editor role, or comms team in communication board';
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
$$


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
$$


CREATE OR REPLACE FUNCTION public.admin_detect_board_taxonomy_drift()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  v_caller_id uuid;
  v_new_alerts integer := 0;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  INSERT INTO public.board_taxonomy_alerts(alert_code, severity, board_id, payload)
  SELECT 'GLOBAL_WITH_TRIBE', 'critical', pb.id,
    jsonb_build_object('board_scope', pb.board_scope, 'tribe_id', i.legacy_tribe_id, 'domain_key', pb.domain_key)
  FROM public.project_boards pb
  LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
  WHERE pb.board_scope = 'global' AND pb.initiative_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.board_taxonomy_alerts a
      WHERE a.alert_code = 'GLOBAL_WITH_TRIBE' AND a.board_id = pb.id AND a.resolved_at IS NULL);
  GET DIAGNOSTICS v_new_alerts = ROW_COUNT;

  INSERT INTO public.board_taxonomy_alerts(alert_code, severity, board_id, payload)
  SELECT 'SCOPE_DOMAIN_MISMATCH', 'warning', pb.id,
    jsonb_build_object('board_scope', pb.board_scope, 'domain_key', pb.domain_key)
  FROM public.project_boards pb
  WHERE pb.board_scope = 'tribe'
    AND coalesce(pb.domain_key, '') NOT IN ('', 'research_delivery', 'tribe_general')
    AND NOT EXISTS (SELECT 1 FROM public.board_taxonomy_alerts a
      WHERE a.alert_code = 'SCOPE_DOMAIN_MISMATCH' AND a.board_id = pb.id AND a.resolved_at IS NULL);

  RETURN jsonb_build_object(
    'success', true, 'new_alerts_inserted', v_new_alerts,
    'open_alerts', (SELECT count(*) FROM public.board_taxonomy_alerts WHERE resolved_at IS NULL)
  );
END;
$$


CREATE OR REPLACE FUNCTION public.admin_link_communication_boards(p_tribe_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
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

  -- Resolve initiative_id for the target tribe
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
$$


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
$$


CREATE OR REPLACE FUNCTION public.admin_run_portfolio_data_sanity()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  v_caller_id uuid;
  v_summary jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  v_summary := jsonb_build_object(
    'orphan_items', (SELECT count(*) FROM public.board_items bi
      LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
      WHERE pb.id IS NULL),
    'items_in_inactive_board', (SELECT count(*) FROM public.board_items bi
      JOIN public.project_boards pb ON pb.id = bi.board_id
      WHERE pb.is_active = false AND bi.status <> 'archived'),
    'global_with_tribe_id', (SELECT count(*) FROM public.project_boards
      WHERE board_scope = 'global' AND initiative_id IS NOT NULL),
    'tribe_without_tribe_id', (SELECT count(*) FROM public.project_boards
      WHERE board_scope = 'tribe' AND initiative_id IS NULL)
  );

  INSERT INTO public.portfolio_data_sanity_runs(run_by, summary)
  VALUES (v_caller_id, v_summary);

  RETURN jsonb_build_object('success', true, 'summary', v_summary);
END;
$$


CREATE OR REPLACE FUNCTION public.can_read_internal_analytics()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN false;
  END IF;

  RETURN public.can_by_member(v_caller_id, 'view_internal_analytics');
END;
$$


CREATE OR REPLACE FUNCTION public.check_code_schema_drift()
 RETURNS TABLE(object_type text, object_name text, schema_name text, pattern_matched text, suspect_reference text, reason text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  v_caller_member_id uuid;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();

  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_member_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Not authorized: requires view_internal_analytics';
  END IF;

  RETURN QUERY
  WITH
  -- Column-level drops
  known_dropped_cols_candidates AS (
    SELECT * FROM (VALUES
      ('members', 'tribe_id', 'ADR-0015 Phase 3d (2026-04-15)'),
      ('events', 'tribe_id', 'ADR-0015 Phase 3d (2026-04-15)'),
      ('project_boards', 'tribe_id', 'ADR-0015 Phase 3d (2026-04-15)')
    ) AS k(tbl, col, phase)
  ),
  known_dropped_cols AS (
    SELECT k.tbl, k.col, k.phase
    FROM known_dropped_cols_candidates k
    WHERE NOT EXISTS (
      SELECT 1 FROM information_schema.columns c
      WHERE c.table_schema = 'public' AND c.table_name = k.tbl AND c.column_name = k.col
    )
  ),
  -- Table-level drops/non-existent (Item 2 fix v4)
  known_dropped_tables_candidates AS (
    SELECT * FROM (VALUES
      ('cpmai_sessions', 'never existed (Item 2 fix 2026-04-28)'),
      ('member_status_transitions', 'never existed (Item 2 fix 2026-04-28)'),
      ('member_role_changes', 'never existed (handoff suggestion outdated)')
    ) AS k(tbl, phase)
  ),
  known_dropped_tables AS (
    SELECT k.tbl, k.phase
    FROM known_dropped_tables_candidates k
    WHERE NOT EXISTS (
      SELECT 1 FROM information_schema.tables t
      WHERE t.table_schema = 'public' AND t.table_name = k.tbl
    )
  ),
  pg_proc_clean AS (
    SELECT
      p.proname,
      n.nspname,
      regexp_replace(
        regexp_replace(p.prosrc, '--[^\r\n]*', '', 'g'),
        '/\*[^*]*\*+([^/*][^*]*\*+)*/', '', 'g'
      ) AS clean_src
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname != 'check_code_schema_drift'
  ),
  -- Column refs in pg_proc
  pg_proc_col_hits AS (
    SELECT
      'pg_proc'::text AS object_type,
      pc.proname::text AS object_name,
      pc.nspname::text AS schema_name,
      format('%s.%s ref', k.tbl, k.col) AS pattern_matched,
      k.col AS suspect_reference,
      format('Function still references %I.%I (dropped in %s)', k.tbl, k.col, k.phase) AS reason
    FROM pg_proc_clean pc
    CROSS JOIN known_dropped_cols k
    WHERE pc.clean_src ~ ('\m' || k.tbl || '\.' || k.col || '\M')
  ),
  -- Table refs in pg_proc (Item 2 v4 extension)
  pg_proc_table_hits AS (
    SELECT
      'pg_proc'::text AS object_type,
      pc.proname::text AS object_name,
      pc.nspname::text AS schema_name,
      format('public.%s table ref', k.tbl) AS pattern_matched,
      k.tbl AS suspect_reference,
      format('Function still references public.%I (table %s)', k.tbl, k.phase) AS reason
    FROM pg_proc_clean pc
    CROSS JOIN known_dropped_tables k
    WHERE pc.clean_src ~ ('\m(public\.)?' || k.tbl || '\M')
  ),
  pg_view_col_hits AS (
    SELECT
      'pg_view'::text AS object_type,
      v.viewname::text AS object_name,
      v.schemaname::text AS schema_name,
      format('%s.%s ref', k.tbl, k.col) AS pattern_matched,
      k.col AS suspect_reference,
      format('View definition still references %I.%I (dropped in %s)', k.tbl, k.col, k.phase) AS reason
    FROM pg_views v
    CROSS JOIN known_dropped_cols k
    WHERE v.schemaname = 'public'
      AND regexp_replace(
            regexp_replace(v.definition, '--[^\r\n]*', '', 'g'),
            '/\*[^*]*\*+([^/*][^*]*\*+)*/', '', 'g'
          ) ~ ('\m' || k.tbl || '\.' || k.col || '\M')
  ),
  pg_view_table_hits AS (
    SELECT
      'pg_view'::text AS object_type,
      v.viewname::text AS object_name,
      v.schemaname::text AS schema_name,
      format('public.%s table ref', k.tbl) AS pattern_matched,
      k.tbl AS suspect_reference,
      format('View references public.%I (table %s)', k.tbl, k.phase) AS reason
    FROM pg_views v
    CROSS JOIN known_dropped_tables k
    WHERE v.schemaname = 'public'
      AND regexp_replace(
            regexp_replace(v.definition, '--[^\r\n]*', '', 'g'),
            '/\*[^*]*\*+([^/*][^*]*\*+)*/', '', 'g'
          ) ~ ('\m(public\.)?' || k.tbl || '\M')
  ),
  policy_hits AS (
    SELECT
      'pg_policy'::text AS object_type,
      pol.polname::text AS object_name,
      n.nspname::text AS schema_name,
      format('%s.%s ref', k.tbl, k.col) AS pattern_matched,
      k.col AS suspect_reference,
      format('RLS policy on %I.%I still references %I.%I (dropped in %s)', n.nspname, c.relname, k.tbl, k.col, k.phase) AS reason
    FROM pg_policy pol
    JOIN pg_class c ON c.oid = pol.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    CROSS JOIN known_dropped_cols k
    WHERE (
      coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') ~ ('\m' || k.tbl || '\.' || k.col || '\M')
      OR coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '') ~ ('\m' || k.tbl || '\.' || k.col || '\M')
    )
  )
  SELECT * FROM pg_proc_col_hits
  UNION ALL SELECT * FROM pg_proc_table_hits
  UNION ALL SELECT * FROM pg_view_col_hits
  UNION ALL SELECT * FROM pg_view_table_hits
  UNION ALL SELECT * FROM policy_hits
  ORDER BY object_type, object_name;
END;
$$


CREATE OR REPLACE FUNCTION public.create_card_comment(p_board_item_id uuid, p_body text, p_parent_comment_id uuid DEFAULT NULL::uuid, p_mentioned_member_ids uuid[] DEFAULT '{}'::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
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
    OR public.can_by_member(v_caller.id, 'write_board')
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
$$


CREATE OR REPLACE FUNCTION public.create_change_note(p_chain_id uuid, p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_active boolean;
  v_chain record;
  v_comment_id uuid;
BEGIN
  SELECT m.id, m.is_active INTO v_caller_id, v_caller_active
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL OR v_caller_active = false THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  SELECT ac.id, ac.version_id, ac.opened_by INTO v_chain
  FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN
    RETURN jsonb_build_object('error', 'chain_not_found');
  END IF;

  -- V4: opener (submitter) OR org admin via manage_platform
  IF NOT (
    v_chain.opened_by = v_caller_id
    OR public.can_by_member(v_caller_id, 'manage_platform')
  ) THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  IF length(COALESCE(p_body, '')) = 0 THEN
    RETURN jsonb_build_object('error', 'empty_body');
  END IF;

  INSERT INTO public.document_comments (document_version_id, author_id, body, visibility)
  VALUES (v_chain.version_id, v_caller_id, p_body, 'change_notes')
  RETURNING id INTO v_comment_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'change_note_created', 'document_comment', v_comment_id,
    jsonb_build_object('chain_id', p_chain_id, 'version_id', v_chain.version_id));

  RETURN jsonb_build_object('success', true, 'comment_id', v_comment_id);
END;
$$


CREATE OR REPLACE FUNCTION public.create_document_comment(p_version_id uuid, p_clause_anchor text, p_body text, p_visibility text, p_parent_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_member record;
  v_comment_id uuid;
BEGIN
  SELECT m.id, m.name, m.operational_role, m.designations, m.is_active
  INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL OR v_member.is_active = false THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  IF p_visibility NOT IN ('curator_only','submitter_only','change_notes') THEN
    RETURN jsonb_build_object('error','invalid_visibility');
  END IF;

  -- ADR-0041: V4 catalog action `participate_in_governance_review` source-of-truth
  IF NOT public.can_by_member(v_member.id, 'participate_in_governance_review') THEN
    RETURN jsonb_build_object('error','not_authorized');
  END IF;

  IF length(COALESCE(p_body,'')) = 0 THEN
    RETURN jsonb_build_object('error','empty_body');
  END IF;

  INSERT INTO public.document_comments (document_version_id, author_id, clause_anchor, body, parent_id, visibility)
  VALUES (p_version_id, v_member.id, p_clause_anchor, p_body, p_parent_id, p_visibility)
  RETURNING id INTO v_comment_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'document_comment_created', 'document_comment', v_comment_id,
    jsonb_build_object('version_id', p_version_id, 'visibility', p_visibility, 'clause_anchor', p_clause_anchor));

  RETURN jsonb_build_object('success', true, 'comment_id', v_comment_id, 'created_at', now());
END;
$$


CREATE OR REPLACE FUNCTION public.generate_weekly_member_digest_cron()
 RETURNS TABLE(member_id uuid, notified boolean, reason text, batch_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  v_m record;
  v_digest jsonb;
  v_has_content boolean;
  v_consumed_ids jsonb;
  v_batch_id uuid := gen_random_uuid();
  v_consumed_id_array uuid[];
BEGIN
  FOR v_m IN
    SELECT id FROM public.members
    WHERE is_active = true
      AND notify_weekly_digest = true
      AND notify_delivery_mode_pref IN ('weekly_digest', 'custom_per_type')
  LOOP
    v_digest := public.get_weekly_member_digest(v_m.id);
    v_has_content :=
      jsonb_array_length(v_digest->'sections'->'cards'->'this_week_pending') > 0
      OR jsonb_array_length(v_digest->'sections'->'cards'->'next_week_due') > 0
      OR jsonb_array_length(v_digest->'sections'->'cards'->'overdue_7plus') > 0
      OR jsonb_array_length(v_digest->'sections'->'engagements_new') > 0
      OR jsonb_array_length(v_digest->'sections'->'events_upcoming') > 0
      OR jsonb_array_length(v_digest->'sections'->'publications_new') > 0
      OR jsonb_array_length(v_digest->'sections'->'broadcasts') > 0
      OR jsonb_array_length(v_digest->'sections'->'governance_pending') > 0
      OR jsonb_array_length(v_digest->'sections'->'achievements'->'certificates_issued') > 0
      OR (v_digest->'sections'->'achievements'->>'xp_delta')::int > 0;

    IF v_has_content THEN
      v_consumed_ids := v_digest->'consumed_notification_ids';

      -- Insert digest notification with payload as JSON in body (notifications has no metadata col)
      INSERT INTO public.notifications (
        recipient_id, type, title, body, link, source_type, source_id,
        is_read, delivery_mode, digest_batch_id
      ) VALUES (
        v_m.id,
        'weekly_member_digest',
        'Seu resumo semanal — Núcleo IA',
        v_digest::text,
        '/digest/' || v_batch_id::text,
        'digest',
        v_batch_id,
        false,
        'transactional_immediate',
        v_batch_id
      );

      -- Mark consumed notifications as digest_delivered with batch_id
      IF jsonb_array_length(v_consumed_ids) > 0 THEN
        SELECT array_agg((value::text)::uuid) INTO v_consumed_id_array
        FROM jsonb_array_elements_text(v_consumed_ids);

        UPDATE public.notifications
        SET digest_delivered_at = now(),
            digest_batch_id = v_batch_id
        WHERE id = ANY(v_consumed_id_array)
          AND digest_delivered_at IS NULL;
      END IF;

      member_id := v_m.id; notified := true; reason := 'sent'; batch_id := v_batch_id;
    ELSE
      member_id := v_m.id; notified := false; reason := 'no_content_skip'; batch_id := NULL;
    END IF;
    RETURN NEXT;
  END LOOP;
END;
$$


CREATE OR REPLACE FUNCTION public.get_cross_tribe_comparison()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id uuid;
  v_cycle_start date;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  -- ADR-0042: V4 catalog (manage_platform writes; view_chapter_dashboards reads)
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  RETURN (
    SELECT json_agg(row_to_json(r) ORDER BY r.attendance_rate DESC NULLS LAST)
    FROM (
      SELECT
        t.id as tribe_id,
        t.name as tribe_name,
        (SELECT m2.name FROM members m2 WHERE m2.tribe_id = t.id AND m2.operational_role = 'tribe_leader' LIMIT 1) as leader_name,
        (SELECT count(*) FROM members m WHERE m.tribe_id = t.id AND m.is_active AND m.current_cycle_active) as member_count,
        (SELECT round(
          count(*) FILTER (WHERE a.id IS NOT NULL AND a.excused IS NOT TRUE)::numeric /
          NULLIF(count(*) FILTER (WHERE a.id IS NULL OR a.excused IS NOT TRUE), 0) * 100, 0
        )
        FROM events e
        JOIN initiatives ti ON ti.id = e.initiative_id
        CROSS JOIN members m
        LEFT JOIN attendance a ON a.event_id = e.id AND a.member_id = m.id
        WHERE e.date >= v_cycle_start AND e.date < current_date
          AND e.type = 'tribo' AND ti.legacy_tribe_id = t.id
          AND m.tribe_id = t.id AND m.is_active
        ) as attendance_rate,
        (SELECT count(*) FROM board_items bi
         JOIN project_boards pb ON pb.id = bi.board_id
         JOIN initiatives ti ON ti.id = pb.initiative_id
         WHERE ti.legacy_tribe_id = t.id AND bi.status = 'done') as cards_done,
        (SELECT count(*) FROM board_items bi
         JOIN project_boards pb ON pb.id = bi.board_id
         JOIN initiatives ti ON ti.id = pb.initiative_id
         WHERE ti.legacy_tribe_id = t.id AND bi.status = 'in_progress') as cards_in_progress,
        (SELECT count(*) FROM board_items bi
         JOIN project_boards pb ON pb.id = bi.board_id
         JOIN initiatives ti ON ti.id = pb.initiative_id
         WHERE ti.legacy_tribe_id = t.id AND bi.status NOT IN ('archived', 'done')) as cards_total,
        (SELECT round(sum(e.duration_minutes * sub.att_count)::numeric / 60, 1)
         FROM events e
         JOIN initiatives ti ON ti.id = e.initiative_id
         JOIN (SELECT event_id, count(*) as att_count FROM attendance WHERE excused IS NOT TRUE GROUP BY event_id) sub ON sub.event_id = e.id
         WHERE ti.legacy_tribe_id = t.id AND e.date >= v_cycle_start AND e.date <= current_date
        ) as impact_hours,
        (SELECT count(*) FROM events e
         JOIN initiatives ti ON ti.id = e.initiative_id
         WHERE ti.legacy_tribe_id = t.id AND e.date >= v_cycle_start AND e.date <= current_date AND e.type = 'tribo') as events_held,
        (SELECT max(e.date) FROM events e
         JOIN initiatives ti ON ti.id = e.initiative_id
         WHERE ti.legacy_tribe_id = t.id AND e.date <= current_date AND e.type = 'tribo') as last_meeting
      FROM tribes t
      WHERE t.is_active = true
    ) r
  );
END;
$$


CREATE OR REPLACE FUNCTION public.get_selection_pipeline_metrics(p_cycle_id uuid DEFAULT NULL::uuid, p_chapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_funnel jsonb;
  v_by_chapter jsonb;
  v_conversion_rate numeric;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- V4: view_internal_analytics covers admin/GP + sponsor + chapter_liaison
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Unauthorized: admin or sponsor required';
  END IF;

  IF p_cycle_id IS NOT NULL THEN
    v_cycle_id := p_cycle_id;
  ELSE
    SELECT id INTO v_cycle_id FROM public.selection_cycles
    ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'no_cycle_found');
  END IF;

  SELECT jsonb_build_object(
    'total_applications', COUNT(*),
    'screening', COUNT(*) FILTER (WHERE status = 'screening'),
    'objective_eval', COUNT(*) FILTER (WHERE status = 'objective_eval'),
    'passed_cutoff', COUNT(*) FILTER (WHERE status NOT IN ('submitted', 'screening', 'objective_eval', 'objective_cutoff', 'rejected', 'withdrawn', 'cancelled')),
    'interview_pending', COUNT(*) FILTER (WHERE status = 'interview_pending'),
    'interview_scheduled', COUNT(*) FILTER (WHERE status = 'interview_scheduled'),
    'interview_done', COUNT(*) FILTER (WHERE status = 'interview_done'),
    'interview_noshow', COUNT(*) FILTER (WHERE status = 'interview_noshow'),
    'final_eval', COUNT(*) FILTER (WHERE status = 'final_eval'),
    'approved', COUNT(*) FILTER (WHERE status = 'approved'),
    'rejected', COUNT(*) FILTER (WHERE status = 'rejected'),
    'waitlist', COUNT(*) FILTER (WHERE status = 'waitlist'),
    'converted', COUNT(*) FILTER (WHERE status = 'converted'),
    'withdrawn', COUNT(*) FILTER (WHERE status = 'withdrawn')
  ) INTO v_funnel
  FROM public.selection_applications
  WHERE cycle_id = v_cycle_id
    AND (p_chapter IS NULL OR chapter = p_chapter);

  SELECT jsonb_agg(
    jsonb_build_object(
      'chapter', chapter,
      'total', total,
      'approved', approved,
      'rejected', rejected,
      'waitlist', waitlist,
      'converted', converted,
      'avg_score', avg_score
    )
  ) INTO v_by_chapter
  FROM (
    SELECT
      sa.chapter,
      COUNT(*) AS total,
      COUNT(*) FILTER (WHERE sa.status = 'approved') AS approved,
      COUNT(*) FILTER (WHERE sa.status = 'rejected') AS rejected,
      COUNT(*) FILTER (WHERE sa.status = 'waitlist') AS waitlist,
      COUNT(*) FILTER (WHERE sa.status = 'converted') AS converted,
      ROUND(AVG(sa.final_score), 2) AS avg_score
    FROM public.selection_applications sa
    WHERE sa.cycle_id = v_cycle_id
      AND (p_chapter IS NULL OR sa.chapter = p_chapter)
    GROUP BY sa.chapter
    ORDER BY sa.chapter
  ) sub;

  v_conversion_rate := CASE
    WHEN (v_funnel->>'total_applications')::int > 0
    THEN ROUND(((v_funnel->>'approved')::int + (v_funnel->>'converted')::int)::numeric /
         (v_funnel->>'total_applications')::int * 100, 1)
    ELSE 0
  END;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'chapter_filter', p_chapter,
    'funnel', v_funnel,
    'by_chapter', COALESCE(v_by_chapter, '[]'::jsonb),
    'conversion_rate', v_conversion_rate
  );
END;
$$


CREATE OR REPLACE FUNCTION public.get_selection_rankings(p_cycle_code text DEFAULT NULL::text, p_track text DEFAULT 'both'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_researcher jsonb;
  v_leader jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- V4: view_internal_analytics covers admin/GP + sponsor + chapter_liaison + curator (post-seed)
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: admin/GP/curator only');
  END IF;

  IF p_cycle_code IS NOT NULL THEN
    SELECT id INTO v_cycle_id FROM public.selection_cycles WHERE cycle_code = p_cycle_code;
  ELSE
    SELECT id INTO v_cycle_id FROM public.selection_cycles ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No cycle found');
  END IF;

  IF p_track IN ('researcher', 'both') THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'rank', rank_researcher,
      'applicant_name', applicant_name,
      'chapter', chapter,
      'research_score', research_score,
      'status', status,
      'promotion_path', promotion_path
    ) ORDER BY rank_researcher), '[]'::jsonb)
    INTO v_researcher
    FROM public.selection_applications
    WHERE cycle_id = v_cycle_id AND rank_researcher IS NOT NULL;
  END IF;

  IF p_track IN ('leader', 'both') THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'rank', rank_leader,
      'applicant_name', applicant_name,
      'chapter', chapter,
      'research_score', research_score,
      'leader_score', leader_score,
      'status', status,
      'promotion_path', promotion_path
    ) ORDER BY rank_leader), '[]'::jsonb)
    INTO v_leader
    FROM public.selection_applications
    WHERE cycle_id = v_cycle_id AND rank_leader IS NOT NULL;
  END IF;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'track', p_track,
    'researcher_track', COALESCE(v_researcher, '[]'::jsonb),
    'leader_track', COALESCE(v_leader, '[]'::jsonb),
    'formula', jsonb_build_object(
      'research_score', 'objective_pert + interview_pert',
      'leader_score', 'research_score * 0.7 + leader_extra_pert * 0.3',
      'tiebreaker', 'Standard Competition Ranking (ISO 80000-2) + applicant_name ASC'
    )
  );
END;
$$


CREATE OR REPLACE FUNCTION public.get_tribe_member_contacts(p_tribe_id integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_can boolean;
  v_accessed_ids uuid[];
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN '{}'::json; END IF;

  -- V4: org-wide PII access OR tribe-scoped write authority (tribe_leader has write_for_tribe)
  v_can := public.can_by_member(v_caller_id, 'view_pii')
        OR public.rls_can_for_tribe('write'::text, p_tribe_id);
  IF NOT v_can THEN RETURN '{}'::json; END IF;

  SELECT array_agg(m.id) INTO v_accessed_ids
  FROM public.members m
  WHERE m.tribe_id = p_tribe_id AND m.current_cycle_active = true;

  PERFORM public.log_pii_access_batch(
    v_accessed_ids,
    ARRAY['email','phone']::text[],
    'get_tribe_member_contacts',
    'tribe ' || p_tribe_id
  );

  RETURN (
    SELECT coalesce(
      json_object_agg(m.id, json_build_object('email', m.email, 'phone', m.phone)),
      '{}'::json
    )
    FROM public.members m
    WHERE m.tribe_id = p_tribe_id AND m.current_cycle_active = true
  );
END;
$$


CREATE OR REPLACE FUNCTION public.get_vep_divergence_report()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_selection jsonb;
  v_onboarding jsonb;
  v_active jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'application_id', a.id,
    'applicant_name', a.applicant_name,
    'email', a.email,
    'pmi_id', a.pmi_id,
    'cycle_code', c.cycle_code,
    'nucleo_status', a.status,
    'vep_status_raw', a.vep_status_raw,
    'vep_last_seen_at', a.vep_last_seen_at,
    'vep_reconciled_at', a.vep_reconciled_at,
    'suggested_action', 'Comitê: marcar withdrawn/rejected no Núcleo'
  ) ORDER BY a.applicant_name), '[]'::jsonb) INTO v_selection
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE a.vep_status_raw IN ('Withdrawn', 'Declined', 'OfferNotExtended')
    AND a.status IN ('submitted', 'screening', 'objective_eval', 'interview_pending', 'interview_scheduled', 'interview_done', 'final_eval')
    AND c.status = 'open'
    AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'application_id', a.id,
    'applicant_name', a.applicant_name,
    'email', a.email,
    'pmi_id', a.pmi_id,
    'cycle_code', c.cycle_code,
    'nucleo_status', a.status,
    'vep_status_raw', a.vep_status_raw,
    'vep_last_seen_at', a.vep_last_seen_at,
    'vep_reconciled_at', a.vep_reconciled_at,
    'suggested_action', 'Recruiter PMI: marcar Complete/OfferExtended no VEP'
  ) ORDER BY a.applicant_name), '[]'::jsonb) INTO v_onboarding
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE a.status IN ('approved', 'converted')
    AND a.vep_status_raw IN ('Submitted', 'Active')
    AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'member_id', m.id,
    'member_name', m.name,
    'email', m.email,
    'pmi_id', a.pmi_id,
    'is_active', m.is_active,
    'last_engagement_end_date', latest_eng.end_date,
    'latest_application_id', a.id,
    'cycle_code', c.cycle_code,
    'vep_status_raw', a.vep_status_raw,
    'vep_last_seen_at', a.vep_last_seen_at,
    'vep_reconciled_at', a.vep_reconciled_at,
    'suggested_action', 'Recruiter PMI: marcar Complete no VEP (membro offboarded)'
  ) ORDER BY m.name), '[]'::jsonb) INTO v_active
  FROM public.members m
  JOIN LATERAL (
    SELECT sa.* FROM public.selection_applications sa
    WHERE lower(sa.email) = lower(m.email)
      AND sa.vep_status_raw IS NOT NULL
    ORDER BY sa.imported_at DESC NULLS LAST
    LIMIT 1
  ) a ON true
  LEFT JOIN public.selection_cycles c ON c.id = a.cycle_id
  LEFT JOIN LATERAL (
    SELECT end_date FROM public.engagements e
    WHERE e.person_id = m.person_id
      AND e.end_date IS NOT NULL
    ORDER BY e.end_date DESC
    LIMIT 1
  ) latest_eng ON true
  WHERE m.is_active = false
    AND a.vep_status_raw IN ('Submitted', 'Active')
    AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at);

  v_result := jsonb_build_object(
    'selection_divergent', v_selection,
    'onboarding_divergent', v_onboarding,
    'active_members_divergent', v_active,
    'summary', jsonb_build_object(
      'total_divergent', (
        jsonb_array_length(v_selection) +
        jsonb_array_length(v_onboarding) +
        jsonb_array_length(v_active)
      ),
      'selection_count', jsonb_array_length(v_selection),
      'onboarding_count', jsonb_array_length(v_onboarding),
      'active_members_count', jsonb_array_length(v_active),
      'generated_at', now()
    )
  );

  RETURN v_result;
END;
$$


CREATE OR REPLACE FUNCTION public.get_version_diff(p_version_a uuid, p_version_b uuid, p_include_content boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_member_id uuid;
  v_a record;
  v_b record;
  v_payload_a jsonb;
  v_payload_b jsonb;
BEGIN
  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_version_a IS NULL OR p_version_b IS NULL THEN
    RAISE EXCEPTION 'both version ids are required' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT dv.id, dv.document_id, dv.version_number, dv.version_label,
         dv.authored_at, dv.locked_at, dv.content_html, dv.content_markdown,
         dv.content_diff_json, dv.notes, m.name AS authored_by_name
  INTO v_a
  FROM public.document_versions dv
  LEFT JOIN public.members m ON m.id = dv.authored_by
  WHERE dv.id = p_version_a;

  SELECT dv.id, dv.document_id, dv.version_number, dv.version_label,
         dv.authored_at, dv.locked_at, dv.content_html, dv.content_markdown,
         dv.content_diff_json, dv.notes, m.name AS authored_by_name
  INTO v_b
  FROM public.document_versions dv
  LEFT JOIN public.members m ON m.id = dv.authored_by
  WHERE dv.id = p_version_b;

  IF v_a.id IS NULL OR v_b.id IS NULL THEN
    RETURN jsonb_build_object(
      'both_exist', false,
      'version_a_exists', (v_a.id IS NOT NULL),
      'version_b_exists', (v_b.id IS NOT NULL)
    );
  END IF;

  IF v_a.document_id <> v_b.document_id THEN
    RETURN jsonb_build_object(
      'both_exist', true,
      'same_document', false,
      'document_id_a', v_a.document_id,
      'document_id_b', v_b.document_id
    );
  END IF;

  v_payload_a := jsonb_build_object(
    'version_id', v_a.id,
    'version_number', v_a.version_number,
    'version_label', v_a.version_label,
    'authored_by_name', v_a.authored_by_name,
    'authored_at', v_a.authored_at,
    'locked_at', v_a.locked_at,
    'content_html_length', length(v_a.content_html),
    'content_markdown_length', length(v_a.content_markdown),
    'notes', v_a.notes
  );
  IF p_include_content THEN
    v_payload_a := v_payload_a
      || jsonb_build_object('content_html', v_a.content_html)
      || jsonb_build_object('content_markdown', v_a.content_markdown);
  END IF;

  v_payload_b := jsonb_build_object(
    'version_id', v_b.id,
    'version_number', v_b.version_number,
    'version_label', v_b.version_label,
    'authored_by_name', v_b.authored_by_name,
    'authored_at', v_b.authored_at,
    'locked_at', v_b.locked_at,
    'content_html_length', length(v_b.content_html),
    'content_markdown_length', length(v_b.content_markdown),
    'notes', v_b.notes
  );
  IF p_include_content THEN
    v_payload_b := v_payload_b
      || jsonb_build_object('content_html', v_b.content_html)
      || jsonb_build_object('content_markdown', v_b.content_markdown);
  END IF;

  RETURN jsonb_build_object(
    'both_exist', true,
    'same_document', true,
    'document_id', v_a.document_id,
    'include_content', p_include_content,
    'version_a', v_payload_a,
    'version_b', v_payload_b,
    'pre_computed_diff', COALESCE(v_b.content_diff_json, v_a.content_diff_json),
    'newer_version_id', CASE WHEN v_a.version_number > v_b.version_number THEN v_a.id ELSE v_b.id END,
    'older_version_id', CASE WHEN v_a.version_number > v_b.version_number THEN v_b.id ELSE v_a.id END
  );
END;
$$


CREATE OR REPLACE FUNCTION public.is_event_mandatory_for_member(p_event_id uuid, p_member_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_member record; v_rule record; v_is_curator boolean;
BEGIN
  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF v_member IS NULL OR v_member.is_active = false THEN RETURN false; END IF;
  v_is_curator := v_member.designations IS NOT NULL AND v_member.designations @> ARRAY['curator']::text[];
  FOR v_rule IN SELECT * FROM public.event_audience_rules WHERE event_id = p_event_id AND attendance_type = 'mandatory'
  LOOP
    IF v_rule.target_type = 'all_active_operational' THEN
      IF v_is_curator THEN CONTINUE; END IF;
      IF v_member.tribe_id IS NOT NULL OR v_member.operational_role IN ('manager','deputy_manager') THEN RETURN true; END IF;
    ELSIF v_rule.target_type = 'tribe' THEN
      IF v_is_curator THEN CONTINUE; END IF;
      IF v_member.tribe_id IS NOT NULL AND v_member.tribe_id::text = v_rule.target_value THEN RETURN true; END IF;
    ELSIF v_rule.target_type = 'role' THEN
      IF v_member.operational_role = v_rule.target_value THEN RETURN true; END IF;
    ELSIF v_rule.target_type = 'specific_members' THEN
      IF EXISTS (SELECT 1 FROM public.event_invited_members
        WHERE event_id = p_event_id AND member_id = p_member_id AND attendance_type = 'mandatory') THEN RETURN true; END IF;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.event_invited_members
    WHERE event_id = p_event_id AND member_id = p_member_id AND attendance_type = 'mandatory') THEN RETURN true; END IF;
  RETURN false;
END;
$$


CREATE OR REPLACE FUNCTION public.list_card_drive_files(p_board_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  v_caller_id uuid;
  v_files jsonb;
  v_initiative_folders jsonb;
  v_board_folders jsonb;
  v_board_id uuid;
  v_initiative_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT bi.board_id, pb.initiative_id
    INTO v_board_id, v_initiative_id
  FROM public.board_items bi
  JOIN public.project_boards pb ON pb.id = bi.board_id
  WHERE bi.id = p_board_item_id;

  IF v_board_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Card not found');
  END IF;

  -- Card-level files
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', f.id,
    'drive_file_id', f.drive_file_id,
    'drive_file_url', f.drive_file_url,
    'filename', f.filename,
    'mime_type', f.mime_type,
    'size_bytes', f.size_bytes,
    'uploaded_by_name', m.name,
    'uploaded_via', f.uploaded_via,
    'created_at', f.created_at
  ) ORDER BY f.created_at DESC), '[]'::jsonb)
  INTO v_files
  FROM public.board_item_files f
  LEFT JOIN public.members m ON m.id = f.uploaded_by
  WHERE f.board_item_id = p_board_item_id AND f.deleted_at IS NULL;

  -- Initiative-level folder links (Hub de Comunicacao folder + Atas)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id,
    'drive_folder_id', l.drive_folder_id,
    'drive_folder_url', l.drive_folder_url,
    'drive_folder_name', l.drive_folder_name,
    'link_purpose', l.link_purpose,
    'linked_at', l.linked_at
  ) ORDER BY l.link_purpose NULLS LAST, l.linked_at), '[]'::jsonb)
  INTO v_initiative_folders
  FROM public.initiative_drive_links l
  WHERE l.initiative_id = v_initiative_id AND l.unlinked_at IS NULL;

  -- Board-level folder links (rare but supported)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id,
    'drive_folder_id', l.drive_folder_id,
    'drive_folder_url', l.drive_folder_url,
    'drive_folder_name', l.drive_folder_name,
    'linked_at', l.linked_at
  ) ORDER BY l.linked_at), '[]'::jsonb)
  INTO v_board_folders
  FROM public.board_drive_links l
  WHERE l.board_id = v_board_id AND l.unlinked_at IS NULL;

  RETURN jsonb_build_object(
    'board_item_id', p_board_item_id,
    'files', v_files,
    'initiative_folders', v_initiative_folders,
    'board_folders', v_board_folders,
    'fetched_at', now()
  );
END;
$$


CREATE OR REPLACE FUNCTION public.list_pending_curation(p_table text DEFAULT 'all'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_member_id uuid; v_result jsonb := '[]'::jsonb; v_resources jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_member_id, 'write') THEN RAISE EXCEPTION 'Insufficient permissions'; END IF;

  -- ADR-0012 archival: artifacts branch removed. publication_submissions flow via approval_chains.
  IF p_table IN ('all', 'hub_resources') THEN
    SELECT COALESCE(jsonb_agg(row_to_json(r)), '[]'::jsonb) INTO v_resources
    FROM (
      SELECT h.id, h.title, h.url, h.asset_type AS type, h.source, h.tags,
             h.curation_status, h.trello_card_id, h.cycle_code AS cycle,
             h.created_at, NULL::text AS author_name,
             i.title AS tribe_name,
             'hub_resources' AS _table,
             public.suggest_tags(h.title, h.asset_type, h.cycle_code) AS suggested_tags
      FROM public.hub_resources h
      LEFT JOIN public.initiatives i ON i.id = h.initiative_id
      WHERE h.source IS DISTINCT FROM 'manual'
        AND h.curation_status IN ('draft','pending_review')
      ORDER BY h.created_at DESC LIMIT 200
    ) r;
    v_result := v_result || COALESCE(v_resources, '[]'::jsonb);
  END IF;
  RETURN v_result;
END;
$$


CREATE OR REPLACE FUNCTION public.recirculate_governance_doc(p_chain_id uuid, p_dry_run boolean DEFAULT true, p_recipient_emails text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_member record;
  v_chain record;
  v_document record;
  v_current_version record;
  v_draft record;
  v_first_gate jsonb;
  v_first_gate_kind text;
  v_recipients jsonb := '[]'::jsonb;
  v_recipient_count int := 0;
  v_send_results jsonb := '[]'::jsonb;
  v_send record;
  v_send_result jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_lock_result jsonb;
  v_new_chain_id uuid;
  v_platform_url text := 'https://nucleoia.vitormr.dev';
  v_changelog_html text;
  v_prior_resolved_count int := 0;
  v_prior_open_count int := 0;
  v_prior_summary_html text := '';
BEGIN
  SELECT m.id, m.name INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT public.can_by_member(v_member.id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: manage_member required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT ac.id, ac.document_id, ac.version_id, ac.status, ac.gates, ac.opened_at
  INTO v_chain
  FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN
    RAISE EXCEPTION 'approval_chain not found (id=%)', p_chain_id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_chain.status NOT IN ('review','active') THEN
    RAISE EXCEPTION 'approval_chain status=% — recirculation requires status review or active', v_chain.status
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT gd.id, gd.title, gd.doc_type INTO v_document
  FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  SELECT dv.id, dv.version_label, dv.version_number INTO v_current_version
  FROM public.document_versions dv WHERE dv.id = v_chain.version_id;

  SELECT dv.id, dv.version_number, dv.version_label, dv.notes, dv.locked_at
  INTO v_draft
  FROM public.document_versions dv
  WHERE dv.document_id = v_chain.document_id
    AND dv.version_number > v_current_version.version_number
    AND dv.locked_at IS NULL
  ORDER BY dv.version_number ASC LIMIT 1;
  IF v_draft.id IS NULL THEN
    RAISE EXCEPTION 'no pending draft version found for document_id=% (current version_number=%)',
      v_chain.document_id, v_current_version.version_number USING ERRCODE = 'no_data_found';
  END IF;

  SELECT g INTO v_first_gate
  FROM jsonb_array_elements(v_chain.gates) g
  ORDER BY (g->>'order')::int ASC LIMIT 1;
  v_first_gate_kind := v_first_gate->>'kind';

  IF p_recipient_emails IS NOT NULL AND array_length(p_recipient_emails, 1) IS NOT NULL THEN
    SELECT jsonb_agg(jsonb_build_object(
      'email', lower(e.email),
      'first_name', split_part(COALESCE(m.name, e.email), ' ', 1),
      'member_id', m.id,
      'source', 'explicit'
    )) INTO v_recipients
    FROM unnest(p_recipient_emails) AS e(email)
    LEFT JOIN public.members m ON lower(m.email) = lower(e.email);
  ELSE
    SELECT jsonb_agg(jsonb_build_object(
      'email', lower(m.email),
      'first_name', split_part(m.name, ' ', 1),
      'member_id', m.id,
      'source', 'auto_first_gate_eligible'
    )) INTO v_recipients
    FROM public.members m
    WHERE m.is_active = true
      AND m.email IS NOT NULL
      AND public._can_sign_gate(m.id, p_chain_id, v_first_gate_kind);
  END IF;

  IF v_recipients IS NULL OR jsonb_array_length(v_recipients) = 0 THEN
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code', 'no_recipients',
      'message', 'No recipients computed — execution will skip email step'
    ));
    v_recipients := '[]'::jsonb;
    v_recipient_count := 0;
  ELSE
    v_recipient_count := jsonb_array_length(v_recipients);
  END IF;

  IF v_draft.notes IS NOT NULL THEN
    v_changelog_html := '<pre style="white-space:pre-wrap; font-family:monospace; font-size:13px; background:#f9fafb; padding:12px; border-radius:6px; border:1px solid #e5e7eb;">' ||
                        replace(replace(v_draft.notes, '<', '&lt;'), '>', '&gt;') ||
                        '</pre>';
  ELSE
    v_changelog_html := '<p><em>(Sem changelog detalhado nas notes do draft.)</em></p>';
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE dc.resolved_at IS NOT NULL),
    COUNT(*) FILTER (WHERE dc.resolved_at IS NULL)
  INTO v_prior_resolved_count, v_prior_open_count
  FROM public.document_comments dc
  JOIN public.document_versions dv2 ON dv2.id = dc.document_version_id
  WHERE dv2.document_id = v_document.id
    AND dv2.locked_at IS NOT NULL
    AND dv2.version_number < v_current_version.version_number;

  IF v_prior_resolved_count + v_prior_open_count > 0 THEN
    SELECT
      '<details><summary style="cursor:pointer; font-weight:600;">' ||
      'Ver detalhe (' || (v_prior_resolved_count + v_prior_open_count)::text || ' comentário(s))' ||
      '</summary><ul style="font-size:12px; margin:8px 0; padding-left:20px;">' ||
      string_agg(
        '<li style="margin:6px 0;">' ||
        CASE WHEN dc.resolved_at IS NOT NULL
          THEN '<span style="color:#059669;">✓ endereçado</span>'
          ELSE '<span style="color:#dc2626;">⚠ ainda aberto</span>'
        END ||
        ' — <strong>' || COALESCE(m.name, '?') || '</strong>' ||
        CASE WHEN dc.clause_anchor IS NOT NULL
          THEN ' (§ ' || dc.clause_anchor || ')'
          ELSE ''
        END ||
        ': <em>"' ||
        replace(replace(LEFT(dc.body, 140), '<', '&lt;'), '>', '&gt;') ||
        CASE WHEN length(dc.body) > 140 THEN '…' ELSE '' END ||
        '"</em>' ||
        '</li>',
        ''
        ORDER BY dc.resolved_at IS NULL DESC, dc.created_at DESC
      ) ||
      '</ul></details>'
    INTO v_prior_summary_html
    FROM public.document_comments dc
    JOIN public.document_versions dv2 ON dv2.id = dc.document_version_id
    LEFT JOIN public.members m ON m.id = dc.author_id
    WHERE dv2.document_id = v_document.id
      AND dv2.locked_at IS NOT NULL
      AND dv2.version_number < v_current_version.version_number
      AND dc.visibility IN ('curator_only', 'public');
  ELSE
    v_prior_summary_html := '<p style="font-size:12px; color:#6b7280; font-style:italic;">(Sem comentários em versões anteriores.)</p>';
  END IF;

  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'dry_run', true,
      'valid', true,
      'document', jsonb_build_object(
        'id', v_document.id,
        'title', v_document.title,
        'doc_type', v_document.doc_type
      ),
      'current_chain', jsonb_build_object(
        'id', v_chain.id,
        'status', v_chain.status,
        'version_id', v_chain.version_id,
        'version_label', v_current_version.version_label,
        'version_number', v_current_version.version_number,
        'opened_at', v_chain.opened_at
      ),
      'draft_version', jsonb_build_object(
        'id', v_draft.id,
        'version_number', v_draft.version_number,
        'version_label', v_draft.version_label,
        'notes_present', v_draft.notes IS NOT NULL,
        'notes_length', COALESCE(length(v_draft.notes), 0)
      ),
      'gates_to_copy', v_chain.gates,
      'first_gate_kind', v_first_gate_kind,
      'recipients', v_recipients,
      'recipient_count', v_recipient_count,
      'prior_comments_summary', jsonb_build_object(
        'resolved_count', v_prior_resolved_count,
        'open_count', v_prior_open_count
      ),
      'warnings', v_warnings,
      'next_step_summary', 'Execute with p_dry_run=false to: (1) supersede chain, (2) lock draft + create new chain via lock_document_version, (3) email recipients, (4) audit log.'
    );
  END IF;

  UPDATE public.approval_chains
    SET status = 'superseded',
        closed_at = now(),
        closed_by = v_member.id,
        notes = COALESCE(notes,'') || E'\n[recirculated at ' || now()::text ||
                ' by ' || v_member.name || ' — superseded by new draft v' || v_draft.version_label || ']',
        updated_at = now()
    WHERE id = p_chain_id;

  v_lock_result := public.lock_document_version(v_draft.id, v_chain.gates);
  IF NOT (v_lock_result->>'success')::boolean THEN
    RAISE EXCEPTION 'lock_document_version failed: %', v_lock_result::text USING ERRCODE = 'integrity_constraint_violation';
  END IF;
  v_new_chain_id := (v_lock_result->>'chain_id')::uuid;

  IF v_recipient_count > 0 THEN
    FOR v_send IN SELECT * FROM jsonb_to_recordset(v_recipients) AS x(
      email text, first_name text, member_id uuid, source text
    ) LOOP
      BEGIN
        v_send_result := public.campaign_send_one_off(
          'governance_recirculation_request',
          v_send.email,
          jsonb_build_object(
            'first_name', COALESCE(v_send.first_name, 'Curador'),
            'document_title', v_document.title,
            'version_label', v_draft.version_label,
            'new_chain_url', v_platform_url || '/admin/governance/documents/' || v_new_chain_id::text,
            'old_chain_url', v_platform_url || '/admin/governance/documents/' || p_chain_id::text,
            'changelog', v_changelog_html,
            'prior_resolved_count', v_prior_resolved_count::text,
            'prior_open_count', v_prior_open_count::text,
            'prior_addressed_summary', v_prior_summary_html,
            'platform_url', v_platform_url,
            'sender_name', v_member.name
          ),
          jsonb_build_object(
            'source', 'governance_recirculation',
            'document_id', v_document.id,
            'old_chain_id', p_chain_id,
            'new_chain_id', v_new_chain_id,
            'recipient_name', v_send.first_name
          )
        );
        v_send_results := v_send_results || jsonb_build_array(jsonb_build_object(
          'email', v_send.email,
          'send_id', v_send_result->>'send_id',
          'status', 'enqueued'
        ));
      EXCEPTION WHEN OTHERS THEN
        v_send_results := v_send_results || jsonb_build_array(jsonb_build_object(
          'email', v_send.email,
          'send_id', NULL,
          'status', 'failed',
          'error', SQLERRM
        ));
      END;
    END LOOP;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_member.id,
    'governance.recirculated',
    'governance_document',
    v_document.id,
    jsonb_build_object(
      'old_chain_id', p_chain_id,
      'new_chain_id', v_new_chain_id,
      'old_version', v_current_version.version_label,
      'new_version', v_draft.version_label,
      'recipients_count', v_recipient_count,
      'recipient_emails', (SELECT jsonb_agg(r->>'email') FROM jsonb_array_elements(v_recipients) r),
      'prior_resolved_count', v_prior_resolved_count,
      'prior_open_count', v_prior_open_count,
      'send_results', v_send_results
    ),
    jsonb_build_object(
      'doc_type', v_document.doc_type,
      'first_gate_kind', v_first_gate_kind,
      'sender_member_id', v_member.id
    )
  );

  RETURN jsonb_build_object(
    'dry_run', false,
    'success', true,
    'old_chain_id', p_chain_id,
    'new_chain_id', v_new_chain_id,
    'version_id_locked', v_draft.id,
    'document_id', v_document.id,
    'recipients_count', v_recipient_count,
    'prior_comments_summary', jsonb_build_object(
      'resolved_count', v_prior_resolved_count,
      'open_count', v_prior_open_count
    ),
    'send_results', v_send_results,
    'warnings', v_warnings
  );
END;
$$


CREATE OR REPLACE FUNCTION public.request_interview_reschedule(p_application_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record;
  v_app record;
  v_committee record;
  v_send_result jsonb;
  v_first_name text;
  v_was_noshow boolean := false;
  v_booking_url text := 'https://calendar.app.google/gh9WjefjcmisVLoh7';
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id
    AND member_id = v_caller.id
    AND role = 'lead';

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or have manage_member';
  END IF;

  -- p109 Onda 4 Fase 1.3: aceitar interview_noshow (segunda chance é o caso comum)
  IF v_app.status NOT IN ('interview_pending', 'interview_scheduled', 'interview_noshow') THEN
    RAISE EXCEPTION 'Application status % does not allow reschedule request', v_app.status;
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'Reschedule reason is required';
  END IF;

  v_was_noshow := v_app.status = 'interview_noshow';

  -- Reset status para 'interview_pending' se estava em noshow (limpa stuck state)
  UPDATE public.selection_applications
  SET interview_status = 'needs_reschedule',
      interview_reschedule_reason = p_reason,
      interview_reschedule_requested_at = now(),
      interview_reschedule_requested_by = v_caller.id,
      status = CASE WHEN v_was_noshow THEN 'interview_pending' ELSE status END,
      updated_at = now()
  WHERE id = p_application_id;

  UPDATE public.selection_interviews
  SET status = 'rescheduled',
      notes = COALESCE(notes || E'\n', '')
            || '[' || to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI') || ' BRT] '
            || 'Marked for reschedule by ' || COALESCE(v_caller.name, 'admin')
            || CASE WHEN v_was_noshow THEN ' (from no-show)' ELSE '' END
            || ': ' || p_reason
  WHERE application_id = p_application_id
    AND status IN ('scheduled', 'noshow');

  v_first_name := COALESCE(
    NULLIF(trim(v_app.first_name), ''),
    NULLIF(split_part(v_app.applicant_name, ' ', 1), ''),
    'candidato(a)'
  );

  v_send_result := public.campaign_send_one_off(
    'interview_reschedule_request',
    v_app.email,
    jsonb_build_object(
      'first_name', v_first_name,
      'reason', p_reason,
      'booking_url', v_booking_url
    ),
    jsonb_build_object(
      'language', 'pt',
      'recipient_name', COALESCE(v_app.first_name, v_app.applicant_name),
      'source', 'request_interview_reschedule'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'send_id', v_send_result->>'send_id',
    'booking_url', v_booking_url,
    'interview_status', 'needs_reschedule',
    'was_noshow', v_was_noshow,
    'requested_by', v_caller.id,
    'requested_at', now()
  );
END;
$$


CREATE OR REPLACE FUNCTION public.request_secondary_email_verification(p_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id              uuid;
  v_caller_primary_email   text;
  v_caller_secondary_array text[];
  v_other_member           uuid;
  v_token                  text;
  v_pending_id             uuid;
  v_service_role_key       text;
  v_normalized_email       text;
BEGIN
  SELECT id, email, COALESCE(secondary_emails, '{}'::text[])
    INTO v_caller_id, v_caller_primary_email, v_caller_secondary_array
    FROM public.members
   WHERE auth_id = (SELECT auth.uid())
   LIMIT 1;

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  v_normalized_email := lower(trim(coalesce(p_email, '')));

  IF v_normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid email format');
  END IF;

  IF lower(coalesce(v_caller_primary_email,'')) = v_normalized_email THEN
    RETURN jsonb_build_object('success', false, 'error', 'Email is already your primary');
  END IF;

  IF v_normalized_email = ANY(SELECT lower(unnest(v_caller_secondary_array))) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Email is already in your secondary list');
  END IF;

  SELECT id INTO v_other_member
    FROM public.members
   WHERE id <> v_caller_id
     AND (
       lower(coalesce(email,'')) = v_normalized_email
       OR v_normalized_email = ANY(SELECT lower(unnest(coalesce(secondary_emails, '{}'::text[]))))
     )
   LIMIT 1;

  IF v_other_member IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Email already linked to another member. Contact an admin if you believe this is wrong.');
  END IF;

  -- Schema-qualify pgcrypto call
  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  INSERT INTO public.email_verification_pending(token, target_email, requesting_member_id, purpose)
  VALUES (v_token, v_normalized_email, v_caller_id, 'add_secondary_email')
  RETURNING id INTO v_pending_id;

  BEGIN
    SELECT decrypted_secret INTO v_service_role_key
      FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

    IF v_service_role_key IS NOT NULL THEN
      PERFORM net.http_post(
        url     := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/send-email-verification',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_role_key
        ),
        body    := jsonb_build_object('token', v_token)
      );
    ELSE
      RAISE NOTICE 'request_secondary_email_verification: no service_role_key in vault, EF not dispatched (token still valid)';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'request_secondary_email_verification dispatch failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success',      true,
    'target_email', v_normalized_email,
    'expires_at',   (SELECT expires_at FROM public.email_verification_pending WHERE id = v_pending_id),
    'pending_id',   v_pending_id
  );
END;
$$


CREATE OR REPLACE FUNCTION public.resolve_document_comment(p_comment_id uuid, p_resolution_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_member record;
  v_comment record;
BEGIN
  SELECT m.id, m.operational_role, m.designations, m.is_active
  INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL OR v_member.is_active = false THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  SELECT c.id, c.author_id, c.resolved_at INTO v_comment
  FROM public.document_comments c WHERE c.id = p_comment_id;
  IF v_comment.id IS NULL THEN
    RETURN jsonb_build_object('error','not_found');
  END IF;
  IF v_comment.resolved_at IS NOT NULL THEN
    RETURN jsonb_build_object('error','already_resolved');
  END IF;

  -- ADR-0041: V4 catalog OR Path Y (author self-resolve preserved)
  IF NOT (
    v_comment.author_id = v_member.id
    OR public.can_by_member(v_member.id, 'participate_in_governance_review')
  ) THEN
    RETURN jsonb_build_object('error','not_authorized');
  END IF;

  UPDATE public.document_comments
  SET resolved_at = now(), resolved_by = v_member.id, resolution_note = p_resolution_note, updated_at = now()
  WHERE id = p_comment_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'document_comment_resolved', 'document_comment', p_comment_id,
    jsonb_build_object('resolution_note', p_resolution_note));

  RETURN jsonb_build_object('success', true, 'resolved_at', now());
END;
$$


CREATE OR REPLACE FUNCTION public.update_event_instance(p_event_id uuid, p_new_date date DEFAULT NULL::date, p_new_time_start time without time zone DEFAULT NULL::time without time zone, p_new_duration_minutes integer DEFAULT NULL::integer, p_meeting_link text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_agenda_text text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_event_tribe int;
  v_event_exists boolean;
  v_updated text[] := '{}';
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT true, i.legacy_tribe_id
    INTO v_event_exists, v_event_tribe
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.id = p_event_id;
  IF v_event_exists IS NOT TRUE THEN RAISE EXCEPTION 'Event not found'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;
  IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_event_tribe THEN
    RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage events of own tribe';
  END IF;

  IF p_new_date IS NOT NULL THEN
    IF v_event_tribe IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.events e2
      JOIN public.initiatives i2 ON i2.id = e2.initiative_id
      WHERE i2.legacy_tribe_id = v_event_tribe
        AND e2.date = p_new_date
        AND e2.id <> p_event_id
    ) THEN
      RAISE EXCEPTION 'Ja existe um evento desta tribo na data %', p_new_date;
    END IF;
    UPDATE public.events SET date = p_new_date, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'date');
  END IF;
  IF p_new_time_start IS NOT NULL THEN
    UPDATE public.events SET time_start = p_new_time_start, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'time_start');
  END IF;
  IF p_new_duration_minutes IS NOT NULL THEN
    UPDATE public.events SET duration_minutes = p_new_duration_minutes, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'duration_minutes');
  END IF;
  IF p_meeting_link IS NOT NULL THEN
    UPDATE public.events SET meeting_link = p_meeting_link, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'meeting_link');
  END IF;
  IF p_notes IS NOT NULL THEN
    UPDATE public.events SET notes = p_notes, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'notes');
  END IF;
  IF p_agenda_text IS NOT NULL THEN
    UPDATE public.events SET agenda_text = p_agenda_text, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'agenda_text');
  END IF;

  RETURN json_build_object('success', true, 'event_id', p_event_id, 'updated_fields', to_json(v_updated));
END;
$$


CREATE OR REPLACE FUNCTION public.validate_status_transition(p_from text, p_to text)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- Self-transitions are idempotent
  IF p_from = p_to THEN RETURN; END IF;

  -- candidate is pre-membership
  IF p_from = 'candidate' AND p_to <> 'active' THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Invalid transition: candidate -> ' || p_to || '. Candidates only become active via selection acceptance.',
      ERRCODE = '22023';
  END IF;

  IF p_to = 'candidate' AND p_from IN ('active','observer','alumni','inactive') THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Invalid transition: ' || p_from || ' -> candidate. Candidate is pre-membership, not reachable from member states.',
      ERRCODE = '22023';
  END IF;

  -- ARM-9 Features Post-G2: alumni → active requires re-engagement pipeline path
  -- Direct alumni→active is now blocked; must use accepted pipeline entry.
  -- The check for the accepted pipeline entry happens in admin_reactivate_member,
  -- not here (this fn is IMMUTABLE and stateless).
  IF p_from = 'alumni' AND p_to = 'active' THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Invalid transition: alumni -> active. Alumni reactivation requires re-engagement pipeline (stage → invite → accepted). Use re_engagement_pipeline workflow + admin_reactivate_member.',
      ERRCODE = '22023';
  END IF;

  RETURN;
END;
$$
