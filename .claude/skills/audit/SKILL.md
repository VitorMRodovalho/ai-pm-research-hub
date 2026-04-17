---
name: audit
description: Run a comprehensive audit of the platform — docs, URLs, tests, security, structural invariants (ADR-0012), ADR coverage, and Supabase advisor drift.
user_invocable: true
---

Run a full platform audit. Checks:

## Infra / URLs / Build
1. **Legacy URLs**: `grep -rn "platform.ai-pm-research-hub.workers.dev\|mcp.vitormr.dev\|ai-pm-research-hub.pages.dev" src/ supabase/ docs/ *.md --include="*.ts" --include="*.astro" --include="*.md" 2>/dev/null`
2. **Build**: `npx astro build` — 0 errors
3. **Tests**: `npm test` — count pass/fail (baseline: 1186+ pass)
4. **Domain**: `curl -sI https://nucleoia.vitormr.dev/ | head -3`
5. **EF health**: `curl -s https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/health`
6. **OAuth flow**: Test register + authorize + POST /mcp endpoints

## i18n / Localization
7. **i18n parity**: Count keys in each locale file (pt-BR, en-US, es-LATAM), flag differences
8. **Missing i18n redirects**: Compare `ls src/pages/*.astro` vs `ls src/pages/en/*.astro` and `src/pages/es/*.astro`

## Security
9. **Hardcoded secrets**: Grep for API keys, tokens, service role keys in source (not in .env)
10. **Supabase advisors**: Via MCP `get_advisors(type='security')` and `type='performance'`. Report ERRORs (baseline: ~12 intentional + 0 new), WARNs (baseline: ~9), INFOs
11. **RLS coverage**: List public tables without RLS enabled

## Structural invariants (ADR-0012)
12. **check_schema_invariants()**: Via MCP `execute_sql`:
    ```sql
    SELECT invariant_name, severity, violation_count FROM public.check_schema_invariants() ORDER BY invariant_name;
    ```
    Expected: 8 rows, all `violation_count = 0`. Any non-zero is a BLOCKER.
13. **Contract tests (DB-side)**: If `SUPABASE_SERVICE_ROLE_KEY` env var is set, run `npm run test:contracts:db`. Otherwise skip gracefully.

## ADR coverage / Knowledge drift
14. **CLAUDE.md metrics drift**: Compare advertised counts to reality
    - MCP tools: `grep -c 'mcp\.tool(' supabase/functions/nucleo-mcp/index.ts` vs CLAUDE.md line "76 MCP tools"
    - Edge Functions: `ls supabase/functions/ | wc -l` vs CLAUDE.md "22 Edge Functions"
    - Tests: last `npm test` output vs CLAUDE.md "1184 unit + 40 e2e"
    - Version: CLAUDE.md "v3.2.0" vs `docs/RELEASE_LOG.md` top entry
15. **Migration tracking**: Via MCP, compare count of files in `supabase/migrations/` to rows in `supabase_migrations.schema_migrations`. Any file missing a tracking row?
16. **ADR index**: List `docs/adr/*.md` vs `docs/adr/README.md` — any ADR file not indexed?

## Backlog / Knowledge
17. **TODO/FIXME inventory**: `grep -rn "TODO\|FIXME\|XXX\|HACK" src/ supabase/ --include="*.ts" --include="*.astro" --include="*.sql"` — candidates for `project_issue_gap_opportunity_log.md`
18. **Stale memory entries**: List `memory/*.md` files older than 30 days mentioning features — candidates for review

## Output

Report as table:

| Check | Status | Detail / Drift | Action |
|---|---|---|---|

At the bottom, summarize:
- BLOCKERs (check 12 violations, any security ERROR new, missing RLS)
- HIGH drift (docs count > 10% off, ADR missing, migration untracked)
- MEDIUM (i18n parity, legacy URLs)
- Backlog candidates (count of TODO items, stale memories)

If BLOCKERs > 0, halt and recommend remediation before any deploy.
