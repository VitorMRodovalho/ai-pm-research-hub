---
description: Deployment rules and verification (build, test, deploy commands, domain, CSRF)
paths:
  - "wrangler.toml"
  - "astro.config.mjs"
  - "supabase/migrations/**"
  - "supabase/functions/**"
---

# Deployment Rules

## Pre-Deploy Checklist

1. `npx astro build` — must pass with 0 new errors.

2. `npm test` — must be 0 fail. **Do NOT pin or recite a baseline count from memory or from this file** —
   the current pass/skip totals change every session, so the live source of truth is *running the command*.
   (Official guidance: frequently-changing data must not live in always-loaded rules — it bloats context and
   it is the exact thing that gets stated as a stale "fact". See `reference_process_fix_and_context_hygiene_2026_05_30`.)
   - Offline (no DB env) vs with-DB (`SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`) differ: with-DB runs the
     DB-gated contract tests that otherwise skip. CI runs with-DB via repo secrets.
   - ⚠️ **The with-DB suite WRITES to production and does not clean up after itself** (`tx=rollback` does not
     undo a SECURITY DEFINER INSERT). It therefore does NOT tolerate concurrent execution: two suites over the
     same database see each other's rows. Measured 2026-07-28 (#1505) — two CI runs in the same 7-minute window
     failed on DIFFERENT subtests of the SAME files, and the same commit passed alone on re-run. CI now
     serializes via the repo-global concurrency group `supabase-shared-db` (job-level, `cancel-in-progress:
     false`), but that group does NOT know about your laptop: **do not run `npm test` locally while a CI run is
     in flight** (`gh run list --limit 5` before starting). A red that vanishes on re-run is the signature —
     classify it as this before hunting a code cause, and never merge over it.
   - When you add/remove a test, register it in BOTH the `"test"` and `"test:contracts"` whitelists in
     `package.json` (SEDIMENT-186.C) before running.
   - Pre-trim baseline-history narrative archived at `docs/audit/DEPLOY_TEST_BASELINE_HISTORY_ARCHIVED_2026-05-30.md`.

3. No legacy URLs in code (`grep` for `platform.ai-pm-research-hub.workers.dev`).

4. **Local QA workflow**: see `docs/operations/LOCAL_QA.md` (issue #164). Default = remote-linked; local stack
   optional after `supabase db pull --linked`. Migration `20260723000000_baseline_rpcs_after_schema.sql` fixes
   the ordering bug that blocked `supabase start`.

## Deploy Commands
- **Worker:** `npx wrangler deploy`
- **Edge Functions:** `supabase functions deploy <name> --no-verify-jwt`
- **Migrations:** apply via Supabase MCP `apply_migration`, then write the local file + `supabase migration repair
  --status applied <timestamp>` + `NOTIFY pgrst` (GC-097 ritual — see `.claude/rules/database.md`).

## Domain Architecture
- Canonical: `nucleoia.vitormr.dev` (custom domain on Cloudflare zone vitormr.dev)
- Legacy: `platform.ai-pm-research-hub.workers.dev` (301 redirect via middleware)
- MCP endpoint: `nucleoia.vitormr.dev/mcp`
- Supabase: `ldrfrvwhxsmgaabwmaik.supabase.co`

## CSRF Middleware
- `checkOrigin: false` in astro.config (Astro's check runs before middleware, blocks OAuth/MCP)
- Manual CSRF in `src/middleware.ts`: bypasses /oauth/, /mcp, /.well-known/; checks origin for all other POSTs
