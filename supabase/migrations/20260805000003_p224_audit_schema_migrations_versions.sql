-- p224 WATCH-185 / ADR-0097 — Schema migrations drift audit helper RPC
--
-- Returns one row per tracked migration: (version, name, has_body).
-- Consumed by tests/contracts/rpc-migration-coverage.test.mjs to compute
-- 3 set-difference ratchet assertions against p224 baselines:
--   - missing files (tracked - local) ≤ 694
--   - orphan local (local - tracked) ≤ 15
--   - empty statements (has_body=false) ≤ 41
--
-- SECURITY DEFINER required: supabase_migrations.schema_migrations is owned
-- by postgres and not exposed via PostgREST table API to service_role/
-- authenticated. The function elevates to read this internal schema, but
-- returns only version + name + boolean — no body content, no PII.
--
-- ADR cross-ref: ADR-0097 (migration history drift accepted + ratchet).
-- Discovery cross-ref: P162 log #185 (WATCH-AUDIT-HIGH-17).

CREATE OR REPLACE FUNCTION public._audit_list_schema_migrations()
RETURNS TABLE(version text, name text, has_body boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    sm.version::text,
    sm.name::text,
    (sm.statements IS NOT NULL AND array_length(sm.statements, 1) > 0) AS has_body
  FROM supabase_migrations.schema_migrations sm
  ORDER BY sm.version;
$$;

COMMENT ON FUNCTION public._audit_list_schema_migrations() IS
  'p224 WATCH-185 / ADR-0097 — Migration history drift audit helper. Returns version + name + has_body for every tracked migration. Consumed by rpc-migration-coverage.test.mjs ratchet (missing/orphan/empty allowlist enforcement).';

REVOKE ALL ON FUNCTION public._audit_list_schema_migrations() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._audit_list_schema_migrations() TO service_role;

NOTIFY pgrst, 'reload schema';
