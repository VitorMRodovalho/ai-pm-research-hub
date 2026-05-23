-- p224 follow-up — fix PostgREST 1000-row LIMIT artifact on TABLE returns.
-- Previous RPC `_audit_list_schema_migrations()` returned TABLE(version, name, has_body)
-- which PostgREST paginated at 1000 rows (default limit), invalidating set diffs in the
-- ratchet tests. New version returns jsonb aggregate (single row containing array of
-- N objects) which PostgREST does NOT paginate.
--
-- ADR cross-ref: ADR-0097 sediment §4 (PostgREST RPC TABLE return pagination trap).

DROP FUNCTION IF EXISTS public._audit_list_schema_migrations();

CREATE OR REPLACE FUNCTION public._audit_list_schema_migrations()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'version', sm.version::text,
        'name', sm.name::text,
        'has_body', (sm.statements IS NOT NULL AND COALESCE(array_length(sm.statements, 1), 0) > 0)
      )
      ORDER BY sm.version
    ),
    '[]'::jsonb
  )
  FROM supabase_migrations.schema_migrations sm;
$$;

COMMENT ON FUNCTION public._audit_list_schema_migrations() IS
  'p224 WATCH-185 / ADR-0097 — Migration history drift audit helper. Returns single jsonb array of {version, name, has_body} for every tracked migration. Returns jsonb (not TABLE) to bypass PostgREST 1000-row pagination. has_body uses COALESCE to handle empty-array edge case (statements=''{}'' → has_body=false, not NULL).';

REVOKE ALL ON FUNCTION public._audit_list_schema_migrations() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._audit_list_schema_migrations() TO service_role;

NOTIFY pgrst, 'reload schema';
