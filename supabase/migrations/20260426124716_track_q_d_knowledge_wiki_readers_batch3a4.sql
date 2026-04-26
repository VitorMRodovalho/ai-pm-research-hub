-- Track Q-D — knowledge/wiki readers hardening (batch 3a.4)
--
-- Discovery (p58 continuation, post 3a.3b):
-- 9 SECDEF readers in knowledge/wiki bucket. Per-fn callsite analysis:
--
-- (a) Live with authenticated callers — REVOKE FROM PUBLIC, anon
--     (keep authenticated):
-- - get_wiki_page(text) — wiki page reader. Caller: MCP tool
--   `get_wiki_page` (nucleo-mcp/index.ts:1444). MCP runs as
--   authenticated user via OAuth2.1 → JWT. Returns wiki_pages.*
--   (id, path, title, domain, content, summary, tags, authors,
--   license, ip_track, source_sha, synced_at, updated_at). Wiki
--   source repo is private (Obsidian vault per CLAUDE.md). PII risk:
--   wiki_health_report scans for email/phone/CPF patterns →
--   confirms members may paste PII into wiki content. Tightening
--   anon access closes the gap (anon could currently fetch any
--   wiki page directly via PostgREST).
-- - search_knowledge(text) — Global Search RPC. Caller:
--   /api/search.ts (W90 command palette). API route REQUIRES
--   Authorization Bearer + valid session (returns 401 if absent).
--   Direct anon-key PostgREST calls bypass the API gate. REVOKE
--   FROM anon enforces the API tier at DB layer.
-- - search_wiki_pages(text, integer, text, text) — wiki search
--   with FTS + headline. Caller: MCP tool `search_wiki`
--   (nucleo-mcp/index.ts:1433). Same MCP authenticated pattern.
-- - wiki_health_report() — health check (stale pages, PII
--   warnings, missing metadata). Admin-shape report. Caller: MCP
--   tool `wiki_health_report` (nucleo-mcp/index.ts:1471). MCP
--   authenticated.
--
-- (b) Dead — no callers in src/, supabase/functions/, scripts/, tests/:
-- - knowledge_assets_latest(text, integer) — knowledge asset
--   metadata reader. 0 callers found. Treatment: REVOKE FROM
--   PUBLIC, anon, authenticated (full lock-down per Q-D dead
--   matrix).
-- - knowledge_search(vector, integer, text) — vector embedding
--   semantic search. 0 callers (likely future MCP integration).
--   Full lock-down.
-- - knowledge_insights_backlog_candidates(text, integer) —
--   insights backlog reader. 0 callers. Already lacks anon grant
--   (postgres + authenticated + service_role only). Tightening
--   to fully dead status (REVOKE authenticated too) per Q-D
--   dead-matrix consistency.
-- - knowledge_insights_overview(text, integer) — same pattern as
--   backlog_candidates. 0 callers. Full lock-down.
-- - knowledge_search_text(text, text, integer) — text-based
--   knowledge search. 0 callers. Already anon-clean. Full
--   lock-down.
--
-- Total: 9 fns triaged. Treatment matrix application: 4 live
-- REVOKE-from-anon + 5 dead REVOKE-only.
--
-- Risk: zero. No frontend, EF, or test callsite is broken.
-- Authenticated callers via MCP / API route preserved for the
-- 4 live fns. Dead fns become un-callable from external clients.
-- Postgres + service_role retained on all 9 (cron + EF still
-- functional if needed).

-- ============================================================
-- (a) Live with authenticated callers — REVOKE-from-anon
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.get_wiki_page(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.search_knowledge(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.search_wiki_pages(text, integer, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.wiki_health_report() FROM PUBLIC, anon;

-- ============================================================
-- (b) Dead — REVOKE-only full lock-down
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.knowledge_assets_latest(text, integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.knowledge_search(vector, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.knowledge_insights_backlog_candidates(text, integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.knowledge_insights_overview(text, integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.knowledge_search_text(text, text, integer) FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
