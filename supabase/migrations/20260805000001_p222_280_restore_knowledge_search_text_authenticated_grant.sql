-- p222 #280 alpha Council HIGH-2 fix
--
-- Restore authenticated grant on public.knowledge_search_text(text, text, integer).
--
-- Origin: migration 20260426124716 (Track Q-D batch 3a.4, p58) REVOKE'd EXECUTE from
-- public/anon/authenticated as part of dead-fn cleanup, with the explicit rationale
-- "0 callers found in src/, supabase/functions/, scripts/, tests/" — treating the
-- function as dead-matrix lockdown for consistency.
--
-- Current state: the dead-matrix predicate no longer holds. Two authenticated callers
-- now exist:
--   1. supabase/functions/nucleo-mcp/index.ts /mcp tool `knowledge_search_text`
--      (registered at line 3455+, latent permission-denied since p58 — never reported
--      because graceful degradation masked it).
--   2. supabase/functions/nucleo-mcp/index.ts /mcp/semantic tool `search_nucleo_knowledge`
--      (registered p222 #280 alpha — depends on knowledge_assets source per SPEC-280.B).
--
-- Restoring the grant fixes both surfaces with one migration. The underlying
-- knowledge_assets table is synced wiki + external research (non-PII narrative
-- knowledge per ADR-0010 wiki narrative scope). search_wiki_pages has identical
-- authenticated grant (granted on the same date, same migration kept it for
-- live callers). Restoring keeps the public knowledge surface consistent.
--
-- Rollback: REVOKE EXECUTE ON FUNCTION public.knowledge_search_text(text, text, integer)
-- FROM authenticated; if dead-matrix lockdown becomes desired again.

GRANT EXECUTE ON FUNCTION public.knowledge_search_text(text, text, integer) TO authenticated;

COMMENT ON FUNCTION public.knowledge_search_text(text, text, integer) IS
  'Full-text search over knowledge_assets. SECURITY DEFINER. Authenticated callers: /mcp tool knowledge_search_text + /mcp/semantic tool search_nucleo_knowledge (p222 #280). Re-granted to authenticated after p58 REVOKE became obsolete due to live callers — see migration 20260805000001.';

NOTIFY pgrst, 'reload schema';
