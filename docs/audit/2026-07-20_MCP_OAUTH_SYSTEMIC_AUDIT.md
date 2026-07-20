# MCP OAuth / DCR - Systemic End-to-End Audit

**Date:** 2026-07-20
**Trigger:** Owner decision to stop chained hotfixes and audit the whole MCP connect flow after 4 OAuth layers were fixed in one session (Site URL, true DCR, consent-hang, client_secret). Two symptoms remained open: Leticia (Claude) `oauth_client_not_found / invalid client_id format`, and Perplexity `Failed to verify OAuth request` after a 200 token exchange.
**Method:** Inline diagnosis + a 4-agent workflow (map + adversarial verify) + owner-run live SQL on the `auth` schema. Every number below comes from a live tool result captured this session (curl, GoTrue admin API, `execute_sql`, git). Deployed head at audit time: main `8a011a01`, EF `nucleo-mcp` 2.90.0.

---

## 1. Verdict

The happy path is healthy and was reproduced live end to end: discovery, true DCR (per-client create), GoTrue authorize, consent, GoTrue-native token, 401 + WWW-Authenticate, initialize, tools/list. A real member (Eduardo Luz) has a working Claude connection through the new per-client DCR path, which proves the pipeline works for a non-owner user.

Both open symptoms are now diagnosed with confirmed root causes. Neither is a new server bug; both are the aftermath of earlier states:

- **Leticia** holds a non-UUID client_id cached by her Claude client from a 38-minute shim window on 2026-03-26. It cannot be repaired server-side. The fix is a client-side reconnect.
- **Perplexity** emits the "Failed to verify" string itself, after our server side completes successfully. The one server-side contributor worth fixing is a resource-metadata mismatch; the rest is Perplexity-client behavior, most likely a mobile in-app-browser state split.

No production OAuth client was deleted during the audit. The two subagent "deletion" security flags were conservative false alarms: `auth.oauth_clients` (which retains soft-deleted rows) confirms every delete targeted an `__audit_*` / `probe` throwaway the agents created and cleaned up in the same run. All 6 real clients are intact.

---

## 2. The flow, mapped (each step verified live)

| Step | Endpoint | Status | Notes |
|---|---|---|---|
| 1. Resource discovery | `/.well-known/oauth-protected-resource` | OK, with caveat | Returns `resource: origin/mcp` hardcoded even when the connector is `/mcp/semantic`. Path-suffixed variant `/.well-known/oauth-protected-resource/mcp/semantic` returns 404. |
| 2. AS metadata | `/.well-known/oauth-authorization-server` | OK | `authorization_endpoint` + `token_endpoint` point at GoTrue native; `registration_endpoint` is our shim; `scopes_supported:[email]`. |
| 3. DCR | `POST /oauth/register` | OK, with trap | True per-client create returns a valid UUID. Silent fallback to shared `8636c0d0` when the sanitized redirect list is empty (see FM-01). |
| 4. Authorize | GoTrue `/auth/v1/oauth/authorize` | OK | Fresh discovery sends clients straight to GoTrue. Our `/oauth/authorize` is a compat passthrough for cached pre-#1210 clients only. |
| 5. Consent | `/oauth/consent` | OK | Client-side SPA, 20s watchdog, always HTTP 200 (a bad `authorization_id` fails only client-side). |
| 6. Token | GoTrue `/auth/v1/oauth/token` | OK | Our `/oauth/token` is a retired stub returning `invalid_grant` for any cached pre-#1210 client. |
| 7. Connect (401) | `/mcp`, `/mcp/semantic`, `/mcp/actions` | OK | Each returns 401 + `WWW-Authenticate` pointing at the same (bare) protected-resource metadata. |
| 8. initialize / tools/list / call | EF `nucleo-mcp` | OK | Verified on all three surfaces (342 / 52 / 88 tools). Auth is enforced at the DB via `auth.uid()` + RLS, not by an audience check. |

**Authorize error taxonomy (fingerprints, live-verified):**

- non-UUID client_id  -> `400 oauth_client_not_found / "invalid client_id format"`  (Leticia)
- valid UUID, no such client  -> `400 oauth_client_not_found / "invalid client_id"` (no "format")
- empty client_id  -> `400 validation_failed / "client_id is required"`
- wrong redirect_uri  -> `400 validation_failed / "invalid redirect_uri"` (hard 400, not redirected)
- missing PKCE  -> `302` to the client callback with `error=invalid_request` (redirected, because the redirect_uri is trusted)

---

## 3. Findings (prioritized)

All findings were passed through an adversarial verifier. Verdicts: FM-01 CONFIRMED, FM-02 CONFIRMED, FM-03 PARTIALLY-CONFIRMED (defect real, strict-client impact is hypothesis), PPX-1 CONFIRMED, PPX-2 REFUTED as a cause (dedup is cosmetic), PPX-3/PPX-5 PARTIALLY-CONFIRMED (hypothesis + test), LR chain CONFIRMED.

### P0 - user-facing, act now

**FM-02 / LR (Leticia) - cached non-UUID client_id, unrescuable server-side.**
GoTrue rejects her cached `nucleo-mcp-xxxxxxxx` at authorize with the exact error she reported. Root cause: a register.ts shim that ran only 2026-03-26 14:51:45 to 15:29:04 returned `client_id: nucleo-mcp-${randomUUID().slice(0,8)}` (a non-UUID) and created no GoTrue row. Claude caches the DCR client_id by server URL and does not re-register, so the bad value has persisted since March. It lives only in her client cache; there is no server object to migrate, admin UPDATE is broken (500), and a passthrough rewrite is dead code because current discovery points authorize straight at GoTrue and the cached-discovery path is also blocked by the retired token stub.
**Fix (no code, no deploy, no risk):** she removes the connector and re-adds it at `https://nucleoia.vitormr.dev/mcp/semantic` (a server-URL key her March client never registered against), forcing a fresh DCR that mints a valid UUID. Fallbacks if it persists: try the other Claude surface (web vs desktop have separate caches), full Claude sign-out/in, or `/mcp` / `/mcp/actions` as a different key. Exact PT-BR instruction in section 4.

### P1 - correctness traps that will keep biting new client classes

**FM-01 - DCR silently falls back to the shared client and echoes unregistered redirect_uris.**
`register.ts` gates true DCR on the *sanitized* redirect list. If sanitize empties it (a non-https callback, no `redirect_uris` field, or the real callback sitting 6th+ past the cap of 5), it returns shared `8636c0d0` with HTTP 201 and echoes the caller's *requested* URIs as if registered. The client believes it registered a callback that GoTrue then hard-fails at authorize with `invalid redirect_uri`. This is the structural shape behind the Perplexity/xAI/Cursor class. Verifier gap note: the fix below does not cover the 6th+-URI sub-case (sanitize keeps the first 5, non-empty, so it still registers the wrong set silently).
**Fix:** in the fallback branch do not echo `body.redirect_uris` (return `[]`); when a non-empty request sanitizes to nothing, return RFC 7591 `invalid_redirect_uri` 400 instead of a misleading 201. Gate the 400 strictly on "sanitize dropped everything", never on "no service role", so local dev and transient admin 5xx do not regress. Owner decision: raise the redirect cap above 5, or warn on partial registration.

**PPX-3 / FM-03 / FM-04 - resource-metadata mismatch.**
`oauth-protected-resource.ts` hardcodes `resource: origin/mcp` for every caller, and the RFC 9728 path-suffixed URL 404s, so `/mcp/semantic` and `/mcp/actions` both advertise `/mcp`. Confirmed non-breaking today (the EF does no audience check; a plain Supabase JWT is accepted identically on all three surfaces), but it is the one server-side pretext a spec-strict client (Perplexity, possibly OpenAI Apps SDK) could use to reject after a good token exchange.
**Fix:** make the protected-resource route path-aware and add a `/.well-known/oauth-protected-resource/[...path]` catch-all so each surface advertises its own `resource`. Do not add EF-side audience enforcement (GoTrue tokens are not RFC 8707 resource-bound; enforcing would break the working flow).

### P2 - hygiene and hardening (no user impact today)

**PPX-1 / PPX-5 (Perplexity) - "Failed to verify" is Perplexity-side.**
The string appears nowhere in `src/` or `supabase/`. Our chain completes: authorize 302 to consent (with or without the `resource` param), token 200, EF accepts the JWT. Classify as client-side, most likely a mobile in-app-browser state/PKCE-verifier split (the exact "post-200 then failed to verify" signature). **Test to run:** connect from Perplexity on desktop web first. If desktop works and only mobile fails, it is confirmed client-side (report upstream, no server fix). If both fail, ship PPX-3 and retest.

**Inventory cleanup (grounded in live usage, section 5).** One safe deletion: orphan Claude client `6bef8765` (0 sessions, 0 consents, 0 authz). Everything else carries a real member consent and must not be deleted.

**FM-05 / FM-06 - retired token stub and always-200 consent page.** Both are by design (#1210, #1432). No change unless telemetry shows clients looping on the stub, or a synthetic monitor needs the consent page to signal a bad id via a 4xx instead of the client-side watchdog.

---

## 4. Leticia - ready-to-send instruction (PT-BR)

> Oi Leticia! O conector antigo do Claude ficou preso com um identificador em formato antigo que o nosso login recusa. O jeito de resolver e recriar o conector do zero:
> 1. No Claude, abra Configuracoes > Conectores, ache o conector do Nucleo e clique em Remover/Desconectar.
> 2. Adicione de novo como conector novo, colando exatamente esta URL: `https://nucleoia.vitormr.dev/mcp/semantic`
> 3. Faca o login e autorize quando o Claude abrir a tela de consentimento.
> Se ainda falhar: tente no outro Claude (se usou o app, tente o site, ou vice-versa), ou saia e entre de novo na sua conta Claude antes de readicionar.

---

## 5. OAuth client inventory (live usage, 2026-07-20)

6 live (non-deleted) clients. Usage from `auth.sessions`, `auth.oauth_consents`, `auth.oauth_authorizations`. `last_authz` values dated today are audit-probe noise.

| client_id | name | active consents (who) | disposition |
|---|---|---|---|
| `8636c0d0` | Nucleo IA MCP (legacy shared) | 3 - Vitor, Fabricio Costa, Fernando Maquiaveli (connected 08-09/Jul, pre-DCR) | KEEP. Deleting breaks 3 members. |
| `033828f2` | Claude | 1 - Eduardo Luz (real member, working) | KEEP. |
| `f3d4bacc` | Claude | 1 - Vitor | KEEP. |
| `6bef8765` | Claude | 0 (orphan, first of the 14:52 double-registration) | SAFE TO DELETE (only unambiguous cleanup). |
| `0d4fb692` | Perplexity | 1 - Vitor | KEEP for now (owner's own; part of the failing Perplexity test). |
| `a4980f86` | Perplexity | 1 - Vitor | KEEP for now (owner's own; duplicate of 0d4fb692, both Vitor). |

**Policy:** cleanup is gated on live usage, not tidiness. Delete only clients with 0 sessions AND 0 consents AND 0 authz. Deleting a client with a consent forces that member to reconnect. Admin UPDATE is broken (500), so the architecture stays one-client-per-registration; never plan a fix that mutates an existing client.

---

## 6. Systemic hardening + anti-regression tests

**Code hardening (proposals, not yet applied):**
1. `register.ts`: assert `created.client_id` matches a UUID before returning it (defense against the exact Leticia class ever recurring from a shim). Fallback branch: stop echoing requested redirect_uris; 400 on sanitize-emptied non-empty requests (FM-01).
2. `register.ts` (optional): idempotency dedup by `(client_name, redirect_uris)` to stop the x2/x3 orphan pileup. Cosmetic; owner's call.
3. `oauth-protected-resource.ts`: path-aware `resource` + path-suffixed catch-all route (PPX-3/FM-03/FM-04).
4. `authorize.ts` (optional, marginal reach): detect a non-UUID client_id and 302 to a friendly "re-add your connector" page. Only fires for cached-discovery clients, so low value.
5. Observability: the `mcp/*.ts` proxies have `kvLog` neutered (free-tier write limit). Consider a low-volume `oauth_flow_events` table capturing register outcomes and authorize-failure codes, so the next incident has server-side telemetry instead of guesswork.

**Contract tests to add (anti-regression):**
- `register` must return a UUID `client_id` for a valid https redirect_uri.
- `register` fallback must not echo an unregistered redirect_uri as if registered.
- protected-resource `resource` must equal the connector URL per surface (`/mcp`, `/mcp/semantic`, `/mcp/actions`).
- token stub contract: `/oauth/token` returns `invalid_grant` (retired) and discovery points `token_endpoint` at GoTrue.
- authorize fingerprints: non-UUID -> "invalid client_id format" as the stable signal that the register path never emits a non-UUID again.

Existing OAuth tests to extend: `tests/contracts/1210-mcp-native-oauth.test.mjs`, `tests/contracts/oauth-redirect-uri-allowlist.test.mjs`.

---

## 7. Prioritized action plan

| Prio | Action | Type | Risk | Needs owner |
|---|---|---|---|---|
| P0 | Send Leticia the reconnect instruction (section 4) | Comms | none | send it |
| P1 | FM-01: fix register fallback echo + 400-on-empty-sanitize | Code + deploy | low | approve |
| P1 | PPX-3: path-aware protected-resource metadata + catch-all | Code + deploy | low | approve |
| P1 | Add the 5 contract tests | Code | none | approve |
| P2 | Run the Perplexity desktop-vs-mobile isolation test | Test | none | run it |
| P2 | Delete orphan client `6bef8765` (0/0/0) | Prod delete | low (orphan) | confirm |
| P2 | register.ts UUID assertion + optional dedup | Code | low | approve |
| P2 | OAuth flow observability table | Code | low | approve |

**Explicitly not recommended:** un-retiring `/oauth/token` (regresses the #1210 two-refresher failure), EF-side audience enforcement (breaks the working flow, GoTrue tokens are not resource-bound), any fix that mutates an existing OAuth client (admin UPDATE is broken).

---

## Appendix - audit integrity

- All figures from live tool results this session: GoTrue admin API, `execute_sql` on `auth.*`, curl against production discovery/authorize/token, git history.
- Security flags on `map:flow` and `map:inventory+hardening`: reviewed and cleared. `auth.oauth_clients.deleted_at` shows all deletions hit `__audit_*` / `probe` throwaways; the 6 real clients are present. The `map:inventory+hardening` agent additionally returned a degenerate schema fill ("test"), so the inventory/hardening analysis in sections 5-6 was re-done directly by the main loop against live SQL, not taken from that agent.
- No secret values printed. Service role key read from `.env` into shell variables only.
