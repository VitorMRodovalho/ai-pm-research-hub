-- ============================================================
-- GC-089 / B3: SET search_path = public, pg_temp on ALL SECURITY DEFINER functions
-- ============================================================
-- Uses pg_catalog to dynamically find and fix all SECURITY DEFINER functions
-- in the public schema that are missing search_path configuration.
-- This prevents search_path injection attacks in SECURITY DEFINER context.

DO $$
DECLARE
  r RECORD;
  stmt TEXT;
  fixed INT := 0;
BEGIN
  FOR r IN
    SELECT
      n.nspname,
      p.proname,
      pg_catalog.pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef = true  -- SECURITY DEFINER
      AND (
        p.proconfig IS NULL
        OR NOT EXISTS (
          SELECT 1 FROM unnest(p.proconfig) AS c WHERE c LIKE 'search_path=%'
        )
      )
  LOOP
    stmt := format(
      'ALTER FUNCTION %I.%I(%s) SET search_path = public, pg_temp;',
      r.nspname, r.proname, r.args
    );
    EXECUTE stmt;
    fixed := fixed + 1;
    RAISE NOTICE 'Fixed: %.%(%)', r.nspname, r.proname, r.args;
  END LOOP;

  RAISE NOTICE 'Total SECURITY DEFINER functions fixed: %', fixed;
END;
$$;
