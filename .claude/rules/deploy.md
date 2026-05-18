---
description: Deployment rules and verification
globs: wrangler.toml, astro.config.mjs
---

# Deployment Rules

## Pre-Deploy Checklist
1. `npx astro build` — must pass with 0 errors
2. `npm test` — 1444 pass, 0 fail, 45 skip (offline CI baseline); with DB env: 1495 pass, 0 fail, 5 skip (Phase C 3 tests + Q-C/p65/Pacote M unlocks + p185 admin_audit_log allowlist fix + 3 detect_inactive_members contract tests incl. p186 INSERT-path hermetic helper) — last updated p186 (was 1443/0/42 offline at p181 pin; bumped p185 +1/+2skip and p186 +1skip hermetic INSERT-path test via _test_detect_inactive_with_threshold helper)
3. No legacy URLs in code (grep for platform.ai-pm-research-hub.workers.dev)

## Deploy Commands
- **Worker:** `npx wrangler deploy`
- **Edge Functions:** `supabase functions deploy <name> --no-verify-jwt`
- **Migrations:** Apply via Supabase MCP, then `supabase migration repair --status applied TIMESTAMP`

## Domain Architecture
- Canonical: `nucleoia.vitormr.dev` (custom domain on Cloudflare zone vitormr.dev)
- Legacy: `platform.ai-pm-research-hub.workers.dev` (301 redirect via middleware)
- MCP endpoint: `nucleoia.vitormr.dev/mcp`
- Supabase: `ldrfrvwhxsmgaabwmaik.supabase.co`

## CSRF Middleware
- `checkOrigin: false` in astro.config (Astro's check runs before middleware, blocks OAuth/MCP)
- Manual CSRF in `src/middleware.ts`: bypasses /oauth/, /mcp, /.well-known/; checks origin for all other POSTs
