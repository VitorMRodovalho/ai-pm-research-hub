---
name: audit
description: Run a comprehensive audit of the platform — docs, URLs, tests, security
user_invocable: true
---

Run a full platform audit. Checks:

1. **Legacy URLs**: `grep -rn "platform.ai-pm-research-hub.workers.dev\|mcp.vitormr.dev\|ai-pm-research-hub.pages.dev" src/ supabase/ docs/ *.md --include="*.ts" --include="*.astro" --include="*.md" 2>/dev/null`
2. **Build**: `npx astro build` — 0 errors
3. **Tests**: `npm test` — count pass/fail
4. **i18n parity**: Count keys in each locale file, flag differences
5. **Missing i18n redirects**: Compare `ls src/pages/*.astro` vs `ls src/pages/en/*.astro` and `src/pages/es/*.astro`
6. **EF health**: `curl -s https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/health`
7. **Domain**: `curl -sI https://nucleoia.vitormr.dev/ | head -3`
8. **OAuth flow**: Test register + authorize + POST /mcp endpoints
9. **Security**: Grep for hardcoded secrets, API keys, tokens in source

Report as table: | Check | Status | Detail |
