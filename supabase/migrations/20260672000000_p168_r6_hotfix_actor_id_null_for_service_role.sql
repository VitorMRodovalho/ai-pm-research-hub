-- P168 R6 hotfix: actor_id is FK to members(id). The null-UUID placeholder
-- '00000000...' failed FK. Column is nullable — use NULL when caller is service_role
-- (no member). Apply same fix to log_security_incident (OQ-B1).

CREATE OR REPLACE FUNCTION public.get_invariant_alerts()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id   uuid;
  v_alerts      jsonb := '[]'::jsonb;
  v_violation   record;
  v_first_seen  timestamptz;
  v_age_hours   numeric;
  v_existing    int;
BEGIN
  SELECT id INTO v_caller_id FROM public.members
   WHERE auth_id = (SELECT auth.uid())
     AND (is_superadmin = true OR operational_role IN ('manager','deputy_manager'))
   LIMIT 1;

  IF v_caller_id IS NULL AND (SELECT auth.role()) <> 'service_role' THEN
    RAISE EXCEPTION 'get_invariant_alerts: admin only';
  END IF;

  FOR v_violation IN
    SELECT invariant_name, description, severity, violation_count, sample_ids
      FROM public.check_schema_invariants()
     WHERE violation_count > 0
     ORDER BY (CASE severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END),
              invariant_name
  LOOP
    SELECT min(al.created_at) INTO v_first_seen
      FROM public.admin_audit_log al
     WHERE al.action = 'security_incident.invariant_drift.detected'
       AND al.changes->>'invariant_name' = v_violation.invariant_name
       AND NOT EXISTS (
         SELECT 1 FROM public.admin_audit_log al2
          WHERE al2.action = 'security_incident.invariant_drift.cleared'
            AND al2.changes->>'invariant_name' = v_violation.invariant_name
            AND al2.created_at > al.created_at
       );

    IF v_first_seen IS NULL THEN
      SELECT count(*) INTO v_existing FROM public.admin_audit_log
       WHERE action = 'security_incident.invariant_drift.detected'
         AND changes->>'invariant_name' = v_violation.invariant_name
         AND created_at > now() - interval '1 hour';

      IF v_existing = 0 THEN
        INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
        VALUES (
          v_caller_id,
          'security_incident.invariant_drift.detected',
          'invariant',
          NULL,
          jsonb_build_object(
            'invariant_name', v_violation.invariant_name,
            'description',    v_violation.description,
            'severity',       v_violation.severity,
            'violation_count', v_violation.violation_count,
            'sample_ids',     to_jsonb(v_violation.sample_ids),
            'summary',        format('Drift detected: %s (%s violations)', v_violation.invariant_name, v_violation.violation_count)
          ),
          jsonb_build_object(
            'severity',     CASE v_violation.severity WHEN 'critical' THEN 'p0' WHEN 'high' THEN 'p1' WHEN 'medium' THEN 'p2' ELSE 'p3' END,
            'status',       'open',
            'incident_id',  gen_random_uuid(),
            'auto_detected', true,
            'via',          'get_invariant_alerts'
          )
        );
        v_first_seen := now();
      END IF;
    END IF;

    v_age_hours := EXTRACT(EPOCH FROM (now() - v_first_seen)) / 3600.0;

    v_alerts := v_alerts || jsonb_build_object(
      'invariant_name',  v_violation.invariant_name,
      'description',     v_violation.description,
      'severity',        v_violation.severity,
      'violation_count', v_violation.violation_count,
      'sample_ids',      to_jsonb(v_violation.sample_ids),
      'first_seen_at',   v_first_seen,
      'age_hours',       round(v_age_hours, 2),
      'persistent',      (v_age_hours >= 24)
    );
  END LOOP;

  RETURN jsonb_build_object(
    'alerts',          v_alerts,
    'alert_count',     jsonb_array_length(v_alerts),
    'has_persistent',  EXISTS (SELECT 1 FROM jsonb_array_elements(v_alerts) e WHERE (e->>'persistent')::boolean),
    'checked_at',      now()
  );
END;
$function$;


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

  IF p_category !~ '^[a-z][a-z0-9_]*$' OR p_event !~ '^[a-z][a-z0-9_]*$' THEN
    RAISE EXCEPTION 'Category/event must match ^[a-z][a-z0-9_]*$';
  END IF;

  v_action := format('security_incident.%s.%s', p_category, p_event);

  INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id,
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

NOTIFY pgrst, 'reload schema';
