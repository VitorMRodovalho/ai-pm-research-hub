-- Phase B'' Pacote H (p60) — 8 admin_*/exec_* fns V3→V4 manage_platform
-- All currently SECDEF with V3 admin gate (is_superadmin OR manager/deputy_manager).
-- V4 manage_platform grant set is identical (2 = same superadmins).
--
-- Privilege expansion safety check (verified pre-apply):
--   V3 tight (5 fns): 2 members
--   V3 broad (3 fns: incl co_gp): 2 (same)
--   V4 manage_platform: 2 (same — superadmin override)
--   would_gain: [] / would_lose: []
--
-- search_path hardening:
--   5 fns: 'public, pg_temp' → '' (bodies already fully-qualified)
--   3 fns: KEEP 'public, pg_temp' (bodies have unqualified references;
--          full-qualify refactor out of scope — documented per fn)

-- ============================================================
-- 1. admin_detect_board_taxonomy_drift (search_path hardened)
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_detect_board_taxonomy_drift();
CREATE OR REPLACE FUNCTION public.admin_detect_board_taxonomy_drift()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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
$$;
REVOKE EXECUTE ON FUNCTION public.admin_detect_board_taxonomy_drift() FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_detect_board_taxonomy_drift() IS
  'Phase B'' V4 conversion (p60 Pacote H): manage_platform gate via can_by_member. Was V3 (superadmin OR manager/deputy_manager). search_path hardened to ''''.';

-- ============================================================
-- 2. admin_detect_data_anomalies (search_path hardened)
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_detect_data_anomalies(boolean);
CREATE OR REPLACE FUNCTION public.admin_detect_data_anomalies(p_auto_fix boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_fixed jsonb[] := '{}';
  v_pending jsonb[] := '{}';
  v_rec record;
  v_anomaly_id uuid;
  v_current_cycle text;
  v_counts jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT code INTO v_current_cycle FROM public.cycles WHERE is_current = true LIMIT 1;
  IF v_current_cycle IS NULL THEN
    v_current_cycle := 'cycle3-2026';
  END IF;

  -- ─── 1. tribe_selection_drift ───
  FOR v_rec IN
    SELECT m.id AS member_id, m.name, m.tribe_id AS member_tribe, ts.tribe_id AS selection_tribe
    FROM public.members m
    JOIN public.tribe_selections ts ON ts.member_id = m.id
    WHERE m.tribe_id IS DISTINCT FROM ts.tribe_id
      AND m.current_cycle_active = true
  LOOP
    v_anomaly_id := gen_random_uuid();
    INSERT INTO public.data_anomaly_log (id, anomaly_type, severity, member_id, description, auto_fixable, context)
    VALUES (v_anomaly_id, 'tribe_selection_drift', 'warning', v_rec.member_id,
      format('Member %s: members.tribe_id=%s differs from tribe_selections.tribe_id=%s',
        v_rec.name, v_rec.member_tribe, v_rec.selection_tribe),
      true,
      jsonb_build_object('member_tribe_id', v_rec.member_tribe, 'selection_tribe_id', v_rec.selection_tribe));

    IF p_auto_fix THEN
      UPDATE public.members SET tribe_id = v_rec.selection_tribe, updated_at = now()
      WHERE id = v_rec.member_id;
      UPDATE public.data_anomaly_log SET auto_fixed = true, fixed_at = now(), fixed_by = 'auto'
      WHERE id = v_anomaly_id;
      v_fixed := v_fixed || jsonb_build_object('type', 'tribe_selection_drift', 'member_id', v_rec.member_id);
    ELSE
      v_pending := v_pending || jsonb_build_object('type', 'tribe_selection_drift', 'member_id', v_rec.member_id);
    END IF;
  END LOOP;

  -- ─── 2. active_flag_inconsistency ───
  FOR v_rec IN
    SELECT m.id AS member_id, m.name, m.is_active, m.current_cycle_active, m.operational_role
    FROM public.members m
    WHERE m.is_active = false AND m.current_cycle_active = true
      AND (m.operational_role IS NULL OR m.operational_role = 'none' OR m.operational_role = '')
  LOOP
    v_anomaly_id := gen_random_uuid();
    INSERT INTO public.data_anomaly_log (id, anomaly_type, severity, member_id, description, auto_fixable, context)
    VALUES (v_anomaly_id, 'active_flag_inconsistency', 'warning', v_rec.member_id,
      format('Member %s: is_active=false but current_cycle_active=true with no operational role', v_rec.name),
      true,
      jsonb_build_object('is_active', v_rec.is_active, 'current_cycle_active', v_rec.current_cycle_active));

    IF p_auto_fix THEN
      UPDATE public.members SET current_cycle_active = false, updated_at = now()
      WHERE id = v_rec.member_id;
      UPDATE public.data_anomaly_log SET auto_fixed = true, fixed_at = now(), fixed_by = 'auto'
      WHERE id = v_anomaly_id;
      v_fixed := v_fixed || jsonb_build_object('type', 'active_flag_inconsistency', 'member_id', v_rec.member_id);
    ELSE
      v_pending := v_pending || jsonb_build_object('type', 'active_flag_inconsistency', 'member_id', v_rec.member_id);
    END IF;
  END LOOP;

  -- ─── 3. role_designation_mismatch (info, NOT auto-fixable) ───
  FOR v_rec IN
    SELECT m.id AS member_id, m.name, m.operational_role, m.designations
    FROM public.members m
    WHERE (m.operational_role IS NULL OR m.operational_role = 'none' OR m.operational_role = '')
      AND m.designations IS NOT NULL
      AND m.designations::text != '[]'
      AND m.designations::text != 'null'
      AND jsonb_array_length(m.designations) > 0
      AND m.current_cycle_active = true
  LOOP
    INSERT INTO public.data_anomaly_log (anomaly_type, severity, member_id, description, auto_fixable, context)
    VALUES ('role_designation_mismatch', 'info', v_rec.member_id,
      format('Member %s: operational_role is none but has designations %s', v_rec.name, v_rec.designations),
      false,
      jsonb_build_object('operational_role', v_rec.operational_role, 'designations', v_rec.designations));
    v_pending := v_pending || jsonb_build_object('type', 'role_designation_mismatch', 'member_id', v_rec.member_id);
  END LOOP;

  -- ─── 4. orphan_active_no_tribe (NOT auto-fixable) ───
  FOR v_rec IN
    SELECT m.id AS member_id, m.name, m.created_at
    FROM public.members m
    WHERE m.current_cycle_active = true
      AND m.tribe_id IS NULL
      AND m.created_at < (now() - interval '30 days')
  LOOP
    INSERT INTO public.data_anomaly_log (anomaly_type, severity, member_id, description, auto_fixable, context)
    VALUES ('orphan_active_no_tribe', 'warning', v_rec.member_id,
      format('Member %s: active with no tribe for over 30 days', v_rec.name),
      false,
      jsonb_build_object('created_at', v_rec.created_at));
    v_pending := v_pending || jsonb_build_object('type', 'orphan_active_no_tribe', 'member_id', v_rec.member_id);
  END LOOP;

  -- ─── 5. cycle_array_stale ───
  FOR v_rec IN
    SELECT m.id AS member_id, m.name, m.cycles
    FROM public.members m
    WHERE m.current_cycle_active = true
      AND m.cycles IS NOT NULL
      AND NOT (m.cycles ? v_current_cycle)
  LOOP
    v_anomaly_id := gen_random_uuid();
    INSERT INTO public.data_anomaly_log (id, anomaly_type, severity, member_id, description, auto_fixable, context)
    VALUES (v_anomaly_id, 'cycle_array_stale', 'info', v_rec.member_id,
      format('Member %s: current_cycle_active=true but cycles array does not include %s', v_rec.name, v_current_cycle),
      true,
      jsonb_build_object('cycles', v_rec.cycles, 'expected_cycle', v_current_cycle));

    IF p_auto_fix THEN
      UPDATE public.members
      SET cycles = CASE
        WHEN cycles IS NULL THEN jsonb_build_array(v_current_cycle)
        ELSE cycles || to_jsonb(v_current_cycle)
      END, updated_at = now()
      WHERE id = v_rec.member_id;
      UPDATE public.data_anomaly_log SET auto_fixed = true, fixed_at = now(), fixed_by = 'auto'
      WHERE id = v_anomaly_id;
      v_fixed := v_fixed || jsonb_build_object('type', 'cycle_array_stale', 'member_id', v_rec.member_id);
    ELSE
      v_pending := v_pending || jsonb_build_object('type', 'cycle_array_stale', 'member_id', v_rec.member_id);
    END IF;
  END LOOP;

  -- ─── 6. duplicate_email (critical, NOT auto-fixable) ───
  FOR v_rec IN
    SELECT m.email, array_agg(m.id) AS member_ids, count(*) AS cnt
    FROM public.members m
    WHERE m.email IS NOT NULL AND m.email != ''
    GROUP BY m.email
    HAVING count(*) > 1
  LOOP
    INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, auto_fixable, context)
    VALUES ('duplicate_email', 'critical',
      format('Duplicate email %s found in %s members', v_rec.email, v_rec.cnt),
      false,
      jsonb_build_object('email', v_rec.email, 'member_ids', to_jsonb(v_rec.member_ids), 'count', v_rec.cnt));
    v_pending := v_pending || jsonb_build_object('type', 'duplicate_email', 'email', v_rec.email);
  END LOOP;

  -- ─── 7. never_logged_in (info, NOT auto-fixable) ───
  FOR v_rec IN
    SELECT m.id AS member_id, m.name, m.created_at
    FROM public.members m
    WHERE m.auth_id IS NULL
      AND m.created_at < (now() - interval '60 days')
      AND m.current_cycle_active = true
  LOOP
    INSERT INTO public.data_anomaly_log (anomaly_type, severity, member_id, description, auto_fixable, context)
    VALUES ('never_logged_in', 'info', v_rec.member_id,
      format('Member %s: created over 60 days ago but never logged in', v_rec.name),
      false,
      jsonb_build_object('created_at', v_rec.created_at));
    v_pending := v_pending || jsonb_build_object('type', 'never_logged_in', 'member_id', v_rec.member_id);
  END LOOP;

  -- ─── 8. assignment_orphan ───
  FOR v_rec IN
    SELECT bia.id AS assignment_id, bia.member_id, bia.item_id, m.name
    FROM public.board_item_assignments bia
    JOIN public.members m ON m.id = bia.member_id
    WHERE m.is_active = false
  LOOP
    v_anomaly_id := gen_random_uuid();
    INSERT INTO public.data_anomaly_log (id, anomaly_type, severity, member_id, description, auto_fixable, context)
    VALUES (v_anomaly_id, 'assignment_orphan', 'warning', v_rec.member_id,
      format('Inactive member %s still assigned to board item %s', v_rec.name, v_rec.item_id),
      true,
      jsonb_build_object('assignment_id', v_rec.assignment_id, 'item_id', v_rec.item_id));

    IF p_auto_fix THEN
      DELETE FROM public.board_item_assignments WHERE id = v_rec.assignment_id;
      UPDATE public.data_anomaly_log SET auto_fixed = true, fixed_at = now(), fixed_by = 'auto'
      WHERE id = v_anomaly_id;
      v_fixed := v_fixed || jsonb_build_object('type', 'assignment_orphan', 'member_id', v_rec.member_id);
    ELSE
      v_pending := v_pending || jsonb_build_object('type', 'assignment_orphan', 'member_id', v_rec.member_id);
    END IF;
  END LOOP;

  -- ─── 9. sla_config_missing ───
  FOR v_rec IN
    SELECT pb.id AS board_id, pb.title
    FROM public.project_boards pb
    WHERE pb.is_active = true
      AND NOT EXISTS (SELECT 1 FROM public.board_sla_config bsc WHERE bsc.board_id = pb.id)
  LOOP
    v_anomaly_id := gen_random_uuid();
    INSERT INTO public.data_anomaly_log (id, anomaly_type, severity, description, auto_fixable, context)
    VALUES (v_anomaly_id, 'sla_config_missing', 'warning',
      format('Active board "%s" has no SLA configuration', v_rec.title),
      true,
      jsonb_build_object('board_id', v_rec.board_id, 'board_title', v_rec.title));

    IF p_auto_fix THEN
      INSERT INTO public.board_sla_config (board_id) VALUES (v_rec.board_id)
      ON CONFLICT (board_id) DO NOTHING;
      UPDATE public.data_anomaly_log SET auto_fixed = true, fixed_at = now(), fixed_by = 'auto'
      WHERE id = v_anomaly_id;
      v_fixed := v_fixed || jsonb_build_object('type', 'sla_config_missing', 'board_id', v_rec.board_id);
    ELSE
      v_pending := v_pending || jsonb_build_object('type', 'sla_config_missing', 'board_id', v_rec.board_id);
    END IF;
  END LOOP;

  -- Build summary
  v_counts := jsonb_build_object(
    'total', array_length(v_fixed, 1) + array_length(v_pending, 1),
    'fixed', array_length(v_fixed, 1),
    'pending', array_length(v_pending, 1),
    'by_severity', (
      SELECT jsonb_build_object(
        'critical', count(*) FILTER (WHERE severity = 'critical'),
        'warning', count(*) FILTER (WHERE severity = 'warning'),
        'info', count(*) FILTER (WHERE severity = 'info')
      )
      FROM public.data_anomaly_log
      WHERE auto_fixed = false
    )
  );

  RETURN jsonb_build_object(
    'fixed', to_jsonb(v_fixed),
    'pending', to_jsonb(v_pending),
    'summary', v_counts
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_detect_data_anomalies(boolean) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_detect_data_anomalies(boolean) IS
  'Phase B'' V4 conversion (p60 Pacote H): manage_platform gate via can_by_member. Was V3 (superadmin OR manager/deputy_manager). search_path hardened to ''''.';

-- ============================================================
-- 3. admin_get_anomaly_report (search_path KEPT — body has unqualified refs)
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_get_anomaly_report();
CREATE OR REPLACE FUNCTION public.admin_get_anomaly_report()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public, pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_live_anomalies jsonb := '[]'::jsonb;
  v_count int;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- Rule 1: Active members without current cycle tag
  SELECT count(*) INTO v_count FROM members
  WHERE is_active = true AND current_cycle_active = true
  AND (cycles IS NULL OR array_length(cycles, 1) IS NULL OR NOT ('cycle3-2026' = ANY(cycles)));
  IF v_count > 0 THEN
    v_live_anomalies := v_live_anomalies || jsonb_build_object(
      'rule', 'active_without_cycle', 'severity', 'warning',
      'description', v_count || ' membros ativos sem tag cycle3-2026', 'count', v_count);
  END IF;

  -- Rule 2: Orphan tribe_id
  SELECT count(*) INTO v_count FROM members m
  WHERE m.is_active = true AND m.tribe_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM tribes t WHERE t.id = m.tribe_id);
  IF v_count > 0 THEN
    v_live_anomalies := v_live_anomalies || jsonb_build_object(
      'rule', 'orphan_tribe_id', 'severity', 'critical',
      'description', v_count || ' membros com tribe_id inexistente', 'count', v_count);
  END IF;

  -- Rule 3: Events without attendance (exclude interviews/1on1, only >3 days old)
  SELECT count(*) INTO v_count FROM events e
  WHERE e.date < current_date - 3 AND e.date >= '2026-01-01'
  AND e.type NOT IN ('entrevista', '1on1')
  AND NOT EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id);
  IF v_count > 0 THEN
    v_live_anomalies := v_live_anomalies || jsonb_build_object(
      'rule', 'events_no_attendance', 'severity', 'warning',
      'description', v_count || ' eventos (tribo/geral) sem registro de presença', 'count', v_count);
  END IF;

  -- Rule 4: Duplicate emails
  SELECT count(*) INTO v_count FROM (
    SELECT lower(email) FROM members WHERE email IS NOT NULL GROUP BY lower(email) HAVING count(*) > 1
  ) sub;
  IF v_count > 0 THEN
    v_live_anomalies := v_live_anomalies || jsonb_build_object(
      'rule', 'duplicate_emails', 'severity', 'critical',
      'description', v_count || ' emails duplicados na tabela members', 'count', v_count);
  END IF;

  -- Rule 5: Active but offboarded
  SELECT count(*) INTO v_count FROM members WHERE is_active = true AND offboarded_at IS NOT NULL;
  IF v_count > 0 THEN
    v_live_anomalies := v_live_anomalies || jsonb_build_object(
      'rule', 'active_but_offboarded', 'severity', 'critical',
      'description', v_count || ' membros ativos com data de offboarding', 'count', v_count);
  END IF;

  -- Rule 6: Stale partner follow-ups
  SELECT count(*) INTO v_count FROM partner_entities
  WHERE follow_up_date IS NOT NULL AND follow_up_date < current_date - 7
  AND status NOT IN ('active', 'declined', 'inactive');
  IF v_count > 0 THEN
    v_live_anomalies := v_live_anomalies || jsonb_build_object(
      'rule', 'stale_partner_followups', 'severity', 'info',
      'description', v_count || ' parceiros com follow-up vencido >7 dias', 'count', v_count);
  END IF;

  -- Rule 7: Members without tribe assignment (operational roles only)
  SELECT count(*) INTO v_count FROM members
  WHERE is_active = true AND current_cycle_active = true AND tribe_id IS NULL
  AND operational_role IN ('researcher', 'tribe_leader', 'communicator', 'facilitator');
  IF v_count > 0 THEN
    v_live_anomalies := v_live_anomalies || jsonb_build_object(
      'rule', 'no_tribe_assigned', 'severity', 'warning',
      'description', v_count || ' pesquisadores/líderes ativos sem tribo atribuída', 'count', v_count);
  END IF;

  SELECT jsonb_build_object(
    'live_detection', v_live_anomalies,
    'pending', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', d.id, 'anomaly_type', d.anomaly_type, 'severity', d.severity,
        'description', d.description, 'context', d.context, 'detected_at', d.detected_at
      ) ORDER BY CASE d.severity WHEN 'critical' THEN 0 WHEN 'warning' THEN 1 ELSE 2 END, d.detected_at DESC)
      FROM public.data_anomaly_log d WHERE d.auto_fixed = false
    ), '[]'::jsonb),
    'summary', jsonb_build_object(
      'total_live', jsonb_array_length(v_live_anomalies),
      'total_logged_pending', (SELECT count(*) FROM public.data_anomaly_log WHERE auto_fixed = false),
      'total_fixed', (SELECT count(*) FROM public.data_anomaly_log WHERE auto_fixed = true)
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_get_anomaly_report() FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_get_anomaly_report() IS
  'Phase B'' V4 conversion (p60 Pacote H): manage_platform gate via can_by_member. Was V3 (superadmin OR manager/deputy_manager). search_path KEPT as ''public, pg_temp'' (body has unqualified references; full-qualify refactor out of scope).';

-- ============================================================
-- 4. admin_resolve_anomaly (search_path hardened)
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_resolve_anomaly(uuid, text);
CREATE OR REPLACE FUNCTION public.admin_resolve_anomaly(p_anomaly_id uuid, p_notes text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_name text;
BEGIN
  SELECT id, name INTO v_caller_id, v_caller_name FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  UPDATE public.data_anomaly_log
  SET auto_fixed = true,
      fixed_at = now(),
      fixed_by = v_caller_name,
      context = context || jsonb_build_object('resolution_notes', p_notes)
  WHERE id = p_anomaly_id AND auto_fixed = false;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Anomaly not found or already resolved');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_resolve_anomaly(uuid, text) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_resolve_anomaly(uuid, text) IS
  'Phase B'' V4 conversion (p60 Pacote H): manage_platform gate via can_by_member. Was V3 (superadmin OR manager/deputy_manager). search_path hardened to ''''.';

-- ============================================================
-- 5. admin_run_portfolio_data_sanity (search_path hardened)
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_run_portfolio_data_sanity();
CREATE OR REPLACE FUNCTION public.admin_run_portfolio_data_sanity()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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
$$;
REVOKE EXECUTE ON FUNCTION public.admin_run_portfolio_data_sanity() FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_run_portfolio_data_sanity() IS
  'Phase B'' V4 conversion (p60 Pacote H): manage_platform gate via can_by_member. Was V3 (superadmin OR manager/deputy_manager). search_path hardened to ''''.';

-- ============================================================
-- 6. admin_update_application (search_path KEPT — body has unqualified refs)
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_update_application(uuid, jsonb);
CREATE OR REPLACE FUNCTION public.admin_update_application(p_application_id uuid, p_data jsonb)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public, pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_name text;
  v_app record;
  v_old_status text;
  v_new_status text;
BEGIN
  SELECT id, name INTO v_caller_id, v_caller_name FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN json_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN RETURN json_build_object('error', 'Application not found'); END IF;

  v_old_status := v_app.status;
  v_new_status := coalesce(p_data->>'status', v_old_status);

  -- Update application fields
  UPDATE selection_applications SET
    status = v_new_status,
    feedback = coalesce(p_data->>'feedback', feedback),
    tags = CASE WHEN p_data ? 'tags' THEN ARRAY(SELECT jsonb_array_elements_text(p_data->'tags')) ELSE tags END,
    role_applied = coalesce(p_data->>'role_applied', role_applied),
    converted_from = CASE WHEN p_data ? 'converted_from' THEN p_data->>'converted_from' ELSE converted_from END,
    converted_to = CASE WHEN p_data ? 'converted_to' THEN p_data->>'converted_to' ELSE converted_to END,
    conversion_reason = CASE WHEN p_data ? 'conversion_reason' THEN p_data->>'conversion_reason' ELSE conversion_reason END,
    updated_at = now()
  WHERE id = p_application_id;

  -- If status changed to approved: validate partner chapter + seed onboarding
  IF v_new_status = 'approved' AND v_old_status != 'approved' THEN
    -- Check partner chapter
    IF NOT EXISTS (
      SELECT 1 FROM selection_membership_snapshots sms
      WHERE sms.application_id = p_application_id AND sms.is_partner_chapter = true
    ) THEN
      -- Don't block, just flag
      UPDATE selection_applications SET
        tags = array_append(tags, 'no_partner_chapter')
      WHERE id = p_application_id AND NOT ('no_partner_chapter' = ANY(tags));
    END IF;

    -- Seed pre-onboarding steps if member_id exists
    IF v_app.email IS NOT NULL THEN
      DECLARE v_member_id uuid;
      BEGIN
        SELECT id INTO v_member_id FROM members WHERE email = v_app.email LIMIT 1;
        IF v_member_id IS NOT NULL THEN
          -- Seed pre-onboarding steps directly
          INSERT INTO onboarding_progress (application_id, member_id, step_key, status, sla_deadline, metadata)
          SELECT p_application_id, v_member_id, s.key, 'pending',
                 now() + (s.sla || ' days')::interval,
                 jsonb_build_object('xp', s.xp, 'phase', 'pre_onboarding')
          FROM (VALUES
            ('create_account', 50, 7), ('setup_credly', 75, 14),
            ('explore_platform', 50, 14), ('read_blog', 50, 14), ('start_pmi_certs', 150, 30)
          ) AS s(key, xp, sla)
          WHERE NOT EXISTS (
            SELECT 1 FROM onboarding_progress WHERE member_id = v_member_id AND step_key = s.key
          );
          -- Auto-detect immediately
          PERFORM check_pre_onboarding_auto_steps(v_member_id);
        END IF;
      END;
    END IF;
  END IF;

  -- Log audit
  INSERT INTO data_anomaly_log (anomaly_type, severity, message, details)
  VALUES ('selection_status_change', 'info',
    'Application ' || v_app.applicant_name || ': ' || v_old_status || ' → ' || v_new_status,
    jsonb_build_object('application_id', p_application_id, 'old_status', v_old_status, 'new_status', v_new_status, 'actor', v_caller_name)
  );

  RETURN json_build_object('success', true, 'old_status', v_old_status, 'new_status', v_new_status);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_update_application(uuid, jsonb) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_update_application(uuid, jsonb) IS
  'Phase B'' V4 conversion (p60 Pacote H): manage_platform gate via can_by_member. Was V3 (superadmin OR manager/deputy_manager). search_path KEPT as ''public, pg_temp'' (body has unqualified references including check_pre_onboarding_auto_steps function call; full-qualify refactor out of scope).';

-- ============================================================
-- 7. admin_manage_cycle (search_path hardened)
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_manage_cycle(text, text, text, text, date, date, text, integer);
CREATE OR REPLACE FUNCTION public.admin_manage_cycle(
  p_action text, p_cycle_code text, p_label text, p_abbr text,
  p_start date, p_end date, p_color text, p_sort integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'access_denied'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  IF p_action = 'create' THEN
    INSERT INTO public.cycles (cycle_code, cycle_label, cycle_abbr, cycle_start, cycle_end, cycle_color, sort_order)
    VALUES (p_cycle_code, p_label, p_abbr, p_start, p_end, COALESCE(p_color, '#94A3B8'), COALESCE(p_sort, 0));
    v_result := jsonb_build_object('ok', true, 'action', 'created', 'cycle_code', p_cycle_code);

  ELSIF p_action = 'update' THEN
    UPDATE public.cycles SET
      cycle_label = COALESCE(p_label, cycle_label),
      cycle_abbr  = COALESCE(p_abbr, cycle_abbr),
      cycle_start = COALESCE(p_start, cycle_start),
      cycle_end   = COALESCE(p_end, cycle_end),
      cycle_color = COALESCE(p_color, cycle_color),
      sort_order  = COALESCE(p_sort, sort_order)
    WHERE cycle_code = p_cycle_code;
    IF NOT FOUND THEN RAISE EXCEPTION 'cycle_not_found'; END IF;
    v_result := jsonb_build_object('ok', true, 'action', 'updated', 'cycle_code', p_cycle_code);

  ELSIF p_action = 'delete' THEN
    IF EXISTS (SELECT 1 FROM public.cycles WHERE cycle_code = p_cycle_code AND is_current = true) THEN
      RAISE EXCEPTION 'cannot_delete_current_cycle';
    END IF;
    DELETE FROM public.cycles WHERE cycle_code = p_cycle_code;
    IF NOT FOUND THEN RAISE EXCEPTION 'cycle_not_found'; END IF;
    v_result := jsonb_build_object('ok', true, 'action', 'deleted', 'cycle_code', p_cycle_code);

  ELSIF p_action = 'set_current' THEN
    UPDATE public.cycles SET is_current = false WHERE is_current = true;
    UPDATE public.cycles SET is_current = true WHERE cycle_code = p_cycle_code;
    IF NOT FOUND THEN RAISE EXCEPTION 'cycle_not_found'; END IF;
    v_result := jsonb_build_object('ok', true, 'action', 'set_current', 'cycle_code', p_cycle_code);

  ELSE
    RAISE EXCEPTION 'invalid_action';
  END IF;

  RETURN v_result;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_manage_cycle(text, text, text, text, date, date, text, integer) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_manage_cycle(text, text, text, text, date, date, text, integer) IS
  'Phase B'' V4 conversion (p60 Pacote H): manage_platform gate via can_by_member. Was V3 (superadmin OR manager/deputy_manager). search_path hardened to ''''.';

-- ============================================================
-- 8. exec_chapter_comparison (search_path KEPT — body has unqualified refs)
-- ============================================================
DROP FUNCTION IF EXISTS public.exec_chapter_comparison();
CREATE OR REPLACE FUNCTION public.exec_chapter_comparison()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public, pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'access_denied'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  SELECT jsonb_agg(row_to_json(r)) INTO v_result
  FROM (
    SELECT
      m.chapter,
      count(*) AS total_members,
      count(*) FILTER (WHERE m.current_cycle_active) AS active_members,
      count(*) FILTER (WHERE m.cpmai_certified) AS cpmai_certified,
      COALESCE((SELECT count(*) FROM board_item_assignments bia2
        JOIN board_items bi2 ON bi2.id = bia2.item_id
        WHERE bia2.member_id = ANY(array_agg(m.id))
        AND bi2.curation_status = 'approved'), 0) AS articles_approved,
      COALESCE((SELECT count(DISTINCT a2.event_id) FROM attendance a2
        WHERE a2.member_id = ANY(array_agg(m.id))
        AND a2.present = true), 0) AS attendance_events
    FROM members m
    WHERE m.chapter IS NOT NULL
    GROUP BY m.chapter
    ORDER BY count(*) FILTER (WHERE m.current_cycle_active) DESC
  ) r;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.exec_chapter_comparison() FROM PUBLIC, anon;
COMMENT ON FUNCTION public.exec_chapter_comparison() IS
  'Phase B'' V4 conversion (p60 Pacote H): manage_platform gate via can_by_member. Was V3 (superadmin OR manager/deputy_manager). search_path KEPT as ''public, pg_temp'' (body has unqualified references; full-qualify refactor out of scope).';

NOTIFY pgrst, 'reload schema';
