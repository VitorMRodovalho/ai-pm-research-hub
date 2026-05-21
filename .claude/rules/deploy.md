---
description: Deployment rules and verification
globs: wrangler.toml, astro.config.mjs
---

# Deployment Rules

## Pre-Deploy Checklist

1. `npx astro build` — must pass with 0 errors

2. `npm test` baselines (last updated **p216 — 2026-05-21** via GAP-205.D PR + Council amendments):
   - **Offline CI** (no DB env): **1587 pass / 0 fail / 42 skip** *(confirmed p216 post-amendments — p215 baseline 1558 + 22 initial GAP-205.D assertions + 7 council amendment assertions in `tests/contracts/member-emails-write-surface.test.mjs`)*
   - **With DB env** (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY): **~1609 pass / 0 fail / 5 skip** *(p216 — p215 with-DB pin was 1580 + 29 GAP-205.D static tests run identically in both env modes)*
   - Coverage delta vs prior baselines: Phase C 3 tests + Q-C/p65/Pacote M unlocks + p185 admin_audit_log allowlist fix + 4 `detect_inactive_members` contract tests (dry_run shape + tx=rollback runtime + p186 INSERT-path hermetic helper + p187 misuse-path defensive restore) + 2 p188 `member_cycle_history` self-read static tests (GAP-181.B closure) + 1 p192 `exec_cross_initiative_comparison` p_kind dispatch test (OPP-191.A close inline LOW) + 2 p194 contract tests (GAP-192.C total_hours + GAP-194.A members_inactive_30d strict scope) + 9 p212 #224 admin-selection-import-error-rendering contract tests + 4 p212 #237 onboarding-token-organization-id contract tests + 11 p214 GAP-205.A/B member-emails RLS multi-tenant + 2 p215 GAP-205.C verified_at absence forward-defense + **22 p216 GAP-205.D write-surface (3 RPCs × ~7 assertions each: existence + SECDEF/search_path + auth gate + primary-rejection + GRANT EXECUTE + MCP registration + version/health label parity) + 7 p216 council amendments (HIGH LGPD generic msg + MED #1 FOR UPDATE + MED #2 org boundary anchor × 3 RPCs + LOW #1 generic remove primary msg)**.
   - p196/p197/p198 added 0 tests despite 10 migrations + new RPCs (GAP-197.G: 0 contract tests pros 2 RPCs novos `complete_peer_review` + `complete_leader_review` — backlog).
   - Drift history (newest → oldest): **p216 +29** (22 GAP-205.D + 7 council amendments); p215 +2 (column-absence assertions #12 + #13); p214 +11 (RLS multi-tenant suite); p212 +13 (1490→1503 admin-selection + onboarding-token); p198 update (1447→1449 silent drift since p194); p192 +1 pass (p_kind dispatch static); p188 +2 pass (static mch_self_read tests); p187 +1 skip (misuse-path); p186 +1 skip (INSERT-path hermetic); p185 +1 pass admin_audit_log allowlist + +2 skip detect-inactive non-dry-run; p181 pin = 1443/0/42 offline (corrected silent drift from p175 pin of 1442).
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
