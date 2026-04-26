-- Track Q-D canonical classification helper (p59 follow-up)
-- (v1 — superseded by v2 below; this file keeps history for migration replay)
-- See `_audit_classify_function_gate(text)` final body in v2 migration
-- 20260426164800_track_q_d_canonical_classification_v2_broader_regex.sql

CREATE OR REPLACE FUNCTION public._audit_classify_function_gate(p_function_name text)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'proname', p.proname,
    'sig', pg_get_function_identity_arguments(p.oid),
    'gate_kind',
    CASE
      WHEN p.prosrc ~ '\mcan_by_member\s*\(' THEN 'V4_can_by_member'
      WHEN p.prosrc ~ '(public\.)?\mcan\s*\(\s*(person_id|me_person|target_person|p_person|me_pid|v_person|caller|p_caller)' THEN 'V4_can'
      WHEN p.prosrc ~ '(is_superadmin|operational_role)' THEN 'V3_legacy'
      WHEN p.prosrc ~ 'auth\.uid\s*\(\s*\)' THEN 'CUSTOM_auth_uid'
      ELSE 'NO_GATE'
    END,
    'is_secdef', p.prosecdef,
    'body_chars', length(p.prosrc)
  )
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = p_function_name
  LIMIT 1;
$$;

REVOKE EXECUTE ON FUNCTION public._audit_classify_function_gate(text) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public._audit_classify_function_gate(text) IS
  'Track Q-D canonical classification helper (p59): returns gate_kind for a public-schema function using strengthened regex. Catches `can(person_id, ...)` without `public.` prefix that p55 original regex missed (caused 9 V4-discovered false positives). Service-role only. Used by tests/contracts/track-q-d-classification.test.mjs.';

NOTIFY pgrst, 'reload schema';
