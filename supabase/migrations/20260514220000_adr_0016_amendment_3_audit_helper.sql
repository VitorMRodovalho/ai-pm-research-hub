-- ADR-0016 Amendment 3 — audit helper for cache↔live drift detection
-- Used by contract test tests/contracts/preview-gate-eligibles-cache-equivalence.test.mjs

CREATE OR REPLACE FUNCTION public._audit_preview_gate_eligibles_drift()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_doc_type text;
  v_gate jsonb;
  v_gate_kind text;
  v_cache_count int;
  v_live_count int;
  v_results jsonb := '[]'::jsonb;
BEGIN
  FOREACH v_doc_type IN ARRAY public._cacheable_preview_doc_types()
  LOOP
    FOR v_gate IN SELECT * FROM jsonb_array_elements(public.resolve_default_gates(v_doc_type))
    LOOP
      v_gate_kind := v_gate->>'kind';
      IF v_gate_kind = 'submitter_acceptance' THEN CONTINUE; END IF;

      SELECT count(*) INTO v_cache_count
      FROM public.preview_gate_eligibles_cache c
      JOIN public.members m ON m.id = c.member_id
      WHERE c.doc_type = v_doc_type
        AND m.is_active = true
        AND v_gate_kind = ANY(c.eligible_gates);

      SELECT count(*) INTO v_live_count
      FROM public.members m
      WHERE m.is_active = true
        AND public._can_sign_gate(m.id, NULL, v_gate_kind, v_doc_type, NULL);

      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'doc_type', v_doc_type,
        'gate_kind', v_gate_kind,
        'cache_count', v_cache_count,
        'live_count', v_live_count,
        'mismatch', v_cache_count <> v_live_count
      ));
    END LOOP;
  END LOOP;

  RETURN v_results;
END;
$$;

COMMENT ON FUNCTION public._audit_preview_gate_eligibles_drift() IS
  'Audit helper: compares preview_gate_eligibles_cache counts vs live _can_sign_gate counts for every (cacheable_doc_type × cacheable_gate). Used by contract test. Returns jsonb array of {doc_type, gate_kind, cache_count, live_count, mismatch:bool}. Service-role-callable (REVOKEd from authenticated/anon).';

REVOKE EXECUTE ON FUNCTION public._audit_preview_gate_eligibles_drift() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._audit_preview_gate_eligibles_drift() FROM anon;
REVOKE EXECUTE ON FUNCTION public._audit_preview_gate_eligibles_drift() FROM authenticated;

NOTIFY pgrst, 'reload schema';
