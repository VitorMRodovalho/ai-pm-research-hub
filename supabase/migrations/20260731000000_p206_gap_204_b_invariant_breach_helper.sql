-- p206 / Issue #213 — GAP-204.B behavioural invariant breach helper RPC
--
-- INTENT
-- ──────
-- Add `_test_invariants_with_synthetic_breach(text)` test-only helper that
-- seeds a synthetic R or S invariant violation (selection_applications +
-- optional members) and returns the R/S rows from check_schema_invariants().
-- Caller MUST use `Prefer: tx=rollback` to ensure zero persisted state.
--
-- The 4 behavioural tests at `tests/contracts/volunteer-authority-invariants
-- -behavioural.test.mjs` exercise the helper to prove:
--   1. R=0 at deploy (no helper call)
--   2. S=0 at deploy (no helper call)
--   3. R correctly detects synthetic missing-member breach (via helper)
--   4. S correctly detects synthetic NULL-person_id breach (via helper)
--
-- Mirrors p186 `_test_detect_inactive_with_threshold` pattern:
--   - SECURITY DEFINER + GRANT EXECUTE TO service_role only
--   - Returns jsonb (R+S rows union) for caller-side filtering
--   - Hermetic via PostgREST tx=rollback (caller responsibility)
--
-- WHY THIS IS SAFE
-- ────────────────
-- The helper inserts plausible-but-marker-named rows (applicant_name and
-- member name = '__test_invariant_synthetic__'; emails prefixed
-- '__test_invariant_*'). Any leak (helper called without tx=rollback) is
-- visually identifiable AND filterable via the email/name prefix. The
-- SECURITY DEFINER + service_role-only GRANT prevents authenticated callers
-- from poisoning prod data.
--
-- ROLLBACK
-- ────────
-- DROP FUNCTION public._test_invariants_with_synthetic_breach(text);
-- The behavioural tests SKIP cleanly when SUPABASE_SERVICE_ROLE_KEY is unset
-- and treat a missing helper as a test runtime failure (catch + log clearly).
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

CREATE OR REPLACE FUNCTION public._test_invariants_with_synthetic_breach(p_breach text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cycle_id uuid;
  v_org_id uuid;
  v_test_email text;
  v_result jsonb;
BEGIN
  IF p_breach NOT IN ('R', 'S') THEN
    RAISE EXCEPTION 'Invalid p_breach value: % (must be ''R'' or ''S'')', p_breach;
  END IF;

  -- Pick a real cycle to satisfy FK. Most-recent created cycle keeps the
  -- synthetic row plausible. The synthetic application itself never persists
  -- (caller must use Prefer: tx=rollback).
  SELECT id, organization_id
  INTO v_cycle_id, v_org_id
  FROM public.selection_cycles
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_cycle_id IS NULL THEN
    RAISE EXCEPTION 'No selection_cycles available — cannot seed synthetic breach';
  END IF;

  -- Email is unique per call (gen_random_uuid) so concurrent helper runs do
  -- not collide on the same synthetic row.
  v_test_email := '__test_invariant_' || lower(p_breach) || '_' ||
                  replace(gen_random_uuid()::text, '-', '') || '@invariant.test';

  -- Always insert the synthetic approved application.
  INSERT INTO public.selection_applications (
    cycle_id, organization_id, applicant_name, email, role_applied, status
  ) VALUES (
    v_cycle_id, v_org_id,
    '__test_invariant_synthetic__', v_test_email,
    'researcher', 'approved'
  );

  -- For S: also insert a synthetic member matching the email but with
  -- person_id=NULL (the breach condition).
  -- For R: skip — the absence of a matching member IS the breach condition.
  IF p_breach = 'S' THEN
    INSERT INTO public.members (
      organization_id, name, email, member_status, person_id, chapter
    ) VALUES (
      v_org_id, '__test_invariant_synthetic__', v_test_email,
      'active', NULL, 'Outro'
    );
  END IF;

  -- Read both R and S rows from the invariants function. Caller filters.
  SELECT jsonb_agg(row_to_json(t) ORDER BY t.invariant_name)
  INTO v_result
  FROM public.check_schema_invariants() t
  WHERE t.invariant_name IN (
    'R_approved_application_has_member',
    'S_approved_member_has_person_id'
  );

  RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public._test_invariants_with_synthetic_breach(text) IS
'TEST-ONLY helper for GAP-204.B behavioural tests. Seeds a synthetic R or S invariant violation (selection_applications + optional members) and returns both invariant rows from check_schema_invariants(). Caller MUST use Prefer: tx=rollback to avoid persisting the synthetic rows. GRANT EXECUTE limited to service_role; never expose to authenticated or anon. Mirrors _test_detect_inactive_with_threshold pattern (p186 OPP-185.A).';

REVOKE EXECUTE ON FUNCTION public._test_invariants_with_synthetic_breach(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._test_invariants_with_synthetic_breach(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public._test_invariants_with_synthetic_breach(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public._test_invariants_with_synthetic_breach(text) TO service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
