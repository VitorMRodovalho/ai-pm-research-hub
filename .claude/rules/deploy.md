---
description: Deployment rules and verification
globs: wrangler.toml, astro.config.mjs
---

# Deployment Rules

## Pre-Deploy Checklist

1. `npx astro build` — must pass with 0 errors

2. `npm test` baselines (last updated **p192 — 2026-05-18**):
   - **Offline CI** (no DB env): **1447 pass / 0 fail / 46 skip**
   - **With DB env** (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY): **1499 pass / 0 fail / 5 skip**
   - Coverage delta vs prior baselines: Phase C 3 tests + Q-C/p65/Pacote M unlocks + p185 admin_audit_log allowlist fix + 4 `detect_inactive_members` contract tests (dry_run shape + tx=rollback runtime + p186 INSERT-path hermetic helper + p187 misuse-path defensive restore) + 2 p188 `member_cycle_history` self-read static tests (GAP-181.B closure) + 1 p192 `exec_cross_initiative_comparison` p_kind dispatch test (OPP-191.A close inline LOW).
   - Drift history (newest → oldest): p192 +1 pass (p_kind dispatch static); p188 +2 pass (static mch_self_read tests); p187 +1 skip (misuse-path); p186 +1 skip (INSERT-path hermetic); p185 +1 pass admin_audit_log allowlist + +2 skip detect-inactive non-dry-run; p181 pin = 1443/0/42 offline (corrected silent drift from p175 pin of 1442).
   - Update protocol: each session that adds/removes a test MUST bump the offline + with-env counts inline (manual ratchet — see WATCH-186.C for automation backlog).

3. No legacy URLs in code (`grep` for `platform.ai-pm-research-hub.workers.dev`)

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
