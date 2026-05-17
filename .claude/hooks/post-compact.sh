#!/bin/bash
# Post-compaction context re-injection
# When Claude Code compresses the conversation, critical context may be lost.
# This hook re-injects the essential state.

cat <<'CONTEXT'
=== POST-COMPACTION CONTEXT RESTORED ===

Platform: nucleoia.vitormr.dev | MCP v2.70.0 | 289 MCP tools | 1440 tests pass / 0 fail / 39 skip
Supabase: ldrfrvwhxsmgaabwmaik | sa-east-1
Worker: platform (Cloudflare Workers, custom domain)
Migrations head: 20260676100000+

CRITICAL RULES:
- GC-097: npx astro build + npm test BEFORE every commit
- LGPD: No anon access to PII tables (GC-162)
- checkOrigin: false + manual CSRF in middleware (OAuth/MCP need cross-origin POST)
- i18n: ALL keys in 3 locales (pt-BR, en-US, es-LATAM)
- SQL: members uses 'name' not 'full_name', designations is text[] not jsonb
- DDL must use mcp__claude_ai_Supabase__apply_migration (not execute_sql)
- engagements.granted_by FK → persons(id), NOT members(id)
- Before CREATE OR REPLACE FUNCTION: SEMPRE pg_get_functiondef ANTES (p172 sediment)

MCP: @modelcontextprotocol/sdk@1.29.0 | OAuth via Workers | Zod 4.3.6
Domain: nucleoia.vitormr.dev (canonical) | .workers.dev redirects 301
Schema invariants: 16 (A1-A3, B-F, J-Q) via check_schema_invariants()

See .claude/rules/ for detailed rules per area.
=== END CONTEXT ===
CONTEXT
