-- Phase C body-hash drift audit RPC (p175).
--
-- Companion to `_audit_list_public_functions` (Q-C orphan check, p149) that
-- exposes the body-level fingerprint required by the migration body-drift
-- contract test. The two RPCs are split because:
--   * Orphan-check (proname + identity_args) is a small payload sufficient
--     for "is this function captured by any CREATE FUNCTION migration?".
--   * Drift-check needs `md5(regexp_replace(prosrc, '\s+', ' ', 'g'))` and
--     `length(prosrc)` per row — larger payload only the body-drift test
--     actually consumes.
--
-- Returned shape mirrors the JSON schema consumed by both
-- `scripts/audit-rpc-body-drift.mjs` (Node parser) and the new Phase C test.
--
-- The normalization (single regexp_replace of `\s+` → ' ') must match
-- `normalizeBody()` in `tests/helpers/rpc-body-drift-parser.mjs` byte-for-byte;
-- any change here MUST update the helper and bump baseline.
--
-- Security: SECDEF with empty search_path; granted to authenticated +
-- service_role only (no anon). Returns pg_catalog metadata + body hashes,
-- no PII. Body content itself is NOT returned — only the hash + length —
-- so leaking the row set tells an attacker nothing they couldn't infer
-- from already-public CREATE FUNCTION DDL in supabase/migrations/.

CREATE OR REPLACE FUNCTION public._audit_list_public_function_bodies()
RETURNS TABLE(
  proname        text,
  identity_args  text,
  body_md5       text,
  prosrc_len     integer,
  is_secdef      boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    p.proname::text,
    pg_catalog.pg_get_function_identity_arguments(p.oid)::text,
    md5(regexp_replace(p.prosrc, '\s+', ' ', 'g'))::text,
    length(p.prosrc)::integer,
    p.prosecdef
  FROM pg_catalog.pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.prokind = 'f'
    AND NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_depend d
      JOIN pg_catalog.pg_extension e ON e.oid = d.refobjid
      WHERE d.objid = p.oid AND d.deptype = 'e'
    )
  ORDER BY p.proname, p.oid;
$$;

REVOKE ALL ON FUNCTION public._audit_list_public_function_bodies() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._audit_list_public_function_bodies() TO authenticated, service_role;

COMMENT ON FUNCTION public._audit_list_public_function_bodies() IS
  'Phase C body-hash drift audit (p175). Returns project-defined public-schema functions with md5 of whitespace-normalized prosrc + prosrc length. Body text itself NOT returned. Used by tests/contracts/rpc-migration-coverage.test.mjs Phase C tests to detect drift between live function bodies and the latest CREATE FUNCTION migration capture. Body normalization must stay byte-identical to tests/helpers/rpc-body-drift-parser.mjs normalizeBody().';
