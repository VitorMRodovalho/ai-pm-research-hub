---
description: Deployment rules and verification
globs: wrangler.toml, astro.config.mjs
---

# Deployment Rules

## Pre-Deploy Checklist

1. `npx astro build` — must pass with 0 errors

2. `npm test` baselines (last updated **p212 — 2026-05-21** via #237 PR #238):
   - **Offline CI** (no DB env): **1503 pass / 0 fail / 50 skip** *(confirmed p212 close — last documented offline pin was p198's 1449; correctly tracks p211's intermediate +3 = 1490, p212 #224 PR #236's +9 = 1499, and p212 #237 PR #238's +4 = 1503)*
   - **With DB env** (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY): **estimated 1514 pass / 0 fail / 5 skip** *(estimated — last confirmed pin was p192's 1499; +15 corresponds to p194 +2 + p211 +3 + p212 +9 + p212 +4 contract tests minus DB-aware re-additions; verify next time DB env is available)*
   - Coverage delta vs prior baselines: Phase C 3 tests + Q-C/p65/Pacote M unlocks + p185 admin_audit_log allowlist fix + 4 `detect_inactive_members` contract tests (dry_run shape + tx=rollback runtime + p186 INSERT-path hermetic helper + p187 misuse-path defensive restore) + 2 p188 `member_cycle_history` self-read static tests (GAP-181.B closure) + 1 p192 `exec_cross_initiative_comparison` p_kind dispatch test (OPP-191.A close inline LOW) + 2 p194 contract tests (GAP-192.C total_hours + GAP-194.A members_inactive_30d strict scope) + 9 p212 #224 admin-selection-import-error-rendering contract tests + 4 p212 #237 onboarding-token-organization-id contract tests.
   - p196/p197/p198 added 0 tests despite 10 migrations + new RPCs (GAP-197.G: 0 contract tests pros 2 RPCs novos `complete_peer_review` + `complete_leader_review` — backlog).
   - Drift history (newest → oldest): p198 update (1447→1449 silent drift since p194); p192 +1 pass (p_kind dispatch static); p188 +2 pass (static mch_self_read tests); p187 +1 skip (misuse-path); p186 +1 skip (INSERT-path hermetic); p185 +1 pass admin_audit_log allowlist + +2 skip detect-inactive non-dry-run; p181 pin = 1443/0/42 offline (corrected silent drift from p175 pin of 1442).
   - Update protocol: each session that adds/removes a test MUST bump the offline + with-env counts inline (manual ratchet — see WATCH-186.C for automation backlog).

3. No legacy URLs in code (`grep` for `platform.ai-pm-research-hub.workers.dev`)

4. **Local QA workflow**: ver `docs/operations/LOCAL_QA.md` (adopted p202, issue #164 close). Default = remote-linked; local stack opcional após `supabase db pull --linked` bootstrap. Migration `20260723000000_baseline_rpcs_after_schema.sql` resolve o ordering bug que travava `supabase start`.

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
