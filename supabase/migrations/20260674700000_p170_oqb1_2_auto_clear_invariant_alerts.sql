-- p170 OQ-B1 #2 — Auto-clear invariant drift baselines when violation resolves
--
-- Context: get_invariant_alerts() inserts a security_incident.invariant_drift.detected
-- audit row for each open violation. When the violation resolves (violation_count=0),
-- the function only stops returning that alert — but it never inserts a corresponding
-- .cleared row. Result: open baselines linger in admin_audit_log forever.
--
-- Fix: After looping current violations, scan open baselines (detected without cleared)
-- whose invariant_name is NOT in the current violation set, and auto-insert .cleared.
--
-- Behavior post-migration:
--   - When violation appears → .detected row inserted (existing)
--   - When violation persists → no new row (existing dedupe via 1h window)
--   - When violation resolves → .cleared row inserted NOW (new)
--   - Subsequent reappearance → new .detected (existing, since prior baseline is closed)
--
-- Rollback: restore prior CREATE OR REPLACE FUNCTION body (no .cleared loop).

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
  v_current_invariant_names text[];
  v_open_baseline record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members
   WHERE auth_id = (SELECT auth.uid())
     AND (is_superadmin = true OR operational_role IN ('manager','deputy_manager'))
   LIMIT 1;

  IF v_caller_id IS NULL AND (SELECT auth.role()) <> 'service_role' THEN
    RAISE EXCEPTION 'get_invariant_alerts: admin only';
  END IF;

  -- Snapshot current violating invariant names (for auto-clear comparison)
  SELECT COALESCE(array_agg(invariant_name), ARRAY[]::text[])
    INTO v_current_invariant_names
    FROM public.check_schema_invariants()
   WHERE violation_count > 0;

  -- Existing behavior: emit .detected for new violations + build alerts payload
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

  -- p170 OQ-B1 #2: auto-clear open baselines whose invariant is no longer violating
  FOR v_open_baseline IN
    SELECT DISTINCT
      al.changes->>'invariant_name' AS invariant_name,
      al.changes->>'severity'       AS severity,
      al.metadata->>'incident_id'   AS incident_id,
      MIN(al.created_at) OVER (PARTITION BY al.changes->>'invariant_name') AS first_seen_at
    FROM public.admin_audit_log al
    WHERE al.action = 'security_incident.invariant_drift.detected'
      AND NOT EXISTS (
        SELECT 1 FROM public.admin_audit_log al2
         WHERE al2.action = 'security_incident.invariant_drift.cleared'
           AND al2.changes->>'invariant_name' = al.changes->>'invariant_name'
           AND al2.created_at > al.created_at
      )
      AND NOT (al.changes->>'invariant_name' = ANY(v_current_invariant_names))
  LOOP
    INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      v_caller_id,
      'security_incident.invariant_drift.cleared',
      'invariant',
      NULL,
      jsonb_build_object(
        'invariant_name', v_open_baseline.invariant_name,
        'severity',       v_open_baseline.severity,
        'summary',        format('Drift cleared: %s now has 0 violations', v_open_baseline.invariant_name),
        'first_seen_at',  v_open_baseline.first_seen_at,
        'duration_hours', round(EXTRACT(EPOCH FROM (now() - v_open_baseline.first_seen_at)) / 3600.0, 2)
      ),
      jsonb_build_object(
        'status',        'cleared',
        'auto_cleared',  true,
        'via',           'get_invariant_alerts',
        'incident_id',   v_open_baseline.incident_id
      )
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

COMMENT ON FUNCTION public.get_invariant_alerts() IS
  'p170 OQ-B1 #2 — Returns invariant drift alerts + auto-inserts .detected (new) or .cleared (resolved) audit rows. Pre-p170 não inseria .cleared; baseline ficava aberto indefinidamente em admin_audit_log.';

NOTIFY pgrst, 'reload schema';
