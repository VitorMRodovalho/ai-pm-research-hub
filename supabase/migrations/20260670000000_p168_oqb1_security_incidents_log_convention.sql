-- ============================================================================
-- P168 OQ-B1 — Security incidents log convention (over admin_audit_log)
-- Authorization: PM Vitor 2026-05-15 (OQ-B1 selection)
--
-- No new table. Convention:
--   action = 'security_incident.<category>.<event>'
--     e.g. security_incident.identity_hijack.opened
--          security_incident.identity_hijack.remediated
--          security_incident.identity_hijack.closed
--   metadata.severity   ∈ ('p0','p1','p2','p3')
--   metadata.status     ∈ ('open','investigating','remediated','closed')
--   metadata.brief_path = 'docs/audit/...md' (optional pointer to investigation doc)
--   metadata.incident_id (correlates multiple log rows of the same incident — uuid)
--
-- Two RPCs:
--   1. log_security_incident — admin-only writer (also usable manually via execute_sql)
--   2. get_security_incidents — admin-only reader, filterable by status/severity
-- ============================================================================

-- 1) Writer RPC
CREATE OR REPLACE FUNCTION public.log_security_incident(
  p_category    text,
  p_event       text,
  p_severity    text DEFAULT 'p2',
  p_status      text DEFAULT 'open',
  p_target_type text DEFAULT NULL,
  p_target_id   uuid DEFAULT NULL,
  p_brief_path  text DEFAULT NULL,
  p_incident_id uuid DEFAULT NULL,
  p_summary     text DEFAULT NULL,
  p_extra       jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id   uuid;
  v_action      text;
  v_incident_id uuid := COALESCE(p_incident_id, gen_random_uuid());
  v_audit_id    uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members
   WHERE auth_id = (SELECT auth.uid())
     AND (is_superadmin = true OR operational_role IN ('manager','deputy_manager'))
   LIMIT 1;

  IF v_caller_id IS NULL AND (SELECT auth.role()) <> 'service_role' THEN
    RAISE EXCEPTION 'log_security_incident: admin only';
  END IF;

  IF p_severity NOT IN ('p0','p1','p2','p3') THEN
    RAISE EXCEPTION 'Invalid severity %, expected p0|p1|p2|p3', p_severity;
  END IF;

  IF p_status NOT IN ('open','investigating','remediated','closed') THEN
    RAISE EXCEPTION 'Invalid status %, expected open|investigating|remediated|closed', p_status;
  END IF;

  -- Validate category and event match audit-log regex (lowercase + underscore + dot)
  IF p_category !~ '^[a-z][a-z0-9_]*$' OR p_event !~ '^[a-z][a-z0-9_]*$' THEN
    RAISE EXCEPTION 'Category/event must match ^[a-z][a-z0-9_]*$';
  END IF;

  v_action := format('security_incident.%s.%s', p_category, p_event);

  INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    COALESCE(v_caller_id, '00000000-0000-0000-0000-000000000000'::uuid),
    v_action,
    COALESCE(p_target_type, 'security'),
    p_target_id,
    jsonb_build_object('summary', p_summary) || COALESCE(p_extra, '{}'::jsonb),
    jsonb_build_object(
      'severity',    p_severity,
      'status',      p_status,
      'incident_id', v_incident_id,
      'brief_path',  p_brief_path
    )
  )
  RETURNING id INTO v_audit_id;

  RETURN jsonb_build_object('success', true, 'audit_id', v_audit_id, 'incident_id', v_incident_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.log_security_incident(text,text,text,text,text,uuid,text,uuid,text,jsonb) TO authenticated, service_role;

COMMENT ON FUNCTION public.log_security_incident(text,text,text,text,text,uuid,text,uuid,text,jsonb) IS
  'Append a security_incident.* entry to admin_audit_log with severity/status/incident_id metadata. Admin (superadmin / manager / deputy_manager) or service_role only. P168 OQ-B1.';


-- 2) Reader RPC
CREATE OR REPLACE FUNCTION public.get_security_incidents(
  p_status   text DEFAULT NULL,
  p_severity text DEFAULT NULL,
  p_limit    int  DEFAULT 50
)
RETURNS TABLE(
  audit_id     uuid,
  created_at   timestamptz,
  action       text,
  severity     text,
  status       text,
  incident_id  uuid,
  brief_path   text,
  target_type  text,
  target_id    uuid,
  summary      text,
  actor_id     uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.members
     WHERE auth_id = (SELECT auth.uid())
       AND (is_superadmin = true OR operational_role IN ('manager','deputy_manager'))
  ) AND (SELECT auth.role()) <> 'service_role' THEN
    RAISE EXCEPTION 'get_security_incidents: admin only';
  END IF;

  RETURN QUERY
  SELECT
    al.id,
    al.created_at,
    al.action,
    (al.metadata->>'severity')::text,
    (al.metadata->>'status')::text,
    (al.metadata->>'incident_id')::uuid,
    (al.metadata->>'brief_path')::text,
    al.target_type,
    al.target_id,
    (al.changes->>'summary')::text,
    al.actor_id
  FROM public.admin_audit_log al
  WHERE al.action LIKE 'security_incident.%'
    AND (p_status   IS NULL OR (al.metadata->>'status')   = p_status)
    AND (p_severity IS NULL OR (al.metadata->>'severity') = p_severity)
  ORDER BY al.created_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 500));
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_security_incidents(text,text,int) TO authenticated, service_role;

COMMENT ON FUNCTION public.get_security_incidents(text,text,int) IS
  'Read security_incident.* entries from admin_audit_log. Admin-only. P168 OQ-B1.';


-- 3) Backfill the P168 D=1 identity hijack incident retroactively (3 entries: opened, remediated, closed)
DO $backfill$
DECLARE
  v_incident_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    '880f736c-3e76-4df4-9375-33575c190305'::uuid,
    'security_incident.identity_hijack.opened',
    'member',
    '57fcf33c-25a3-4555-b358-a168a4151794'::uuid,
    jsonb_build_object('summary', 'Active identity hijack discovered: Paulo Roberto de Camargo Filho silently re-claiming Paulo Alves member row 57fcf33c via secondary_emails branch in get_member_by_auth on every session refresh',
                       'root_cause', 'get_member_by_auth secondary_emails match + replace-existing-auth_id branch with no ownership verification',
                       'discovery_path', 'invariant D=1 carry investigation -> auth.sessions refreshed_at timing -> profile.astro:1876 unverified writes'),
    jsonb_build_object('severity','p0','status','open','incident_id',v_incident_id,'brief_path','docs/audit/P168_D1_PAULO_ALVES_AUTH_HIJACK_BRIEF.md','timeline_anchor','2026-05-15T22:35Z')
  );

  INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    '880f736c-3e76-4df4-9375-33575c190305'::uuid,
    'security_incident.identity_hijack.remediated',
    'member',
    '57fcf33c-25a3-4555-b358-a168a4151794'::uuid,
    jsonb_build_object('summary', 'R1 revoked 101 refresh_tokens + 2 sessions for Paulo Roberto; R2 restored canonical members[57fcf33c] state; R3-a hardened get_member_by_auth + try_auto_link_ghost (migration 20260667000000); OQ3 deleted auth.users[a2407bdc].',
                       'remediation_steps', jsonb_build_array('R1','R2','R3-a','OQ3')),
    jsonb_build_object('severity','p0','status','remediated','incident_id',v_incident_id,'brief_path','docs/audit/P168_D1_PAULO_ALVES_AUTH_HIJACK_BRIEF.md','timeline_anchor','2026-05-15T23:00Z')
  );

  INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    '880f736c-3e76-4df4-9375-33575c190305'::uuid,
    'security_incident.identity_hijack.closed',
    'member',
    '57fcf33c-25a3-4555-b358-a168a4151794'::uuid,
    jsonb_build_object('summary', 'R4 deployed (email-verified secondary_emails flow, migration 20260668000000); OQ-A1 backfill prevented Carlos LinkedIn ghost; OQ-B1 added security_incidents log convention. Invariant D back to 0. Vulnerability surface platform-wide closed.',
                       'closure_steps', jsonb_build_array('R4','R5_subsumed','OQ-A1','OQ-B1')),
    jsonb_build_object('severity','p0','status','closed','incident_id',v_incident_id,'brief_path','docs/audit/P168_D1_PAULO_ALVES_AUTH_HIJACK_BRIEF.md','timeline_anchor','2026-05-16T03:50Z')
  );
END $backfill$;

NOTIFY pgrst, 'reload schema';
