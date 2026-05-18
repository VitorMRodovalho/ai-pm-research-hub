-- p186 OPP-185.A: test helper for detect_inactive_members INSERT path coverage
--
-- The contract test at tests/contracts/detect-inactive-members-non-dry-run.test.mjs
-- exercises detect_inactive_members(false) with Prefer: tx=rollback. With prod
-- threshold=180, candidates_count may be 0 at CI time and the IF NOT p_dry_run
-- AND v_count > 0 gate skips the INSERT block — the runtime path (notifications +
-- admin_audit_log INSERT) is not directly exercised in those runs.
--
-- This helper forces candidates>0 by temporarily lowering the threshold, runs
-- detect_inactive_members, and restores the prior value before returning.
-- Caller MUST use Prefer: tx=rollback to guarantee zero persisted side effects
-- on notifications/admin_audit_log. Defensive restore covers the case where the
-- caller forgot tx=rollback (threshold returns to prior value but INSERT side
-- effects DO persist in that misuse path — the GRANT/REVOKE is the real gate).
--
-- service_role only. Underscore prefix signals test-only intent.

CREATE OR REPLACE FUNCTION public._test_detect_inactive_with_threshold(p_threshold int)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_old_value jsonb;
  v_result jsonb;
BEGIN
  -- Defense: service_role only (matches detect_inactive_members cron-bypass check).
  -- Phrasing aligned with ADR-0011 canonical hasAuthGate set (p187 MED-186.F).
  IF current_setting('role', true) NOT IN ('service_role', 'postgres')
     AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: _test_detect_inactive_with_threshold requires service_role';
  END IF;

  IF p_threshold < 0 THEN
    RAISE EXCEPTION 'p_threshold must be >= 0 (got %)', p_threshold;
  END IF;

  -- Snapshot current site_config value
  SELECT value INTO v_old_value
    FROM public.site_config
   WHERE key = 'inactivity_threshold_days';

  -- Override
  UPDATE public.site_config
     SET value = to_jsonb(p_threshold)
   WHERE key = 'inactivity_threshold_days';

  -- Run real function inside a nested PL/pgSQL exception block so we can restore
  -- site_config even if detect_inactive_members raises. (This is a BEGIN/EXCEPTION
  -- frame, not a SQL SAVEPOINT statement — PG implicitly creates a subtransaction
  -- savepoint for the frame, but the SAVEPOINT/RELEASE keywords are not issued.)
  BEGIN
    v_result := public.detect_inactive_members(p_dry_run := false);
  EXCEPTION WHEN OTHERS THEN
    UPDATE public.site_config
       SET value = v_old_value
     WHERE key = 'inactivity_threshold_days';
    RAISE;
  END;

  -- Defensive restore (belt+suspenders for cases where caller forgot tx=rollback)
  UPDATE public.site_config
     SET value = v_old_value
   WHERE key = 'inactivity_threshold_days';

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._test_detect_inactive_with_threshold(int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._test_detect_inactive_with_threshold(int) TO service_role;

COMMENT ON FUNCTION public._test_detect_inactive_with_threshold(int) IS
  'Test helper (p186 OPP-185.A): forces detect_inactive_members INSERT path coverage by '
  'temporarily overriding site_config.inactivity_threshold_days for a single call. '
  'Restores prior value before return (defense in depth). '
  'CALLER MUST use Prefer: tx=rollback header via PostgREST to guarantee zero side effects '
  'on notifications and admin_audit_log. service_role only.';
