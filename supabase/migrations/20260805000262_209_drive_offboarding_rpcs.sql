-- #209 / ADR-0107: SECDEF RPCs for the Drive offboarding revocation cascade.
-- GP-facing (manage_member gate, called via PostgREST/MCP) + EF-facing (service-role only).

-- ============ READ — GP (manage_member) ============
CREATE OR REPLACE FUNCTION public.admin_list_drive_revocation_audit(
  p_status text DEFAULT 'pending_revoke',
  p_member_id uuid DEFAULT NULL,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
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
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: manage_member required';
  END IF;

  WITH page AS (
    SELECT a.*, m.name AS member_name
    FROM public.drive_offboarding_audit a
    JOIN public.members m ON m.id = a.member_id
    WHERE (p_status IS NULL OR a.status = p_status)
      AND (p_member_id IS NULL OR a.member_id = p_member_id)
    ORDER BY a.detected_at DESC
    LIMIT v_limit OFFSET v_offset
  )
  SELECT
    coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'member_id', member_id, 'member_name', member_name,
      'permission_email', permission_email::text, 'drive_file_id', drive_file_id,
      'drive_file_name', drive_file_name, 'drive_file_url', drive_file_url,
      'is_shared_drive', is_shared_drive, 'permission_id', permission_id,
      'permission_role', permission_role, 'permission_type', permission_type,
      'status', status, 'google_error', google_error,
      'detected_at', detected_at, 'last_detected_at', last_detected_at,
      'approved_by', approved_by, 'approved_at', approved_at, 'revoked_at', revoked_at
    ) ORDER BY detected_at DESC), '[]'::jsonb),
    coalesce(array_agg(DISTINCT member_id), ARRAY[]::uuid[])
  INTO v_rows, v_member_ids
  FROM page;

  IF cardinality(v_member_ids) > 0 THEN
    PERFORM public.log_pii_access_batch(v_member_ids, ARRAY['email'],
      'admin_list_drive_revocation_audit', 'GP review of Drive offboarding revocation queue');
  END IF;

  RETURN jsonb_build_object('rows', v_rows, 'count', jsonb_array_length(v_rows));
END;
$$;

-- ============ APPROVE single — GP (manage_member) ============
CREATE OR REPLACE FUNCTION public.approve_drive_revocation(p_audit_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_caller_id uuid; v_row public.drive_offboarding_audit;
BEGIN
  v_caller_id := (SELECT id FROM public.members WHERE auth_id = auth.uid());
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: manage_member required';
  END IF;

  UPDATE public.drive_offboarding_audit
     SET status='approved', approved_by=v_caller_id, approved_at=now(), updated_at=now()
   WHERE id=p_audit_id AND status='pending_revoke'
   RETURNING * INTO v_row;

  IF NOT FOUND THEN
    SELECT * INTO v_row FROM public.drive_offboarding_audit WHERE id=p_audit_id;
    IF v_row.id IS NULL THEN RAISE EXCEPTION 'Audit row % not found', p_audit_id; END IF;
    RAISE EXCEPTION 'Audit row % not in pending_revoke (current: %)', p_audit_id, v_row.status;
  END IF;

  RETURN jsonb_build_object('audit_id', v_row.id, 'status', v_row.status,
    'drive_file_id', v_row.drive_file_id, 'permission_id', v_row.permission_id);
END;
$$;

-- ============ APPROVE bulk per member — GP (manage_member) ============
CREATE OR REPLACE FUNCTION public.bulk_approve_drive_revocations(p_member_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_caller_id uuid; v_ids uuid[];
BEGIN
  v_caller_id := (SELECT id FROM public.members WHERE auth_id = auth.uid());
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: manage_member required';
  END IF;

  WITH upd AS (
    UPDATE public.drive_offboarding_audit
       SET status='approved', approved_by=v_caller_id, approved_at=now(), updated_at=now()
     WHERE member_id=p_member_id AND status='pending_revoke'
     RETURNING id
  )
  SELECT coalesce(array_agg(id), ARRAY[]::uuid[]) INTO v_ids FROM upd;

  RETURN jsonb_build_object('member_id', p_member_id, 'approved_count', cardinality(v_ids),
                           'audit_ids', to_jsonb(v_ids));
END;
$$;

-- ============ EF-facing — service-role only ============

CREATE OR REPLACE FUNCTION public.get_offboarded_member_emails()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_rows jsonb; v_member_ids uuid[];
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;

  WITH emails AS (
    SELECT m.id AS member_id, lower(m.email) AS email
    FROM public.members m
    WHERE m.member_status IN ('inactive','alumni') AND m.offboarded_at IS NOT NULL
      AND m.email IS NOT NULL AND m.email <> ''
    UNION
    SELECT me.member_id, lower(me.email::text) AS email
    FROM public.member_emails me
    JOIN public.members m ON m.id = me.member_id
    WHERE m.member_status IN ('inactive','alumni') AND m.offboarded_at IS NOT NULL
      AND me.email IS NOT NULL
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('member_id', member_id, 'email', email)), '[]'::jsonb),
         coalesce(array_agg(DISTINCT member_id), ARRAY[]::uuid[])
  INTO v_rows, v_member_ids
  FROM emails;

  -- LGPD: system (cron) read of ex-member emails for the Drive scan. accessor_id NULL = system job.
  IF cardinality(v_member_ids) > 0 THEN
    INSERT INTO public.pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason)
    SELECT NULL, mid, ARRAY['email'], 'audit_drive_offboarding_access',
           'weekly drive permission scan: offboarded email match set'
    FROM unnest(v_member_ids) AS mid;
  END IF;

  RETURN v_rows;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_drive_revocation_candidates(p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE
  v_org uuid;
  v_inserted int := 0;
  v_refreshed int := 0;
  v_gp uuid;
  rec jsonb;
  v_is_new boolean;
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;
  v_org := (SELECT id FROM public.organizations ORDER BY created_at LIMIT 1);
  IF v_org IS NULL THEN RAISE EXCEPTION 'no organization configured'; END IF;

  FOR rec IN SELECT value FROM jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) AS value
  LOOP
    INSERT INTO public.drive_offboarding_audit (
      organization_id, member_id, drive_file_id, drive_file_name, drive_file_url,
      is_shared_drive, shared_drive_id, permission_id, permission_email,
      permission_role, permission_type, status
    ) VALUES (
      v_org,
      (rec->>'member_id')::uuid,
      rec->>'drive_file_id',
      rec->>'drive_file_name',
      rec->>'drive_file_url',
      coalesce((rec->>'is_shared_drive')::boolean, false),
      rec->>'shared_drive_id',
      rec->>'permission_id',
      (rec->>'permission_email')::citext,
      rec->>'permission_role',
      rec->>'permission_type',
      'pending_revoke'
    )
    ON CONFLICT (drive_file_id, permission_id) WHERE status IN ('pending_revoke','approved')
    DO UPDATE SET last_detected_at = now(), updated_at = now(),
                  drive_file_name = excluded.drive_file_name,
                  drive_file_url  = excluded.drive_file_url
    RETURNING (xmax = 0) INTO v_is_new;

    IF v_is_new THEN v_inserted := v_inserted + 1; ELSE v_refreshed := v_refreshed + 1; END IF;
  END LOOP;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (NULL, 'drive_permission_revocation_queued', 'drive_offboarding_audit', NULL,
          '{}'::jsonb,
          jsonb_build_object('inserted', v_inserted, 'refreshed', v_refreshed,
                             'candidates', jsonb_array_length(coalesce(p_rows,'[]'::jsonb))));

  IF v_inserted > 0 THEN
    FOR v_gp IN
      SELECT m.id FROM public.members m
      WHERE m.member_status='active'
        AND public.can_by_member(m.id,'manage_member')  -- V4 SSOT (ADR-0007/0011); no is_superadmin bypass
    LOOP
      -- Explicit casts disambiguate the 3 create_notification overloads (NULL link would be `unknown`).
      PERFORM public.create_notification(
        v_gp,
        'drive_offboarding_pending'::text,
        (v_inserted::text || ' permissao(oes) Drive de ex-membros aguardam revisao')::text,
        'O scan de offboarding encontrou acessos Drive de membros desligados. Revise via MCP (list_drive_revocation_pending) e aprove (approve_drive_revocation). Ainda sem UI dedicada (#209 backend+MCP).'::text,
        NULL::text,
        'drive_offboarding_audit'::text,
        NULL::uuid);
    END LOOP;
  END IF;

  RETURN jsonb_build_object('inserted', v_inserted, 'refreshed', v_refreshed);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_drive_revocation_row(p_audit_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_row public.drive_offboarding_audit;
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;
  SELECT * INTO v_row FROM public.drive_offboarding_audit WHERE id=p_audit_id;
  IF v_row.id IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object(
    'id', v_row.id, 'status', v_row.status, 'drive_file_id', v_row.drive_file_id,
    'permission_id', v_row.permission_id, 'permission_email', v_row.permission_email::text,
    'is_shared_drive', v_row.is_shared_drive, 'approved_by', v_row.approved_by);
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_drive_revocation_done(p_audit_id uuid, p_status text, p_google_error jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_row public.drive_offboarding_audit;
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;
  IF p_status NOT IN ('revoked','already_absent','failed') THEN
    RAISE EXCEPTION 'invalid terminal status: %', p_status;
  END IF;

  -- Idempotency guard: act only on a still-open row, so a concurrent caller (synchronous MCP approve +
  -- the drain cron) cannot overwrite an already-terminal outcome with a different status.
  UPDATE public.drive_offboarding_audit
     SET status = p_status,
         google_error = p_google_error,
         revoked_at = CASE WHEN p_status IN ('revoked','already_absent') THEN now() ELSE revoked_at END,
         updated_at = now()
   WHERE id = p_audit_id AND status IN ('approved','pending_revoke')
   RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    -- already terminal or missing → graceful no-op (no overwrite, no spurious audit row)
    SELECT * INTO v_row FROM public.drive_offboarding_audit WHERE id = p_audit_id;
    IF v_row.id IS NULL THEN RAISE EXCEPTION 'Audit row % not found', p_audit_id; END IF;
    RETURN jsonb_build_object('audit_id', v_row.id, 'status', v_row.status, 'noop', true);
  END IF;

  IF p_status IN ('revoked','already_absent') THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (v_row.approved_by, 'drive_permission_revoked', 'drive_offboarding_audit', v_row.id,
            jsonb_build_object('status_after', p_status),
            jsonb_build_object('drive_file_id', v_row.drive_file_id, 'permission_id', v_row.permission_id,
                               'member_id', v_row.member_id));
  END IF;

  RETURN jsonb_build_object('audit_id', v_row.id, 'status', v_row.status);
END;
$$;

-- ===== Grants =====
REVOKE ALL ON FUNCTION public.admin_list_drive_revocation_audit(text,uuid,int,int) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_list_drive_revocation_audit(text,uuid,int,int) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.approve_drive_revocation(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.approve_drive_revocation(uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.bulk_approve_drive_revocations(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.bulk_approve_drive_revocations(uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_offboarded_member_emails() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.get_offboarded_member_emails() TO service_role;
REVOKE ALL ON FUNCTION public.upsert_drive_revocation_candidates(jsonb) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.upsert_drive_revocation_candidates(jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.get_drive_revocation_row(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.get_drive_revocation_row(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.mark_drive_revocation_done(uuid,text,jsonb) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.mark_drive_revocation_done(uuid,text,jsonb) TO service_role;
