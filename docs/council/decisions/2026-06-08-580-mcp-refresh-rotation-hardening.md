# Decision — #580 Harden MCP server-side refresh-token rotation

**Date:** 2026-06-08
**Issue:** #580 (surfaced by security-engineer during #234 org-connector enablement)
**PR:** (this session) · **Type:** Worker-deploy (Cloudflare proxy, NOT the EF) · **--admin:** 0
**Decision loop:** PM picked #580 from the PM-agreed hardening wave (top of the queue;
only item with a MEDIUM edge case in critical auth/refresh infra; blinds the multi-day
connector path #234 just enabled).

## Scope (4 acceptance items, all met)

1. **MEDIUM — proxy KV re-store had no fallback.** `tryAutoRefresh` gated the KV write on
   `if (data.refresh_token)`. On a partial 200 (access_token, no rotated refresh_token) the
   old (possibly rotated-invalidated) token lingered → the NEXT auto-refresh 400s → entry
   purged → connector drops to re-auth mid-session.
   **Fix:** `const newRefresh = data.refresh_token || oldToken` then **always** `kv.put` with
   the 30-day TTL.
2. **LOW — `oauth/token.ts` swallowed JWT-decode/KV-store failures** in `catch {}`. Both store
   blocks (refresh_token grant + authorization_code grant) now log `token-refresh-store-error`
   / `token-refresh-store-skip`. **Kept fail-safe**: the client still gets its 200 even if the
   server-side KV store fails (a KV write failure must not break the client's token exchange).
3. **INFO — de-dup.** `decodeJwtPayload` + `tryAutoRefresh` + the 5-min window were copy-pasted
   across `src/pages/mcp.ts` and `src/pages/mcp/semantic.ts`. Extracted to a NEW shared module
   `src/lib/mcp-refresh.ts` (pure, dependency-injected — KV + fetch + anonKey passed in,
   mirroring `mcp-rate-limit.ts`), so the MEDIUM fix lives in ONE place and both proxies inherit
   it. `token.ts` consumes the shared `decodeJwtPayload` + `MCP_REFRESH_TTL_SECONDS`. (The
   broader full-proxy extraction into `mcp-proxy.ts` remains the #280 follow-up.)
4. **LOW — KV-TTL ≤ Supabase-TTL** documented on `MCP_REFRESH_TTL_SECONDS` (single source; the
   literal `2592000` removed from all 3 consumers).

## Council-on-draft (Workflow `wf_1c92c2ff`, 4 reviewers on the working tree)

**4/4 GO_W_FIXES, 0 NO_GO, 0 BLOCKER** (security-engineer, code-reviewer, senior-software-engineer,
ai-engineer). Folded in-PR:

- **`tryAutoRefresh` made total (never throws).** [MEDIUM ×2 + LOW] The original (and the draft)
  did not wrap the fetch/KV calls; a network/KV exception propagated past the proxy's outer
  try/catch → 500/502 crash instead of fail-open. Now: per-step try/catch returns `null` on any
  blip → caller falls open to the original token (upstream 401s if genuinely expired → clean
  re-auth). **Pre-existing gap, but squarely the hardening this PR is for.** A KV-write failure on
  the happy path no longer discards the fresh access_token (best-effort persist); deletes are
  best-effort (`.catch(()=>{})`); transient exceptions do NOT purge the KV entry (only an explicit
  Supabase rejection — non-2xx / 200-without-access_token — does).
- **Empty-anonKey guard.** [LOW security] `if (!config.anonKey) return null` before any KV/fetch.
  Without it, a misconfigured deploy (lost `PUBLIC_SUPABASE_ANON_KEY`) would 401 → hit the purge
  path → **mass-invalidate every connector's server-side refresh** on the next near-expiry request.
- **env-driven `supabaseUrl`.** [NIT/LOW ×4] Both proxies now pass
  `supabaseUrl: import.meta.env.PUBLIC_SUPABASE_URL || undefined`, matching `token.ts`; the lib's
  `DEFAULT_SUPABASE_URL` stays as a fallback. Prod behaviour unchanged (env value == default).
- **Docs.** Partial-200 behavioural invariant (Supabase returns non-2xx on a revoked token, so a
  200 guarantees the submitted token is live → re-storing the old one cannot mask a revocation);
  the `token.ts` `|| refresh_token` client-supplied-fallback asymmetry (safe — only touches the
  caller's own `mcp_refresh:{sub}`).
- **Tests.** +6 cases: empty anonKey (no fetch/no purge), fetch throws (fail-open, no purge),
  kv.get throws, kv.put throws on happy path (still returns the token), kv.delete throws on a
  rejection (no crash), `supabaseUrl` override honored. Redeclaration static check broadened to
  catch arrow-function copies.

**Skipped (reviewers' own "no change needed"):** `DEFAULT_SUPABASE_URL` project-ID hardcode
(consistent with the prior per-file const; `supabaseUrl` overridable); `isExpiringSoon` exact
boundary (already test-documented); the "no empty catch" static regex brittleness (no reuse yet).

## Out of scope (flagged, not touched)

`claude.com` is absent from `TRUSTED_ROOT_HOSTS` in `src/lib/oauth-security.ts` — that is the
**authorize redirect_uri allow-list**, not the refresh path. Not touched here (speculative changes
to a security allow-list need their own decision + evidence). Remains the #234 enablement watch-item:
if a Claude.ai org-connector callback ever uses a `claude.com` apex, the authorize step rejects the
`redirect_uri` and the connector can't link.

## Verification

`astro build` ✅ · full suite **3678/0/0** (DB-gated, `.env` sourced) · new test
`580-mcp-refresh-hardening` (22, BOTH whitelists) ✅ · fix-forward of 1 brittle pre-existing
assertion (`mcp-semantic-gateway-bridge:233` checked `mcp_refresh:` in `semantic.ts` source — moved
to the shared module; assertion updated to validate the shared-import + the prefix in
`lib/mcp-refresh.ts`) · Worker deployed + OAuth smoke (initialize + tools/list 200; refresh-cycle
covered by the 22 unit tests).
