-- ============================================================================
-- P168 R6 — Invariant alerts RPC (surface check_schema_invariants drift)
-- Authorization: PM Vitor 2026-05-15 (R6 of P168 D=1 remediation roadmap)
--
-- Closes the loop: D=1 was silently in the handoff for sessions before discovery.
-- This RPC + DataHealthIsland section give admins a real signal that something
-- is wrong, with first_seen timestamp so "persisting > 24h" can be observed.
--
-- Convention: each time get_invariant_alerts() runs and finds a violation that
-- has no prior 'security_incident.invariant_drift.detected' entry (still open)
-- for that invariant name, it inserts one (auto-baseline). This gives a stable
-- "first_seen_at" anchor. A future improvement could insert .cleared when the
-- violation count drops to 0.
-- ============================================================================

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
          COALESCE(v_caller_id, '00000000-0000-0000-0000-000000000000'::uuid),
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

GRANT EXECUTE ON FUNCTION public.get_invariant_alerts() TO authenticated, service_role;

COMMENT ON FUNCTION public.get_invariant_alerts() IS
  'Surface check_schema_invariants() violations as actionable alerts with first_seen_at + persistent (>24h) flag. Auto-baselines new drift via security_incident.invariant_drift.detected entries. Admin-only. P168 R6.';

NOTIFY pgrst, 'reload schema';
