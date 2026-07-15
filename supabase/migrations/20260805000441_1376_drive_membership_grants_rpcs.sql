-- #1376 / ADR-0124: RPCs for the Drive membership auto-grant reconcile.
--
-- Split of responsibilities (mirror of #209): the EF (reconcile-initiative-drive-access) does the
-- Google-side work (listPermissions on the folder, POST the missing grants). These RPCs are the
-- DB-side surface: roster resolution (PII-logged), idempotent ledger upsert, missing-folder
-- detection + GP alert, and GP observability. All grant-side gates are manage_platform (GP), the
-- same authority that owns member lifecycle — Drive access follows membership.

-- ─────────────────────── EF-facing (service-role only) ───────────────────────

-- Workspace folders to reconcile: active initiatives with a live workspace link.
-- p_initiative_id null = the full sweep (cron); non-null = one initiative (provision / manual).
CREATE OR REPLACE FUNCTION public.get_membership_drive_targets(p_initiative_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_rows jsonb;
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'initiative_id', i.id,
           'initiative_title', i.title,
           'drive_link_id', l.id,
           'drive_folder_id', l.drive_folder_id,
           'drive_folder_url', l.drive_folder_url,
           'drive_folder_name', l.drive_folder_name
         )), '[]'::jsonb)
  INTO v_rows
  FROM public.initiatives i
  JOIN public.initiative_drive_links l
    ON l.initiative_id = i.id AND l.unlinked_at IS NULL AND l.link_purpose = 'workspace'
  WHERE i.status = 'active'
    AND (p_initiative_id IS NULL OR i.id = p_initiative_id);

  RETURN v_rows;
END;
$$;

-- Active roster of an initiative resolved to a member email (the POST grantee set).
-- LGPD: this is a system-side read of member emails for the Drive grant scan → logged with
-- accessor_id NULL (mirror of get_offboarded_member_emails).
CREATE OR REPLACE FUNCTION public.get_initiative_drive_roster(p_initiative_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_rows jsonb; v_member_ids uuid[];
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;

  WITH roster AS (
    -- primary member email
    SELECT DISTINCT e.person_id, m.id AS member_id, lower(m.email) AS email
    FROM public.engagements e
    JOIN public.members m ON m.person_id = e.person_id
    WHERE e.initiative_id = p_initiative_id AND e.status = 'active'
      AND m.member_status = 'active'
      AND m.email IS NOT NULL AND m.email <> ''
    UNION
    -- alternate emails (member_emails)
    SELECT DISTINCT e.person_id, m.id AS member_id, lower(me.email::text) AS email
    FROM public.engagements e
    JOIN public.members m ON m.person_id = e.person_id
    JOIN public.member_emails me ON me.member_id = m.id
    WHERE e.initiative_id = p_initiative_id AND e.status = 'active'
      AND m.member_status = 'active'
      AND me.email IS NOT NULL
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('person_id', person_id, 'member_id', member_id, 'email', email)), '[]'::jsonb),
         coalesce(array_agg(DISTINCT member_id), ARRAY[]::uuid[])
  INTO v_rows, v_member_ids
  FROM roster;

  IF cardinality(v_member_ids) > 0 THEN
    INSERT INTO public.pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason)
    SELECT NULL, mid, ARRAY['email'], 'reconcile_initiative_drive_access',
           'drive membership grant reconcile: active roster email set'
    FROM unnest(v_member_ids) AS mid;
  END IF;

  RETURN v_rows;
END;
$$;

-- Idempotent ledger upsert of the reconcile outcome (mirror of upsert_drive_revocation_candidates).
CREATE OR REPLACE FUNCTION public.upsert_membership_drive_grants(p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE
  v_org uuid;
  v_granted int := 0;
  v_failed int := 0;
  v_present int := 0;
  rec jsonb;
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;
  v_org := (SELECT id FROM public.organizations ORDER BY created_at LIMIT 1);
  IF v_org IS NULL THEN RAISE EXCEPTION 'no organization configured'; END IF;

  FOR rec IN SELECT value FROM jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) AS value
  LOOP
    INSERT INTO public.drive_membership_grants (
      organization_id, initiative_id, initiative_drive_link_id, drive_folder_id, drive_folder_url,
      grantee_person_id, grantee_member_id, permission_email, permission_id, role,
      status, api_error, reconcile_source, granted_at, last_dispatched_at
    ) VALUES (
      v_org,
      (rec->>'initiative_id')::uuid,
      nullif(rec->>'drive_link_id','')::uuid,
      rec->>'drive_folder_id',
      rec->>'drive_folder_url',
      nullif(rec->>'grantee_person_id','')::uuid,
      nullif(rec->>'grantee_member_id','')::uuid,
      (rec->>'permission_email')::citext,
      rec->>'permission_id',
      coalesce(rec->>'role','writer'),
      coalesce(rec->>'status','granted'),
      rec->'api_error',
      rec->>'reconcile_source',
      CASE WHEN (rec->>'status')='granted' THEN now() ELSE NULL END,
      now()
    )
    ON CONFLICT (drive_folder_id, permission_email) WHERE status IN ('pending_grant','granted','failed')
    DO UPDATE SET
      last_dispatched_at = now(),
      updated_at = now(),
      -- a retry that now succeeds flips failed→granted; a granted row never downgrades to failed on a
      -- transient re-scan (idempotent self-heal).
      status = CASE WHEN excluded.status='granted' THEN 'granted' ELSE public.drive_membership_grants.status END,
      permission_id = coalesce(excluded.permission_id, public.drive_membership_grants.permission_id),
      granted_at = coalesce(public.drive_membership_grants.granted_at, excluded.granted_at),
      -- keep api_error consistent with the (non-downgrading) status: clear it on a fresh grant, keep
      -- the row clean if it was already granted, else record the latest failure. Never a granted row
      -- with a stale error blob.
      api_error = CASE WHEN excluded.status='granted' THEN NULL
                       WHEN public.drive_membership_grants.status='granted' THEN NULL
                       ELSE excluded.api_error END;

    IF (rec->>'status') = 'granted' THEN v_granted := v_granted + 1;
    ELSIF (rec->>'status') = 'already_present' THEN v_present := v_present + 1;
    ELSIF (rec->>'status') = 'failed' THEN v_failed := v_failed + 1;
    END IF;
  END LOOP;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (NULL, 'drive_membership_grant_reconciled', 'drive_membership_grants', NULL, '{}'::jsonb,
          jsonb_build_object('granted', v_granted, 'already_present', v_present, 'failed', v_failed,
                             'rows', jsonb_array_length(coalesce(p_rows,'[]'::jsonb))));

  RETURN jsonb_build_object('granted', v_granted, 'already_present', v_present, 'failed', v_failed);
END;
$$;

-- ─────────────────────── Missing-folder detection + GP alert ───────────────────────
-- Per the #1376 ownership decision: the reconcile cron does NOT auto-create folders (folder
-- ownership must fall to a human via the OAuth EF). It ALERTS the GP, who runs provision_initiative_drive.
-- Scope = the kinds that carry a working folder (tribes + workgroups). Kind-agnostic on the GRANT
-- side, but the missing-folder alert is deliberately narrow to avoid noise on community verticals.
CREATE OR REPLACE FUNCTION public.list_initiatives_missing_drive_workspace()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_rows jsonb; v_caller_id uuid; v_system boolean;
BEGIN
  -- GP-or-system. `current_caller_role()` (=auth.role()) is NULL when pg_cron invokes SQL directly,
  -- so we use the established cron-context bypass (ADR-0028 p89) that also matches service_role via
  -- PostgREST and the GP JWT path. Harmless read (titles + counts, no PII).
  v_system := (current_setting('role', true) IN ('service_role','postgres')
               OR current_user IN ('postgres','supabase_admin'));
  IF NOT v_system THEN
    v_caller_id := (SELECT id FROM public.members WHERE auth_id = auth.uid());
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Unauthorized: GP only (manage_platform)';
    END IF;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'initiative_id', i.id, 'title', i.title, 'kind', i.kind,
           'created_at', i.created_at,
           'active_members', (SELECT count(DISTINCT e.person_id) FROM public.engagements e
                              WHERE e.initiative_id = i.id AND e.status='active')
         ) ORDER BY i.created_at), '[]'::jsonb)
  INTO v_rows
  FROM public.initiatives i
  WHERE i.status = 'active'
    AND i.kind IN ('research_tribe','workgroup')
    AND NOT EXISTS (SELECT 1 FROM public.initiative_drive_links l
                    WHERE l.initiative_id = i.id AND l.unlinked_at IS NULL AND l.link_purpose='workspace');
  RETURN v_rows;
END;
$$;

-- Cron-facing GP alert (service-role): notify GP of tribes/workgroups still missing a workspace folder.
CREATE OR REPLACE FUNCTION public.notify_missing_drive_workspaces()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_missing jsonb; v_n int; v_gp uuid;
BEGIN
  -- Invoked by pg_cron (weekly) directly via SQL → no PostgREST JWT context, so auth.role() is NULL.
  -- Accept the cron context (postgres/supabase_admin) OR service_role (ADR-0028 p89 cron-bypass).
  IF NOT (current_setting('role', true) IN ('service_role','postgres')
          OR current_user IN ('postgres','supabase_admin')) THEN
    RAISE EXCEPTION 'service-role or cron only';
  END IF;
  v_missing := public.list_initiatives_missing_drive_workspace();
  v_n := jsonb_array_length(coalesce(v_missing,'[]'::jsonb));
  IF v_n = 0 THEN RETURN jsonb_build_object('missing', 0); END IF;

  FOR v_gp IN
    SELECT m.id FROM public.members m
    WHERE m.member_status='active' AND public.can_by_member(m.id,'manage_platform')
  LOOP
    PERFORM public.create_notification(
      v_gp,
      'drive_workspace_missing'::text,
      (v_n::text || ' tribo(s)/workgroup(s) ativo(s) sem pasta Drive de workspace')::text,
      'Novas iniciativas foram criadas sem pasta de Drive. Provisione via MCP (provision_initiative_drive) — cria a subpasta, vincula e concede acesso ao roster. #1376.'::text,
      NULL::text, 'drive_membership_grants'::text, NULL::uuid);
  END LOOP;

  RETURN jsonb_build_object('missing', v_n, 'items', v_missing);
END;
$$;

-- ─────────────────────── GP observability ───────────────────────
CREATE OR REPLACE FUNCTION public.admin_list_membership_drive_grants(
  p_status text DEFAULT NULL, p_initiative_id uuid DEFAULT NULL,
  p_limit int DEFAULT 50, p_offset int DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_rows jsonb; v_caller_id uuid;
BEGIN
  v_caller_id := (SELECT id FROM public.members WHERE auth_id = auth.uid());
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: GP only (manage_platform)';
  END IF;
  SELECT coalesce(jsonb_agg(row_to_json(t) ORDER BY t.updated_at DESC), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT g.id, g.initiative_id, i.title AS initiative_title, g.drive_folder_url,
           g.grantee_member_id, m.name AS grantee_name, g.permission_email, g.role,
           g.status, g.api_error, g.reconcile_source, g.granted_at, g.updated_at
    FROM public.drive_membership_grants g
    JOIN public.initiatives i ON i.id = g.initiative_id
    LEFT JOIN public.members m ON m.id = g.grantee_member_id
    WHERE (p_status IS NULL OR g.status = p_status)
      AND (p_initiative_id IS NULL OR g.initiative_id = p_initiative_id)
    ORDER BY g.updated_at DESC
    LIMIT greatest(1, least(p_limit, 200)) OFFSET greatest(0, p_offset)
  ) t;
  RETURN v_rows;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_membership_drive_grant_health()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_out jsonb; v_caller_id uuid;
BEGIN
  v_caller_id := (SELECT id FROM public.members WHERE auth_id = auth.uid());
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: GP only (manage_platform)';
  END IF;
  SELECT jsonb_build_object(
    'ledger', (SELECT coalesce(jsonb_object_agg(status, n),'{}'::jsonb)
               FROM (SELECT status, count(*) AS n FROM public.drive_membership_grants GROUP BY status) s),
    'granted_total', (SELECT count(*) FROM public.drive_membership_grants WHERE status='granted'),
    'failed_total', (SELECT count(*) FROM public.drive_membership_grants WHERE status='failed'),
    'last_reconciled_at', (SELECT max(last_dispatched_at) FROM public.drive_membership_grants),
    'active_workspace_links', (SELECT count(*) FROM public.initiative_drive_links
                               WHERE unlinked_at IS NULL AND link_purpose='workspace'),
    'initiatives_missing_workspace', public.list_initiatives_missing_drive_workspace()
  ) INTO v_out;
  RETURN v_out;
END;
$$;

-- Grants: reads are GP-gated inside the body; service-role EF calls the EF-facing set.
REVOKE ALL ON FUNCTION public.get_membership_drive_targets(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_initiative_drive_roster(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.upsert_membership_drive_grants(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_missing_drive_workspaces() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_membership_drive_targets(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_initiative_drive_roster(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.upsert_membership_drive_grants(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.notify_missing_drive_workspaces() TO service_role;

REVOKE ALL ON FUNCTION public.list_initiatives_missing_drive_workspace() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_membership_drive_grants(text, uuid, int, int) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_membership_drive_grant_health() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_initiatives_missing_drive_workspace() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_list_membership_drive_grants(text, uuid, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_membership_drive_grant_health() TO authenticated;

NOTIFY pgrst, 'reload schema';
