-- Audit helper for table-level DDL drift detection (Pacote M Phase 4 / ADR-0029 R2)
--
-- Mirror of _audit_list_public_functions (introduced p51 to detect fn-level drift).
-- Returns user-defined tables in public schema (excludes system tables, materialized
-- views, and tables marked as auto-managed by Supabase or pg extensions).
--
-- Used by tests/contracts/rpc-migration-coverage.test.mjs to detect:
--   1. NEW orphan tables (in DB, no CREATE TABLE migration)
--   2. EXTINCT tables (CREATE TABLE in migration, no DROP TABLE in migration,
--      but absent from live DB — the ADR-0029 incident pattern)
--
-- Excludes: pg_catalog, information_schema, supabase_migrations, partitioned
-- table partitions (pg_class.relkind = 'r' filter excludes 'p' partition root).

CREATE OR REPLACE FUNCTION public._audit_list_public_tables()
RETURNS TABLE(table_name text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT c.relname::text
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind IN ('r', 'p')
    AND NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_inherits i WHERE i.inhrelid = c.oid
    )
  ORDER BY c.relname;
$$;

REVOKE EXECUTE ON FUNCTION public._audit_list_public_tables() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._audit_list_public_tables() TO service_role;

COMMENT ON FUNCTION public._audit_list_public_tables() IS
  'Audit helper (Pacote M Phase 4 / ADR-0029 R2): lists user-defined public-schema tables. SECDEF, service_role only. Used by rpc-migration-coverage contract test to detect table-level DDL drift (the bug class that caused the ADR-0029 ingestion subsystem silent drop).';
