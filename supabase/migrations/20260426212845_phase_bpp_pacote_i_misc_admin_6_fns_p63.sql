-- Phase B'' Pacote I (p63) — 6 misc admin fns V3→V4 manage_platform
-- Discovered post-Pacote-H by 75-fn surface audit (categorization in
-- handoff p64). Sub-categorized A_admin_broad (25) into 5 sub-types:
--   A0 clean (5 fns + 1 overload) ← THIS BATCH
--   A2 partner_designations (8) — needs manage_partner action ADR
--   A4 other_designations (7) — needs new V4 actions per domain
--   A5 tribe_leader_no_scope (5) — per-fn inspection
--
-- Privilege expansion safety check (verified pre-apply):
--   V3 tight (5): 2 / V3 broad (1): 2 / V3 super-only (1): 2
--   V4 manage_platform: 2 (same — superadmin override)
--   would_gain: [] / would_lose: []
--
-- search_path partial hardening per Pacote H pattern: 5 hardened,
-- 1 (platform_activity_summary) KEEP because of unqualified refs in
-- aggregate query (events, broadcast_log, comms_metrics, etc.).

-- ============================================================
-- 1. delete_pilot(uuid)
-- ============================================================
DROP FUNCTION IF EXISTS public.delete_pilot(uuid);
CREATE OR REPLACE FUNCTION public.delete_pilot(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  DELETE FROM public.pilots WHERE id = p_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Pilot not found'); END IF;
  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.delete_pilot(uuid) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.delete_pilot(uuid) IS
  'Phase B'' V4 conversion (p63 Pacote I): manage_platform via can_by_member. Was V3 (superadmin OR manager/deputy_manager). search_path hardened.';

-- ============================================================
-- 2. delete_tag(uuid)
-- ============================================================
DROP FUNCTION IF EXISTS public.delete_tag(uuid);
CREATE OR REPLACE FUNCTION public.delete_tag(p_tag_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_tag record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_tag FROM public.tags WHERE id = p_tag_id;
  IF v_tag IS NULL THEN RAISE EXCEPTION 'Tag not found'; END IF;
  IF v_tag.tier = 'system' THEN RAISE EXCEPTION 'System tags cannot be deleted'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Only admins/GP can delete tags';
  END IF;

  DELETE FROM public.tags WHERE id = p_tag_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.delete_tag(uuid) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.delete_tag(uuid) IS
  'Phase B'' V4 conversion (p63 Pacote I): manage_platform via can_by_member. Was V3 (superadmin OR manager/deputy_manager). search_path hardened.';

-- ============================================================
-- 3. get_site_config()
-- ============================================================
DROP FUNCTION IF EXISTS public.get_site_config();
CREATE OR REPLACE FUNCTION public.get_site_config()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Insufficient permissions'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;
  RETURN (SELECT COALESCE(json_object_agg(key, value), '{}'::JSON) FROM public.site_config);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_site_config() FROM PUBLIC, anon;
COMMENT ON FUNCTION public.get_site_config() IS
  'Phase B'' V4 conversion (p63 Pacote I): manage_platform via can_by_member. Was V3 broad (superadmin OR manager/deputy_manager OR co_gp designation). search_path hardened.';

-- ============================================================
-- 4. platform_activity_summary() — search_path KEPT (unqualified refs)
-- ============================================================
DROP FUNCTION IF EXISTS public.platform_activity_summary();
CREATE OR REPLACE FUNCTION public.platform_activity_summary()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public, pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_result JSON;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Insufficient permissions'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;

  SELECT json_build_object(
    'members', (SELECT json_build_object(
      'total', COUNT(*), 'active', COUNT(*) FILTER (WHERE current_cycle_active),
      'with_tribe', COUNT(*) FILTER (WHERE tribe_id IS NOT NULL),
      'with_credly', COUNT(*) FILTER (WHERE credly_url IS NOT NULL AND credly_url != ''),
      'with_photo', COUNT(*) FILTER (WHERE photo_url IS NOT NULL AND photo_url != ''),
      'with_linkedin', COUNT(*) FILTER (WHERE linkedin_url IS NOT NULL AND linkedin_url != '')
    ) FROM members WHERE is_active = TRUE AND current_cycle_active = TRUE),
    'artifacts', (SELECT json_build_object(
      'total', COUNT(*),
      'published', COUNT(*) FILTER (WHERE status = 'published'::submission_status),
      'pending', COUNT(*) FILTER (WHERE status = 'under_review'::submission_status)
    ) FROM publication_submissions),
    'events', (SELECT json_build_object(
      'total', COUNT(*), 'this_month', COUNT(*) FILTER (WHERE event_date >= date_trunc('month', CURRENT_DATE)),
      'calendar_imported', COUNT(*) FILTER (WHERE source = 'calendar_import')
    ) FROM events),
    'boards', (SELECT json_build_object(
      'total_boards', (SELECT COUNT(*) FROM project_boards WHERE is_active),
      'total_items', COUNT(*), 'in_progress', COUNT(*) FILTER (WHERE status = 'in_progress'),
      'done', COUNT(*) FILTER (WHERE status = 'done')
    ) FROM board_items),
    'comms', (SELECT json_build_object(
      'total_entries', COUNT(*), 'total_reach', COALESCE(SUM(reach), 0),
      'total_engagement', COALESCE(SUM(engagement), 0)
    ) FROM comms_metrics),
    'volunteer_apps', (SELECT json_build_object(
      'total', COUNT(*), 'matched', COUNT(*) FILTER (WHERE is_existing_member),
      'cycles', COUNT(DISTINCT cycle)
    ) FROM volunteer_applications),
    'monthly_activity', (
      SELECT COALESCE(json_agg(row_to_json(ma)), '[]'::JSON) FROM (
        SELECT m AS month_label, COALESCE(e_cnt, 0) AS events,
          COALESCE(a_cnt, 0) AS artifacts, COALESCE(b_cnt, 0) AS broadcasts
        FROM generate_series(date_trunc('month', CURRENT_DATE) - INTERVAL '5 months',
          date_trunc('month', CURRENT_DATE), '1 month') AS s(m)
        LEFT JOIN (SELECT date_trunc('month', event_date) AS mo, COUNT(*) AS e_cnt FROM events GROUP BY 1) ev ON ev.mo = s.m
        LEFT JOIN (SELECT date_trunc('month', created_at) AS mo, COUNT(*) AS a_cnt FROM publication_submissions GROUP BY 1) ar ON ar.mo = s.m
        LEFT JOIN (SELECT date_trunc('month', sent_at) AS mo, COUNT(*) AS b_cnt FROM broadcast_log WHERE status = 'sent' GROUP BY 1) bc ON bc.mo = s.m
        ORDER BY m) ma)
  ) INTO v_result;
  RETURN v_result;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.platform_activity_summary() FROM PUBLIC, anon;
COMMENT ON FUNCTION public.platform_activity_summary() IS
  'Phase B'' V4 conversion (p63 Pacote I): manage_platform via can_by_member. Was V3 broad (superadmin OR manager/deputy_manager OR co_gp). search_path KEPT (body has unqualified refs to events, broadcast_log, etc.).';

-- ============================================================
-- 5. set_site_config(text, text) — overload 1
-- ============================================================
DROP FUNCTION IF EXISTS public.set_site_config(text, text);
CREATE OR REPLACE FUNCTION public.set_site_config(p_key text, p_value text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Admin access required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  INSERT INTO public.site_config (key, value, updated_at)
  VALUES (p_key, p_value, now())
  ON CONFLICT (key) DO UPDATE SET value = p_value, updated_at = now();
END;
$$;
REVOKE EXECUTE ON FUNCTION public.set_site_config(text, text) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.set_site_config(text, text) IS
  'Phase B'' V4 conversion (p63 Pacote I): manage_platform via can_by_member. Was V3 (superadmin OR manager/deputy_manager). search_path hardened.';

-- ============================================================
-- 6. set_site_config(text, jsonb) — overload 2 (was V3 superadmin-only — drift!)
-- ============================================================
DROP FUNCTION IF EXISTS public.set_site_config(text, jsonb);
CREATE OR REPLACE FUNCTION public.set_site_config(p_key text, p_value jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Superadmin only'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Superadmin only';
  END IF;

  INSERT INTO public.site_config (key, value, updated_at, updated_by)
  VALUES (p_key, p_value::text, now(), v_caller_id)
  ON CONFLICT (key) DO UPDATE SET
    value = EXCLUDED.value,
    updated_at = now(),
    updated_by = EXCLUDED.updated_by;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.set_site_config(text, jsonb) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.set_site_config(text, jsonb) IS
  'Phase B'' V4 conversion (p63 Pacote I): manage_platform via can_by_member. Was V3 superadmin-only (overload drift vs text variant). Now matches sibling overload. search_path hardened.';

NOTIFY pgrst, 'reload schema';
