-- ============================================================
-- ADR-0042: view_chapter_dashboards V4 action + 8 reader gate additions + _can_manage_event V3→V4
-- Section A: catalog seed (3 rows for new view_chapter_dashboards action)
-- Section B: 7 standard readers + exec_tribe_dashboard get OR view_chapter_dashboards gate
-- Section C: _can_manage_event V3→V4 helper conversion
-- Cross-references: ADR-0007, ADR-0011 Amendment B, ADR-0030, ADR-0040
-- Rollback: revert this migration; helpers + readers re-apply prior bodies from earlier migrations
-- ============================================================

-- ── Section A: catalog seed ────────────────────────────────
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope) VALUES
  ('chapter_board', 'board_member', 'view_chapter_dashboards', 'organization'),
  ('chapter_board', 'liaison',      'view_chapter_dashboards', 'organization'),
  ('sponsor',       'sponsor',      'view_chapter_dashboards', 'organization')
ON CONFLICT (kind, role, action) DO NOTHING;

-- ── Section B: 7 standard readers — surgical gate replacement ────────
DO $migration_b1$
DECLARE
  v_fns text[] := ARRAY[
    'exec_all_tribes_summary',
    'get_cross_tribe_comparison',
    'exec_cycle_report',
    'get_admin_dashboard',
    'exec_cross_tribe_comparison',
    'get_adoption_dashboard',
    'get_campaign_analytics'
  ];
  v_fn text;
  v_def text;
  v_new text;
BEGIN
  FOREACH v_fn IN ARRAY v_fns
  LOOP
    SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = v_fn;

    IF v_def IS NULL THEN
      RAISE EXCEPTION 'Function not found: %', v_fn;
    END IF;

    v_new := replace(v_def,
      'IF NOT public.can_by_member(v_caller_id, ''manage_platform'') THEN
    RAISE EXCEPTION ''Unauthorized: requires manage_platform permission'';',
      '-- ADR-0042: V4 catalog (manage_platform writes; view_chapter_dashboards reads)
  IF NOT (public.can_by_member(v_caller_id, ''manage_platform'')
          OR public.can_by_member(v_caller_id, ''view_chapter_dashboards'')) THEN
    RAISE EXCEPTION ''Unauthorized: requires manage_platform or view_chapter_dashboards permission'';');

    IF v_new = v_def THEN
      RAISE EXCEPTION 'Gate pattern not matched in %; body may have drifted', v_fn;
    END IF;

    EXECUTE v_new;
  END LOOP;
END;
$migration_b1$;

-- ── Section B (cont.): exec_tribe_dashboard cross-tribe gate ───────
DO $migration_b2$
DECLARE
  v_def text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'exec_tribe_dashboard';

  IF v_def IS NULL THEN
    RAISE EXCEPTION 'Function exec_tribe_dashboard not found';
  END IF;

  v_new := replace(v_def,
    'IF v_caller_tribe_id IS DISTINCT FROM p_tribe_id
     AND NOT public.can_by_member(v_caller.id, ''manage_platform'') THEN
    RAISE EXCEPTION ''Unauthorized: cross-tribe view requires manage_platform permission'';',
    '-- ADR-0042: cross-tribe view = manage_platform OR view_chapter_dashboards (read-only catalog action)
  IF v_caller_tribe_id IS DISTINCT FROM p_tribe_id
     AND NOT public.can_by_member(v_caller.id, ''manage_platform'')
     AND NOT public.can_by_member(v_caller.id, ''view_chapter_dashboards'') THEN
    RAISE EXCEPTION ''Unauthorized: cross-tribe view requires manage_platform or view_chapter_dashboards permission'';');

  IF v_new = v_def THEN
    RAISE EXCEPTION 'Gate pattern not matched in exec_tribe_dashboard; body may have drifted';
  END IF;

  EXECUTE v_new;
END;
$migration_b2$;

-- ── Section C: _can_manage_event V3→V4 helper conversion ────────────
-- V3: is_superadmin OR operational_role IN ('manager','deputy_manager') OR tribe_scope OR creator
-- V4: can_by_member('manage_event') OR Path Y (tribe scope + creator preserved)
CREATE OR REPLACE FUNCTION public._can_manage_event(p_event_id uuid)
  RETURNS boolean
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_event record;
  v_event_tribe_id int;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN false; END IF;

  -- ADR-0042: V4 catalog source-of-truth for org-tier event management
  IF public.can_by_member(v_caller.id, 'manage_event') THEN RETURN true; END IF;

  -- Path Y: tribe-scoped management (tribe_leader / researcher own-tribe events)
  -- and event-creator self-management — preserved from V3 body.
  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;
  IF NOT FOUND THEN RETURN false; END IF;

  v_event_tribe_id := public.resolve_tribe_id(v_event.initiative_id);

  IF v_caller.operational_role = 'tribe_leader' AND v_event_tribe_id = v_caller.tribe_id THEN RETURN true; END IF;
  IF v_caller.operational_role = 'researcher'   AND v_event_tribe_id = v_caller.tribe_id THEN RETURN true; END IF;
  IF v_event.created_by = v_caller.id THEN RETURN true; END IF;
  RETURN false;
END;
$function$;

-- ── Cache reload ────────────────────────────
NOTIFY pgrst, 'reload schema';
