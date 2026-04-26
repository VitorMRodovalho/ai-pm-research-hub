-- Track Q-D canonical classification helper v2 (p59 follow-up correction)
-- v1 (migration 20260426164612) was too narrow: required exact identifier
-- match (person_id|caller|...) after `can(`. Missed `v_caller_person_id`,
-- `(SELECT id FROM persons)`, and other valid V4 patterns.
--
-- v2 broadens detection:
-- - V4_can_by_member: any call to can_by_member()
-- - V4_can: any call to (public.)?can( where first arg matches:
--   * `\w*person_id` (catches v_caller_person_id, p_caller_person_id)
--   * `<table_alias>.id` (catches p.id, m.id from joined records)
--   * `(SELECT id FROM persons WHERE ...)` (sub-query patterns in
--      can_by_member-style wrappers)
-- - Conservative classification: if NOT V4 + has V3-style gate, classify
--   as V3_legacy. Otherwise CUSTOM_auth_uid or NO_GATE.

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
      -- V4_can_by_member: any call to can_by_member() with at least one arg
      WHEN p.prosrc ~* '\mcan_by_member\s*\(' THEN 'V4_can_by_member'

      -- V4_can: call to (public.)?can() where:
      --   - first arg looks like an identifier ending in person_id/id, OR
      --   - first arg is a sub-query selecting person_id/id (rare but valid)
      -- Catches: can(v_caller_person_id, ...), can(p.id, ...),
      --          public.can((SELECT id FROM persons), ...),
      --          can(v_person_id, ...)
      WHEN p.prosrc ~* '(public\.)?\mcan\s*\(\s*(\w+\.|\(SELECT\s+)?(\w*person_id|id|p_id|v_id)\s*[,\)]' THEN 'V4_can'

      -- V4_can fallback: call to can() with `_person_id`-suffixed identifier
      -- (catches v_caller_person_id, p_caller_person_id patterns)
      WHEN p.prosrc ~* '(public\.)?\mcan\s*\(\s*\w*_?person_id\b' THEN 'V4_can'

      -- V3_legacy: uses old role/superadmin check
      WHEN p.prosrc ~ '(is_superadmin|operational_role)' THEN 'V3_legacy'

      -- CUSTOM: uses auth.uid() but neither V4 nor V3 (custom path-aware gate)
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

NOTIFY pgrst, 'reload schema';
