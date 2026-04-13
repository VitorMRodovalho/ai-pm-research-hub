---
description: Deployment rules and verification
globs: wrangler.toml, astro.config.mjs
---

# Deployment Rules

## Pre-Deploy Checklist
1. `npx astro build` — must pass with 0 errors
2. `npm test` — 1184 pass, 0 fail
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
