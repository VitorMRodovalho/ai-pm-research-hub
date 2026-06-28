-- #301 / ADR-0108: SECDEF RPCs for curation Drive grants.
-- EF-facing (service-role only) + human-facing (curate_content / manage_platform).

-- ============ EF-facing — service-role only ============

CREATE OR REPLACE FUNCTION public.get_curation_grant_row(p_grant_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_row public.drive_curation_grants;
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;
  SELECT * INTO v_row FROM public.drive_curation_grants WHERE id = p_grant_id;
  IF v_row.id IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object(
    'id', v_row.id, 'status', v_row.status, 'drive_file_id', v_row.drive_file_id,
    'permission_id', v_row.permission_id, 'permission_email', v_row.permission_email::text,
    'role', v_row.role, 'board_item_id', v_row.board_item_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_curation_grant_done(
  p_grant_id uuid, p_status text, p_permission_id text DEFAULT NULL, p_api_error jsonb DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_row public.drive_curation_grants;
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;
  IF p_status NOT IN ('granted','failed') THEN RAISE EXCEPTION 'invalid terminal status: %', p_status; END IF;

  -- Idempotency guard: act only on a still-open pending_grant row (drain cron may race itself).
  UPDATE public.drive_curation_grants
     SET status = p_status,
         permission_id = CASE WHEN p_status = 'granted' THEN p_permission_id ELSE permission_id END,
         granted_at = CASE WHEN p_status = 'granted' THEN now() ELSE granted_at END,
         api_error = p_api_error,
         last_dispatched_at = now(),
         updated_at = now()
   WHERE id = p_grant_id AND status = 'pending_grant'
   RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    SELECT * INTO v_row FROM public.drive_curation_grants WHERE id = p_grant_id;
    IF v_row.id IS NULL THEN RAISE EXCEPTION 'Grant row % not found', p_grant_id; END IF;
    RETURN jsonb_build_object('grant_id', v_row.id, 'status', v_row.status, 'noop', true);
  END IF;

  IF p_status = 'granted' THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (NULL, 'drive_curation_grant_created', 'drive_curation_grants', v_row.id,
            jsonb_build_object('status_after', p_status),
            jsonb_build_object('drive_file_id', v_row.drive_file_id, 'permission_id', v_row.permission_id,
                               'board_item_id', v_row.board_item_id, 'grantee_member_id', v_row.grantee_member_id));
  END IF;
  RETURN jsonb_build_object('grant_id', v_row.id, 'status', v_row.status);
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_curation_grant_revoked(
  p_grant_id uuid, p_status text, p_api_error jsonb DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_row public.drive_curation_grants;
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;
  IF p_status NOT IN ('revoked','revoke_failed') THEN RAISE EXCEPTION 'invalid terminal status: %', p_status; END IF;

  UPDATE public.drive_curation_grants
     SET status = p_status,
         api_error = p_api_error,
         revoked_at = CASE WHEN p_status = 'revoked' THEN now() ELSE revoked_at END,
         last_dispatched_at = now(),
         updated_at = now()
   WHERE id = p_grant_id AND status = 'pending_revoke'
   RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    SELECT * INTO v_row FROM public.drive_curation_grants WHERE id = p_grant_id;
    IF v_row.id IS NULL THEN RAISE EXCEPTION 'Grant row % not found', p_grant_id; END IF;
    RETURN jsonb_build_object('grant_id', v_row.id, 'status', v_row.status, 'noop', true);
  END IF;

  IF p_status = 'revoked' THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (NULL, 'drive_curation_grant_revoked', 'drive_curation_grants', v_row.id,
            jsonb_build_object('status_after', p_status),
            jsonb_build_object('drive_file_id', v_row.drive_file_id, 'permission_id', v_row.permission_id,
                               'board_item_id', v_row.board_item_id, 'grantee_member_id', v_row.grantee_member_id));
  END IF;
  RETURN jsonb_build_object('grant_id', v_row.id, 'status', v_row.status);
END;
$$;

-- ============ Human-facing: status (consumed by #201 modal / #190 queue) ============
-- Gate: curate_content (curators) OR manage_platform (GP). Confidential carve-out (#785).
-- PII-clean: exposes grantee NAMES + counts, never emails (those are GP-only via admin_list).
CREATE OR REPLACE FUNCTION public.get_board_item_drive_access(p_board_item_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE
  v_caller members%rowtype;
  v_item   board_items%rowtype;
  v_files  jsonb;
  v_overall text;
  v_file_count int;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (public.can_by_member(v_caller.id, 'curate_content')
          OR public.can_by_member(v_caller.id, 'manage_platform')) THEN
    RAISE EXCEPTION 'Unauthorized: curate_content or manage_platform required';
  END IF;

  SELECT * INTO v_item FROM public.board_items WHERE id = p_board_item_id;
  IF v_item.id IS NULL THEN RAISE EXCEPTION 'Card not found'; END IF;
  IF NOT public.rls_can_see_board(v_item.board_id) THEN RAISE EXCEPTION 'Card not found'; END IF;  -- #785

  SELECT count(*) INTO v_file_count
  FROM public.board_item_files f
  WHERE f.board_item_id = p_board_item_id AND f.deleted_at IS NULL;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'drive_file_id', f.drive_file_id,
           'drive_file_url', f.drive_file_url,
           'filename', f.filename,
           'drive_permission_status',
             CASE WHEN coalesce(g.error_count,0) > 0 THEN 'error'
                  WHEN coalesce(g.pending_count,0) > 0 THEN 'pending'
                  WHEN coalesce(g.granted_count,0) > 0 THEN 'ready'
                  ELSE 'pending' END,
           'grant_role', 'commenter',
           'granted_count', coalesce(g.granted_count,0),
           'pending_count', coalesce(g.pending_count,0),
           'error_count', coalesce(g.error_count,0),
           'grantees', coalesce(g.grantees, '[]'::jsonb),
           'errors', coalesce(g.errors, '[]'::jsonb)
         ) ORDER BY f.created_at), '[]'::jsonb)
  INTO v_files
  FROM public.board_item_files f
  LEFT JOIN LATERAL (
    SELECT
      count(*) FILTER (WHERE dg.status = 'granted')                          AS granted_count,
      count(*) FILTER (WHERE dg.status = 'pending_grant')                    AS pending_count,
      count(*) FILTER (WHERE dg.status IN ('failed','revoke_failed'))        AS error_count,
      coalesce(jsonb_agg(DISTINCT m.name) FILTER (WHERE dg.status = 'granted'), '[]'::jsonb) AS grantees,
      coalesce(jsonb_agg(DISTINCT (dg.api_error->>'message'))
               FILTER (WHERE dg.status IN ('failed','revoke_failed') AND dg.api_error IS NOT NULL), '[]'::jsonb) AS errors
    FROM public.drive_curation_grants dg
    JOIN public.members m ON m.id = dg.grantee_member_id
    WHERE dg.drive_file_id = f.drive_file_id AND dg.board_item_id = p_board_item_id
  ) g ON true
  WHERE f.board_item_id = p_board_item_id AND f.deleted_at IS NULL;

  v_overall := CASE
    WHEN v_file_count = 0 THEN 'missing'
    WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(v_files) e WHERE e->>'drive_permission_status' = 'error')   THEN 'error'
    WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(v_files) e WHERE e->>'drive_permission_status' = 'pending') THEN 'pending'
    ELSE 'ready' END;

  RETURN jsonb_build_object(
    'board_item_id', p_board_item_id,
    'curation_status', v_item.curation_status,
    'overall_status', v_overall,
    'missing_drive_access', (v_file_count = 0),
    'expires_or_revokes_on', v_item.curation_due_at,
    'files', v_files);
END;
$$;

-- ============ Human-facing: GP observability + manual remediation (manage_platform) ============
CREATE OR REPLACE FUNCTION public.admin_list_curation_drive_grants(
  p_status text DEFAULT NULL, p_board_item_id uuid DEFAULT NULL, p_limit int DEFAULT 50, p_offset int DEFAULT 0
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_rows jsonb;
  v_member_ids uuid[];
  v_limit int := least(greatest(coalesce(p_limit,50),1),200);
  v_offset int := greatest(coalesce(p_offset,0),0);
BEGIN
  v_caller_id := (SELECT id FROM public.members WHERE auth_id = auth.uid());
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: manage_platform required';
  END IF;

  WITH page AS (
    SELECT g.*, m.name AS grantee_name
    FROM public.drive_curation_grants g
    JOIN public.members m ON m.id = g.grantee_member_id
    WHERE (p_status IS NULL OR g.status = p_status)
      AND (p_board_item_id IS NULL OR g.board_item_id = p_board_item_id)
    ORDER BY g.created_at DESC
    LIMIT v_limit OFFSET v_offset
  )
  SELECT
    coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'board_item_id', board_item_id, 'grantee_member_id', grantee_member_id,
      'grantee_name', grantee_name, 'permission_email', permission_email::text,
      'drive_file_id', drive_file_id, 'drive_file_url', drive_file_url, 'permission_id', permission_id,
      'role', role, 'grant_reason', grant_reason, 'status', status, 'api_error', api_error,
      'requested_at', requested_at, 'granted_at', granted_at, 'revoked_at', revoked_at
    ) ORDER BY created_at DESC), '[]'::jsonb),
    coalesce(array_agg(DISTINCT grantee_member_id), ARRAY[]::uuid[])
  INTO v_rows, v_member_ids
  FROM page;

  IF cardinality(v_member_ids) > 0 THEN
    PERFORM public.log_pii_access_batch(v_member_ids, ARRAY['email'],
      'admin_list_curation_drive_grants', 'GP review of curation Drive grant ledger');
  END IF;

  RETURN jsonb_build_object('rows', v_rows, 'count', jsonb_array_length(v_rows));
END;
$$;

CREATE OR REPLACE FUNCTION public.force_grant_curation_drive_access(p_board_item_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_caller_id uuid; v_ids uuid[];
BEGIN
  v_caller_id := (SELECT id FROM public.members WHERE auth_id = auth.uid());
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: manage_platform required';
  END IF;

  PERFORM public.enqueue_curation_drive_grants(p_board_item_id);

  SELECT coalesce(array_agg(id), ARRAY[]::uuid[]) INTO v_ids
  FROM public.drive_curation_grants
  WHERE board_item_id = p_board_item_id AND status = 'pending_grant';

  RETURN jsonb_build_object('board_item_id', p_board_item_id, 'pending_count', cardinality(v_ids),
                            'grant_ids', to_jsonb(v_ids));
END;
$$;

CREATE OR REPLACE FUNCTION public.force_revoke_curation_drive_access(p_board_item_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_caller_id uuid; v_ids uuid[];
BEGIN
  v_caller_id := (SELECT id FROM public.members WHERE auth_id = auth.uid());
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: manage_platform required';
  END IF;

  PERFORM public.enqueue_curation_drive_revokes(p_board_item_id);

  SELECT coalesce(array_agg(id), ARRAY[]::uuid[]) INTO v_ids
  FROM public.drive_curation_grants
  WHERE board_item_id = p_board_item_id AND status = 'pending_revoke';

  RETURN jsonb_build_object('board_item_id', p_board_item_id, 'pending_revoke_count', cardinality(v_ids),
                            'grant_ids', to_jsonb(v_ids));
END;
$$;

-- ===== Grants =====
-- Human-facing (authenticated callers; gate is inside each function body).
REVOKE ALL ON FUNCTION public.get_board_item_drive_access(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_board_item_drive_access(uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_list_curation_drive_grants(text,uuid,int,int) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_list_curation_drive_grants(text,uuid,int,int) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.force_grant_curation_drive_access(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.force_grant_curation_drive_access(uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.force_revoke_curation_drive_access(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.force_revoke_curation_drive_access(uuid) TO authenticated, service_role;

-- EF-facing — service-role only.
REVOKE ALL ON FUNCTION public.get_curation_grant_row(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.get_curation_grant_row(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.mark_curation_grant_done(uuid,text,text,jsonb) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.mark_curation_grant_done(uuid,text,text,jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.mark_curation_grant_revoked(uuid,text,jsonb) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.mark_curation_grant_revoked(uuid,text,jsonb) TO service_role;

-- Enqueue helpers + trigger fn (from mig 266) are internal — service-role only, never client-callable.
REVOKE ALL ON FUNCTION public.enqueue_curation_drive_grants(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.enqueue_curation_drive_grants(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.enqueue_curation_drive_grant_for_member(uuid,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.enqueue_curation_drive_grant_for_member(uuid,uuid,text) TO service_role;
REVOKE ALL ON FUNCTION public.enqueue_curation_drive_revokes(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.enqueue_curation_drive_revokes(uuid) TO service_role;

NOTIFY pgrst, 'reload schema';
