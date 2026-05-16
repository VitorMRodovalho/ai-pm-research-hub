-- p169 hotfix — get_security_incidents V4 auth (ADR-0011 compliance)
-- p168 migration 20260670 introduced this RPC with hardcoded role list, breaking rpc-v4-auth contract test.
-- Replace with can_by_member('manage_platform') call (same set of users — manager/deputy_manager/co_gp).
-- Rollback: restore body from 20260670000000_p168_oqb1_security_incidents_log_convention.sql

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
DECLARE
  v_caller_id uuid;
BEGIN
  -- V4 authority gate (ADR-0011): admin-only via manage_platform action.
  -- service_role bypasses (cron/EF callers).
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = (SELECT auth.uid()) LIMIT 1;

  IF (SELECT auth.role()) <> 'service_role'
     AND (v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission';
  END IF;

  RETURN QUERY
  SELECT
    aal.id          AS audit_id,
    aal.created_at,
    aal.action,
    aal.metadata->>'severity'    AS severity,
    aal.metadata->>'status'      AS status,
    (aal.metadata->>'incident_id')::uuid AS incident_id,
    aal.metadata->>'brief_path'  AS brief_path,
    aal.target_type,
    aal.target_id,
    aal.metadata->>'summary'     AS summary,
    aal.actor_id
  FROM public.admin_audit_log aal
  WHERE aal.action LIKE 'security_incident.%'
    AND (p_status   IS NULL OR aal.metadata->>'status'   = p_status)
    AND (p_severity IS NULL OR aal.metadata->>'severity' = p_severity)
  ORDER BY aal.created_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 500));
END;
$function$;

NOTIFY pgrst, 'reload schema';
