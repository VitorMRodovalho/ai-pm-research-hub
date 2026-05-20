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
-- Defense in depth:
--   1. SECURITY DEFINER + REVOKE FROM PUBLIC/anon/authenticated + GRANT TO
--      service_role only — PostgREST will return 403 for any authenticated
--      JWT or anon call. PUBLIC revoke alone would cascade, but the explicit
--      anon + authenticated revokes match the p186 sibling defensively.
--   2. In-body runtime role guard (`current_setting('role')` check) — even if
--      a future migration accidentally GRANTs to authenticated, the body
--      raises Unauthorized at runtime. Belt-and-suspenders matching the
--      p186 `_test_detect_inactive_with_threshold` pattern.
--   3. Marker-named rows (applicant_name and member name =
--      '__test_invariant_synthetic__'; emails prefixed '__test_invariant_*'
--      on @invariant.test which is not a real TLD). Any leak (caller forgets
--      Prefer: tx=rollback) is visually identifiable AND filterable.
--   4. The next session boot will surface a leak via R or S invariant
--      reporting violation_count > 0 — platform-guardian flags as BLOCKER.
--
-- LEAK CLEANUP (run only if Prefer: tx=rollback was forgotten by a caller)
-- ──────────────────────────────────────────────────────────────────────
-- The synthetic rows are filterable. To clean any leaked rows, run:
--   DELETE FROM public.members WHERE email LIKE '\_\_test\_invariant\_%@invariant.test' ESCAPE '\';
--   DELETE FROM public.selection_applications WHERE email LIKE '\_\_test\_invariant\_%@invariant.test' ESCAPE '\';
-- The DELETEs MUST run in this order (members first, then applications) to
-- avoid FK constraint violations on members.organization_id-derived rows.
-- Re-run check_schema_invariants() afterwards to confirm R=0 + S=0.
--
-- ROLLBACK
-- ────────
-- DROP FUNCTION public._test_invariants_with_synthetic_breach(text);
-- The behavioural tests SKIP cleanly when SUPABASE_SERVICE_ROLE_KEY is unset
-- and treat a missing helper as a test runtime failure (catch + log clearly).
-- If leaked rows exist before DROP, run the LEAK CLEANUP block above first.
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
  -- Belt-and-suspenders runtime role guard. The GRANT/REVOKE pattern is the
  -- primary defense, but if a future migration accidentally widens EXECUTE
  -- (e.g., `GRANT EXECUTE ON FUNCTION ... TO authenticated`) this in-body
  -- check fails closed. Mirrors p186 _test_detect_inactive_with_threshold
  -- pattern parity (council Tier 1 platform-guardian F1, p206).
  IF current_setting('role', true) NOT IN ('service_role', 'postgres')
     AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: _test_invariants_with_synthetic_breach requires service_role';
  END IF;

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
