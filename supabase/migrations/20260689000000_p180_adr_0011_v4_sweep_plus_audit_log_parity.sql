-- ============================================================================
-- p180 ADR-0011 V4 sweep + audit_log parity
-- ============================================================================
-- 2026-05-17 · session p180
-- PM directive: hybrid V3+V4 (preserves V3 surface; adds V4 capability OR
-- branch). Defense-in-depth — no regression risk. Same pattern as p178
-- review_change_request and p179 approve_change_request.
--
-- Scope (6 functions):
--   1. resolve_whatsapp_link       — HYBRID: adds can_by_member(view_pii)
--   2. update_board_item           — HYBRID: adds can_by_member(manage_platform) to v_is_gp
--   3. get_board_members           — V4 SWAP: priority-4 (GP) via can_by_member(manage_platform)
--   4. count_tribe_slots           — DEFENSE: adds caller auth gate (any authed)
--   5. detect_stale_events_cron    — PARITY: admin_audit_log INSERT (mirror detect_inactive_members)
--   6. detect_stale_portfolio_items_cron — PARITY: admin_audit_log INSERT
--
-- Deferred from p180 scope (PM-confirmed 2026-05-17):
--   - has_min_tier rank-4 swap: real V4 requires joint migration of 3 RLS
--     policies (announcements / member_cycle_history / home_schedule) + 1 RPC
--     (exec_cert_timeline). Carry to p181+ as dedicated sprint.
--
-- Surface impact (resolve_whatsapp_link hybrid):
--   V3 path (preserved):  is_superadmin OR operational_role IN ('manager','deputy_manager')
--   V4 path (added):      can_by_member(view_pii)  → adds 14 users (tribe leaders,
--                          chapter_board, sponsors, study_group_owner, committee/workgroup
--                          coordinator+leader). All semantically PII-handling roles per
--                          catalog seed.
--   Domain path (unchanged): same tribe_id match.
--
-- Surface impact (update_board_item v_is_gp hybrid):
--   V3 path (preserved):  is_superadmin OR operational_role IN ('manager','deputy_manager')
--                         OR 'co_gp' = ANY(designations)
--   V4 path (added):      can_by_member(manage_platform) (= volunteer × {co_gp, deputy_manager, manager})
--   Net: zero new users today (catalog matches V3 surface 1:1). Defense-in-depth
--   for future cache drift / catalog expansion.
--
-- Surface impact (get_board_members priority-4):
--   V3 path replaced:     is_superadmin OR operational_role IN ('manager','deputy_manager')
--   V4 path:              is_superadmin OR can_by_member(manage_platform)
--   Net: co_gp gains visibility as priority-4 'gp' (was already visible via
--   priority-5 engagement_member if initiative engagement exists).
--
-- audit_log target_type: NOT NULL with DEFAULT 'member'. Cron fns pass
-- 'system_event' explicitly (semantic over default). Latent issue:
-- detect_inactive_members passes NULL explicitly, overriding default → would
-- fail on first non-dry-run. Tracked as backlog (not in p180 scope; 0 historical
-- inserts so no live data corruption).
--
-- Rollback:
--   Revert each CREATE OR REPLACE FUNCTION to its prior body via
--   migrations 20260680000000 baseline (or pg_get_functiondef pre-p180 snapshot).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. resolve_whatsapp_link — HYBRID V3+V4 (view_pii expansion)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_whatsapp_link(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_caller_id uuid := auth.uid();
  v_caller record;
  v_target record;
  v_clean_phone text;
begin
  -- Get caller
  select id, tribe_id, operational_role, is_superadmin
    into v_caller from public.members where auth_id = v_caller_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Caller not found');
  end if;

  -- Get target
  select id, phone, tribe_id, share_whatsapp
    into v_target from public.members where id = p_member_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Member not found');
  end if;

  -- Check opt-in
  if v_target.share_whatsapp is not true then
    return jsonb_build_object('success', false, 'error', 'Member has not opted in');
  end if;

  -- p180 ADR-0011 V4: hybrid V3+V4 PII access gate.
  -- V3 paths preserved (admin override + same-tribe). V4 path added via
  -- can_by_member('view_pii') — covers chapter_board, committee/workgroup
  -- coordinators+leaders, study_group owners, volunteer × {co_gp, leader,
  -- deputy_manager, manager}. Defense-in-depth: V3 stays as fallback if
  -- catalog drifts.
  if not (
    v_caller.is_superadmin = true
    or v_caller.operational_role in ('manager', 'deputy_manager')
    or public.can_by_member(v_caller.id, 'view_pii')
    or (v_caller.tribe_id is not null and v_caller.tribe_id = v_target.tribe_id)
  ) then
    return jsonb_build_object('success', false, 'error', 'Not authorized');
  end if;

  -- No phone registered
  if v_target.phone is null or v_target.phone = '' then
    return jsonb_build_object('success', false, 'error', 'No phone registered');
  end if;

  -- Clean phone: keep only digits
  v_clean_phone := regexp_replace(v_target.phone, '[^0-9]', '', 'g');

  return jsonb_build_object(
    'success', true,
    'url', 'https://wa.me/' || v_clean_phone
  );
end;
$function$;

-- ----------------------------------------------------------------------------
-- 2. update_board_item — HYBRID v_is_gp (manage_platform UNION)
-- ----------------------------------------------------------------------------
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

  IF NOT public.can_by_member(v_caller.id, 'write_board')
     AND NOT v_is_board_admin AND NOT v_is_card_owner AND NOT v_is_board_editor
     AND NOT v_is_comms_for_domain THEN
    IF NOT (
      coalesce(v_board.domain_key, '') = 'publications_submissions' AND (
        v_caller.operational_role IN ('tribe_leader', 'communicator')
        OR coalesce('curator' = ANY(v_caller.designations), false)
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

  -- Item 02 fix: relax assignee_id for comms domain
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

-- ----------------------------------------------------------------------------
-- 3. get_board_members — priority-4 V4 swap
-- ----------------------------------------------------------------------------
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

  SELECT i.legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives i WHERE i.id = v_board.initiative_id;

  RETURN QUERY
  SELECT DISTINCT ON (q.id) q.id, q.name, q.photo_url, q.operational_role, q.board_role, q.designations
  FROM (
    -- Priority 1: tribe members (legacy tribe_id match — applies to research_tribe boards)
    SELECT m.id, m.name, m.photo_url, m.operational_role, 'tribe_member'::text as board_role, m.designations, 1 as priority
    FROM members m
    WHERE v_board_legacy_tribe_id IS NOT NULL
      AND m.tribe_id = v_board_legacy_tribe_id
      AND m.is_active = true
      AND m.member_status = 'active'
    UNION ALL
    -- Priority 2: explicitly added to board_members
    SELECT bm.member_id, m.name, m.photo_url, m.operational_role, bm.board_role, m.designations, 2
    FROM board_members bm
    JOIN members m ON m.id = bm.member_id
    WHERE bm.board_id = p_board_id
      AND m.is_active = true
    UNION ALL
    -- Priority 3: all curators
    SELECT m.id, m.name, m.photo_url, m.operational_role, 'curator'::text, m.designations, 3
    FROM members m
    WHERE 'curator' = ANY(m.designations)
      AND m.is_active = true
    UNION ALL
    -- Priority 4: GP / superadmin
    -- p180 ADR-0011 V4: replaced operational_role IN ('manager','deputy_manager')
    -- with can_by_member(manage_platform) → covers volunteer × {co_gp, deputy_manager,
    -- manager}. Co_gp now visible as 'gp' priority (was already visible via
    -- priority-5 engagement_member if initiative engagement exists).
    SELECT m.id, m.name, m.photo_url, m.operational_role, 'gp'::text, m.designations, 4
    FROM members m
    WHERE m.is_active = true
      AND (m.is_superadmin = true OR public.can_by_member(m.id, 'manage_platform'))
    UNION ALL
    -- Priority 5: NEW — members with active engagement on the board's initiative
    -- Closes Mayanna Item 02: workgroup/committee/study_group members were
    -- invisible because legacy_tribe_id NULL skipped priority 1.
    SELECT m.id, m.name, m.photo_url, m.operational_role, 'engagement_member'::text, m.designations, 5
    FROM members m
    JOIN persons p ON p.id = m.person_id
    JOIN engagements e ON e.person_id = p.id
    WHERE e.initiative_id = v_board.initiative_id
      AND e.status = 'active'
      AND m.is_active = true
      AND m.member_status = 'active'
  ) q
  ORDER BY q.id, q.priority;
END;
$function$;

-- ----------------------------------------------------------------------------
-- 4. count_tribe_slots — add caller auth gate
-- ----------------------------------------------------------------------------
-- Was: pure SQL fn with no auth gate. Aggregate non-PII data, but unauthenticated
-- access is defensively gated to consistency with other tribe RPCs.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.count_tribe_slots()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result json;
BEGIN
  -- p180 ADR-0011: add caller auth gate. Any authenticated user can read tribe
  -- seat counts (aggregate non-PII). The exclusion list (sponsor / chapter_liaison
  -- / guest / none) is a domain rule (which engagement kinds count as "tribe
  -- seat"), not an auth concern — preserved as-is.
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: authentication required';
  END IF;

  SELECT coalesce(
    json_object_agg(tribe_id, cnt),
    '{}'::json
  )
  INTO v_result
  FROM (
    SELECT tribe_id, count(*)::int as cnt
    FROM public.members
    WHERE member_status = 'active'
      AND tribe_id IS NOT NULL
      AND operational_role NOT IN ('sponsor', 'chapter_liaison', 'guest', 'none')
    GROUP BY tribe_id
  ) sub;

  RETURN v_result;
END;
$function$;

-- ----------------------------------------------------------------------------
-- 5. detect_stale_events_cron — audit_log parity
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.detect_stale_events_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count integer := 0;
  v_inserted integer := 0;
BEGIN
  -- 24-48h window (gives líder 1 day to react before falling into wider monitoring)
  SELECT count(*) INTO v_count
  FROM events e
  WHERE e.date BETWEEN CURRENT_DATE - 2 AND CURRENT_DATE - 1
    AND NOT EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id);

  IF v_count > 0 THEN
    -- p179 ADR-0011 V4: notify admins via manage_platform capability
    -- (replaces operational_role IN ('manager','deputy_manager')).
    INSERT INTO notifications (recipient_id, type, title, body, delivery_mode, created_at)
    SELECT m.id,
           'event_stale_no_attendance',
           format('%s evento(s) sem attendance marcado', v_count),
           format('%s evento(s) passado(s) há mais de 24h não tem nenhuma marcação de presença. Cancele se a reunião não aconteceu OU marque presença em /attendance.', v_count),
           'digest_weekly',
           now()
    FROM members m
    WHERE m.is_active = true
      AND can_by_member(m.id, 'manage_platform');
    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    -- p180: admin_audit_log parity with detect_inactive_members.
    -- target_type='system_event' (explicit, not relying on column DEFAULT).
    -- actor_id=NULL per LGPD memory: NULL is correct for cron/no-member contexts.
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL, 'cron.detect_stale_events_run', 'system_event', NULL,
      jsonb_build_object('stale_count', v_count, 'managers_notified', v_inserted, 'window_hours', 48),
      jsonb_build_object('source', 'cron_detect_stale_events')
    );
  END IF;

  RETURN jsonb_build_object(
    'stale_count', v_count,
    'notifications_inserted', v_inserted,
    'window_hours', 48,
    'run_at', now()
  );
END $function$;

-- ----------------------------------------------------------------------------
-- 6. detect_stale_portfolio_items_cron — audit_log parity
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.detect_stale_portfolio_items_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count integer := 0;
  v_inserted integer := 0;
  v_stale_threshold interval := '60 days';
BEGIN
  SELECT count(*) INTO v_count
  FROM board_items bi
  WHERE bi.is_portfolio_item = true
    AND bi.status NOT IN ('done', 'archived')
    AND bi.updated_at < now() - v_stale_threshold;

  -- Only insert reminder if there is something stale (smart-skip empty digest per ADR-0022)
  IF v_count > 0 THEN
    -- p179 ADR-0011 V4: notify admins via manage_platform capability
    -- (replaces operational_role IN ('manager','deputy_manager')).
    INSERT INTO notifications (recipient_id, type, title, body, delivery_mode, created_at)
    SELECT m.id,
           'portfolio_stale_reminder',
           format('%s portfolio item(s) precisam de update', v_count),
           format('%s itens marcados is_portfolio_item=true sem update há mais de 60 dias. Revise via /admin/portfolio.', v_count),
           'digest_weekly',
           now()
    FROM members m
    WHERE m.is_active = true
      AND can_by_member(m.id, 'manage_platform');

    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    -- p180: admin_audit_log parity with detect_inactive_members.
    -- target_type='system_event' (explicit, not relying on column DEFAULT).
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL, 'cron.detect_stale_portfolio_items_run', 'system_event', NULL,
      jsonb_build_object('stale_count', v_count, 'managers_notified', v_inserted, 'threshold_days', 60),
      jsonb_build_object('source', 'cron_detect_stale_portfolio_items')
    );
  END IF;

  RETURN jsonb_build_object(
    'stale_count', v_count,
    'notifications_inserted', v_inserted,
    'threshold_days', 60,
    'run_at', now()
  );
END $function$;

-- ============================================================================
-- PostgREST schema reload
-- ============================================================================
NOTIFY pgrst, 'reload schema';
