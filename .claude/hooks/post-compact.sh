#!/bin/bash
# Post-compaction context re-injection
# When Claude Code compresses the conversation, critical context may be lost.
# This hook re-injects the essential state.

cat <<'CONTEXT'
=== POST-COMPACTION CONTEXT RESTORED ===

Platform: nucleoia.vitormr.dev | v2.2.1 | 23 MCP tools | 19 EFs | 779 tests
Supabase: ldrfrvwhxsmgaabwmaik | sa-east-1
Worker: platform (Cloudflare Workers, custom domain)

CRITICAL RULES:
- GC-097: npx astro build + npm test BEFORE every commit
- LGPD: No anon access to PII tables (GC-162)
- checkOrigin: false + manual CSRF in middleware (OAuth/MCP need cross-origin POST)
- i18n: ALL keys in 3 locales (pt-BR, en-US, es-LATAM)
- SQL: members uses 'name' not 'full_name', designations is text[] not jsonb

MCP: @modelcontextprotocol/sdk@1.12.1 | OAuth via Workers | 23 tools in registerTools()
Domain: nucleoia.vitormr.dev (canonical) | .workers.dev redirects 301

See .claude/rules/ for detailed rules per area.
=== END CONTEXT ===
CONTEXT
