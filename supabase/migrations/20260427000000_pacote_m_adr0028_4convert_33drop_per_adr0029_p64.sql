-- Pacote M (p64) — ADR-0028 V4 adapter conversion + ADR-0029 dead-code retirement
--
-- Per:
--   * ADR-0028 (Accepted 2026-04-26 p64) — service-role-bypass adapter pattern
--   * ADR-0029 (Accepted 2026-04-26 p64) — ingestion subsystem retroactive retirement
--   * GC-141 — governance changelog entry referencing both ADRs
--   * docs/audit/ADR-0028-prematch-audit.md — Phase 1 evidence (32 of 37 fns dead)
--   * P4 council investigation (security-engineer + accountability-advisor) —
--     UNANIMOUS verdict: accidental DDL drift, not intentional retirement
--
-- Dependency re-check during implementation surfaced 1 additional transitive
-- breakage: admin_capture_data_quality_snapshot calls admin_data_quality_audit()
-- (broken — missing legacy_tribes/legacy_tribe_board_links). Reclassified as
-- PARTIAL_BROKEN. Final scope: 4 OK convert (vs Phase 1's 5) + 33 drop (vs 32).
-- ADR-0029 + GC-141 + ADR-0028 amendment notes updated in companion commit.
--
-- Order:
--   1. CREATE OR REPLACE for 4 OK fns with V4 adapter pattern (admin_check_*,
--      admin_set_ingestion_source_sla, admin_set_release_readiness_policy,
--      admin_get_*)
--   2. REVOKE EXECUTE on the 4 from PUBLIC + anon (preserve security baseline)
--   3. COMMENT ON FUNCTION for the 4 with ADR-0028 sentinel
--   4. DROP FUNCTION for 33 dead-code fns (alphabetical)
--   5. NOTIFY pgrst, 'reload schema'

-- ============================================================================
-- PART 1 — V4 adapter conversions (4 fns)
-- ============================================================================

DROP FUNCTION IF EXISTS public.admin_check_ingestion_source_timeout(text, timestamptz);
CREATE OR REPLACE FUNCTION public.admin_check_ingestion_source_timeout(p_source text, p_started_at timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_sla record;
  v_elapsed_minutes integer;
  v_timed_out boolean := false;
BEGIN
  -- ADR-0028 service-role-bypass adapter (Pacote M, p64)
  IF auth.role() = 'service_role' THEN
    NULL;
  ELSE
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL THEN
      RAISE EXCEPTION 'authentication_required';
    END IF;
    IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'permission_denied: manage_platform required';
    END IF;
  END IF;

  SELECT * INTO v_sla
  FROM public.ingestion_source_sla
  WHERE source = trim(p_source) AND enabled IS TRUE
  LIMIT 1;

  IF v_sla IS NULL THEN
    RETURN jsonb_build_object('source', trim(p_source), 'has_policy', false, 'timed_out', false);
  END IF;

  v_elapsed_minutes := greatest(extract(epoch from (now() - p_started_at))::integer / 60, 0);
  v_timed_out := v_elapsed_minutes > v_sla.timeout_minutes;

  RETURN jsonb_build_object(
    'source', trim(p_source),
    'has_policy', true,
    'timed_out', v_timed_out,
    'elapsed_minutes', v_elapsed_minutes,
    'timeout_minutes', v_sla.timeout_minutes,
    'expected_max_minutes', v_sla.expected_max_minutes,
    'escalation_severity', v_sla.escalation_severity
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_check_ingestion_source_timeout(text, timestamptz) FROM PUBLIC, anon;

COMMENT ON FUNCTION public.admin_check_ingestion_source_timeout(text, timestamptz) IS
  'ADR-0028 service-role-bypass adapter (Pacote M, p64): manage_platform gate via can_by_member with service_role bypass for cron/EF callers. Reads ingestion_source_sla (live). Replaces V3 OR-chain.';

DROP FUNCTION IF EXISTS public.admin_set_ingestion_source_sla(text, integer, integer, text, boolean);
CREATE OR REPLACE FUNCTION public.admin_set_ingestion_source_sla(
  p_source text,
  p_expected_max_minutes integer DEFAULT 120,
  p_timeout_minutes integer DEFAULT 240,
  p_escalation_severity text DEFAULT 'warning',
  p_enabled boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  -- ADR-0028 service-role-bypass adapter (Pacote M, p64)
  IF auth.role() = 'service_role' THEN
    NULL;
  ELSE
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL THEN
      RAISE EXCEPTION 'authentication_required';
    END IF;
    IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'permission_denied: manage_platform required';
    END IF;
  END IF;

  IF p_escalation_severity NOT IN ('info', 'warning', 'critical') THEN
    RAISE EXCEPTION 'Invalid escalation severity: %', p_escalation_severity;
  END IF;

  INSERT INTO public.ingestion_source_sla(
    source, expected_max_minutes, timeout_minutes, escalation_severity, enabled, updated_at, updated_by
  ) VALUES (
    trim(p_source),
    greatest(coalesce(p_expected_max_minutes, 120), 1),
    greatest(coalesce(p_timeout_minutes, 240), 1),
    p_escalation_severity,
    coalesce(p_enabled, true),
    now(),
    COALESCE(v_caller_id, NULL::uuid)
  )
  ON CONFLICT (source)
  DO UPDATE SET
    expected_max_minutes = EXCLUDED.expected_max_minutes,
    timeout_minutes = EXCLUDED.timeout_minutes,
    escalation_severity = EXCLUDED.escalation_severity,
    enabled = EXCLUDED.enabled,
    updated_at = now(),
    updated_by = COALESCE(v_caller_id, NULL::uuid);

  RETURN jsonb_build_object('success', true, 'source', trim(p_source));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_set_ingestion_source_sla(text, integer, integer, text, boolean) FROM PUBLIC, anon;

COMMENT ON FUNCTION public.admin_set_ingestion_source_sla(text, integer, integer, text, boolean) IS
  'ADR-0028 service-role-bypass adapter (Pacote M, p64): manage_platform gate via can_by_member with service_role bypass. UPSERT on ingestion_source_sla (live). updated_by nullable when service_role.';

DROP FUNCTION IF EXISTS public.admin_set_release_readiness_policy(text, text, integer, integer);
CREATE OR REPLACE FUNCTION public.admin_set_release_readiness_policy(
  p_policy_key text DEFAULT 'default',
  p_mode text DEFAULT 'strict',
  p_max_open_warnings integer DEFAULT 5,
  p_require_fresh_snapshot_hours integer DEFAULT 24
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  -- ADR-0028 service-role-bypass adapter (Pacote M, p64)
  IF auth.role() = 'service_role' THEN
    NULL;
  ELSE
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL THEN
      RAISE EXCEPTION 'authentication_required';
    END IF;
    IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'permission_denied: manage_platform required';
    END IF;
  END IF;

  IF p_mode NOT IN ('strict', 'advisory') THEN
    RAISE EXCEPTION 'Invalid readiness mode: %', p_mode;
  END IF;

  INSERT INTO public.release_readiness_policies (
    policy_key, mode, max_open_warnings, require_fresh_snapshot_hours, updated_at, updated_by
  ) VALUES (
    coalesce(nullif(trim(p_policy_key), ''), 'default'),
    p_mode,
    greatest(coalesce(p_max_open_warnings, 5), 0),
    greatest(coalesce(p_require_fresh_snapshot_hours, 24), 1),
    now(),
    COALESCE(v_caller_id, NULL::uuid)
  )
  ON CONFLICT (policy_key)
  DO UPDATE SET
    mode = EXCLUDED.mode,
    max_open_warnings = EXCLUDED.max_open_warnings,
    require_fresh_snapshot_hours = EXCLUDED.require_fresh_snapshot_hours,
    updated_at = now(),
    updated_by = COALESCE(v_caller_id, NULL::uuid);

  RETURN jsonb_build_object('success', true, 'policy_key', coalesce(nullif(trim(p_policy_key), ''), 'default'), 'mode', p_mode);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_set_release_readiness_policy(text, text, integer, integer) FROM PUBLIC, anon;

COMMENT ON FUNCTION public.admin_set_release_readiness_policy(text, text, integer, integer) IS
  'ADR-0028 service-role-bypass adapter (Pacote M, p64): manage_platform gate via can_by_member with service_role bypass. UPSERT on release_readiness_policies (live). updated_by nullable when service_role.';

DROP FUNCTION IF EXISTS public.admin_get_ingestion_source_policy(text);
CREATE OR REPLACE FUNCTION public.admin_get_ingestion_source_policy(p_source text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_row record;
BEGIN
  -- ADR-0028 service-role-bypass adapter (Pacote M, p64)
  IF auth.role() = 'service_role' THEN
    NULL;
  ELSE
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL THEN
      RAISE EXCEPTION 'authentication_required';
    END IF;
    IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'permission_denied: manage_platform required';
    END IF;
  END IF;

  SELECT * INTO v_row
  FROM public.ingestion_source_controls
  WHERE source = p_source
  LIMIT 1;

  IF v_row IS NULL THEN
    RETURN jsonb_build_object(
      'source', p_source,
      'allow_apply', false,
      'require_manual_review', true,
      'notes', 'No policy found; default deny.'
    );
  END IF;

  RETURN to_jsonb(v_row);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_get_ingestion_source_policy(text) FROM PUBLIC, anon;

COMMENT ON FUNCTION public.admin_get_ingestion_source_policy(text) IS
  'ADR-0028 service-role-bypass adapter (Pacote M, p64): manage_platform gate via can_by_member with service_role bypass. Pure read on ingestion_source_controls (live). STABLE.';

-- ============================================================================
-- PART 2 — DROP 33 dead-code fns per ADR-0029
-- ============================================================================

DROP FUNCTION IF EXISTS public.admin_acquire_ingestion_apply_lock(text, text, integer, jsonb);
DROP FUNCTION IF EXISTS public.admin_append_rollback_audit_event(uuid, text, text, jsonb);
DROP FUNCTION IF EXISTS public.admin_approve_ingestion_rollback(uuid, timestamptz, timestamptz);
DROP FUNCTION IF EXISTS public.admin_capture_data_quality_snapshot(text, text, uuid);
DROP FUNCTION IF EXISTS public.admin_capture_governance_bundle_snapshot(integer, text);
DROP FUNCTION IF EXISTS public.admin_check_readiness_slo_breach(integer, integer);
DROP FUNCTION IF EXISTS public.admin_complete_ingestion_run(uuid, text, uuid, text);
DROP FUNCTION IF EXISTS public.admin_data_quality_audit();
DROP FUNCTION IF EXISTS public.admin_execute_ingestion_rollback(uuid, boolean);
DROP FUNCTION IF EXISTS public.admin_plan_ingestion_rollback(uuid, text, boolean, jsonb);
DROP FUNCTION IF EXISTS public.admin_raise_provenance_anomaly_alert(uuid);
DROP FUNCTION IF EXISTS public.admin_record_release_readiness_decision(text, text);
DROP FUNCTION IF EXISTS public.admin_register_ingestion_run(text, text, text, text, text);
DROP FUNCTION IF EXISTS public.admin_release_ingestion_apply_lock(text, text);
DROP FUNCTION IF EXISTS public.admin_release_readiness_gate(integer, integer, text);
DROP FUNCTION IF EXISTS public.admin_resolve_remediation_action(bigint);
DROP FUNCTION IF EXISTS public.admin_run_dry_rehearsal_chain(text, text);
DROP FUNCTION IF EXISTS public.admin_run_ingestion_alert_remediation(bigint);
DROP FUNCTION IF EXISTS public.admin_run_post_ingestion_chain(uuid, boolean, text);
DROP FUNCTION IF EXISTS public.admin_run_post_ingestion_healthcheck(uuid);
DROP FUNCTION IF EXISTS public.admin_set_ingestion_alert_remediation_rule(text, boolean, integer, text);
DROP FUNCTION IF EXISTS public.admin_sign_ingestion_file_provenance(uuid, text, text, text, jsonb);
DROP FUNCTION IF EXISTS public.admin_simulate_ingestion_rollback(uuid);
DROP FUNCTION IF EXISTS public.admin_suggest_notion_board_mappings(integer, boolean);
DROP FUNCTION IF EXISTS public.admin_update_ingestion_alert_status(bigint, text, text, jsonb);
DROP FUNCTION IF EXISTS public.admin_verify_ingestion_provenance_batch(uuid);

DROP FUNCTION IF EXISTS public.exec_governance_export_bundle(integer);
DROP FUNCTION IF EXISTS public.exec_partner_governance_summary(integer);
DROP FUNCTION IF EXISTS public.exec_partner_governance_scorecards(integer);
DROP FUNCTION IF EXISTS public.exec_partner_governance_trends(integer);
DROP FUNCTION IF EXISTS public.exec_readiness_slo_by_source(integer);
DROP FUNCTION IF EXISTS public.exec_readiness_slo_dashboard(integer);
DROP FUNCTION IF EXISTS public.exec_remediation_effectiveness(integer);

NOTIFY pgrst, 'reload schema';
