# MCP Org/Team Connector Enablement — Núcleo IA

> **Tracker for GitHub issue [#234](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/234)** ·
> **Decision: Option B — publish as an org/team connector** (PM, 2026-06-06; recorded in the #234 comment and in
> `docs/council/decisions/2026-06-07-234-org-connector-enablement.md`). Option C (public Claude Connectors
> Directory) was **not** chosen.
>
> This is the **enablement package**: everything the platform side can deliver is done; the remaining steps are
> **PM/admin actions inside the Claude.ai organization UI** plus one **member OAuth smoke**. Keep #234 open until
> both are complete + verified.

## ⚠️ STATUS UPDATE (2026-06-07) — Option B requires Team/Enterprise; adopted **member self-add**

Live finding (verified in the PM's Claude.ai via Claude for Chrome): the account is an **individual plan (Pro/Max)**.
`https://claude.ai/admin-settings/connectors` **redirects to personal settings** — there is **no organization admin
connectors area**. Per the Claude Help Center, org-level connectors are a **Team/Enterprise** feature enabled by an
**Owner/Primary Owner**; on Free/Pro/Max only the **personal** connector (*Customize → Connectors*) exists.

**Revised effective decision (PL/CTO + PM, aligned):** the true "Option B" (centralized admin connector) is **not
viable without a Team/Enterprise upgrade**, and an upgrade is **not worth it just for this**. **Adopted path = member
self-add of the personal custom connector** (§3b) — same server URL, OAuth per member, RLS scopes each user to their
own data, so the outcome is ~equivalent to an org connector at zero plan cost. The PM's own personal connector
**already works** (308 tools loaded) → Workstream A is proven end-to-end. The org-admin content in §1/§3 below remains
valid as the **Team/Enterprise playbook** if the org ever upgrades.

## TL;DR

| | |
|---|---|
| **Current path (individual plan)** | Distribute the **member self-add** instruction (§3b): each member adds `https://nucleoia.vitormr.dev/mcp` in *Customize → Connectors*. RLS scopes each user. |
| **Team/Enterprise playbook** (if upgraded) | PM adds the server in **Organization settings → Connectors** (§1/§3); members enable individually. |
| **What's done (platform side)** | OAuth 2.1 DCR + PKCE, native Supabase OAuth server with per-client refresh chains (#1210 — the earlier KV/server-side auto-refresh model was retired), `offline_access`+`refresh_token` advertised live, docs corrected, decision recorded. **Personal connector verified working live.** |
| **Risk** | Low. No code change. The connector already works as a per-user custom connector today. |

---

## 1. Connector metadata (values to register)

Use these exact values when adding the connector in the Claude.ai organization settings.

| Field | Value |
|-------|-------|
| **Name** | `Núcleo IA` |
| **Short description** | Query and manage the AI & PM Research Hub (initiatives, tribes, boards, events, governance, gamification) from your AI assistant in natural language. |
| **Long description** | Núcleo IA is the MCP server of PMI's Brazilian *AI & Project Management Research Hub*. It exposes the full implementation-tool catalog across personal, tribe, board, events, governance, communications, selection, gamification and knowledge domains, with role-based authority (`can()` / RLS) and full audit logging. OAuth 2.1 + PKCE secures every call; Row Level Security enforces per-member data scope (no PII in tool responses). |
| **Server URL (`/mcp`)** | `https://nucleoia.vitormr.dev/mcp` — full catalog (recommended default for Claude.ai) |
| **Semantic URL (`/mcp/semantic`)** | `https://nucleoia.vitormr.dev/mcp/semantic` — bridge-first gateway for strict clients (Claude.ai does not need this) |
| **Canonical docs URL** | `https://nucleoia.vitormr.dev/docs/mcp` (live tool catalog) · setup guide: [`docs/MCP_SETUP_GUIDE.md`](MCP_SETUP_GUIDE.md) |
| **Privacy page** | `https://nucleoia.vitormr.dev/privacy` |
| **Icon** | `https://nucleoia.vitormr.dev/favicon.svg` — ⚠️ see note in §6 (a square PNG may be required by the UI) |
| **Tool count** | Full catalog — **do not pin a number**; the live per-surface count is at `https://nucleoia.vitormr.dev/mcp` → `tools/list`, or the structured `/health` report (see §2). |

### OAuth 2.1 endpoints (already implemented, no setup needed)

| Purpose | Path |
|---------|------|
| Authorization-server discovery | `/.well-known/oauth-authorization-server` |
| Protected-resource discovery | `/.well-known/oauth-protected-resource` |
| Dynamic Client Registration (DCR) | `/oauth/register` |
| Authorize | `/oauth/authorize` → `/oauth/consent` |
| Token (PKCE verify, refresh) | `/oauth/token` |

- **Grant types advertised:** `authorization_code`, `refresh_token`
- **Scopes advertised:** `mcp:tools`, `offline_access`
- **PKCE:** `S256`

### Allowed link origins

Trust is **subdomain-aware** (`host === root` OR `host` ends with `.root`). Roots, from
`src/lib/oauth-security.ts`:

`claude.ai` · `chatgpt.com` · `openai.com` · `perplexity.ai` · `cursor.com` · `manus.im` · `vitormr.dev`
(each root also covers all its `*.root` subdomains, e.g. `app.claude.ai` — but **not** a different apex like
`claude.com`) — plus custom schemes `cursor://`, `vscode://`, `vscode-insiders://`, `code-oss://`, and
`localhost`/`127.0.0.1` for local dev.

> If Claude.ai's org-connector OAuth callback ever uses a host **not** under one of these roots (watch for a
> `claude.com` apex or a new redirect host), add it to `TRUSTED_ROOT_HOSTS` in `src/lib/oauth-security.ts` and
> redeploy the Worker — otherwise the authorize step will reject the redirect_uri.

---

## 2. Workstream A — stabilization (DONE, live evidence)

All measured live on **2026-06-07** (re-measure before relying on any number — see project grounding rules).

**OAuth metadata advertises refresh capability** (the #234 hotfix `7192b01e`, now in `main`):

```
GET https://nucleoia.vitormr.dev/.well-known/oauth-authorization-server
  grant_types_supported : [ "authorization_code", "refresh_token" ]
  scopes_supported      : [ "mcp:tools", "offline_access" ]

GET https://nucleoia.vitormr.dev/.well-known/oauth-protected-resource
  scopes_supported      : [ "mcp:tools", "offline_access" ]
```

> **⚠️ SUPERSEDED by #1210 (native Supabase OAuth server).** The server-side / proxy auto-refresh model
> described below was **retired**: the AI client now refreshes directly against GoTrue's
> `/auth/v1/oauth/token` on its own client-scoped chain, and the Worker proxies MUST NOT refresh (a second
> refresher was the #1053 re-login bug). `src/pages/oauth/token.ts` is now a retired stub and the KV
> refresh entries are dead (left to expire by TTL). See `.claude/rules/mcp.md` (§ OAuth Flow / Token refresh).
> The historical description is kept below for context only.

**Server-side auto-refresh (HISTORICAL, retired by #1210):**

- `src/pages/mcp.ts` and `src/pages/mcp/semantic.ts` decoded the JWT `exp`, and within a 5-minute window looked up
  `mcp_refresh:{sub}` from KV and renewed against Supabase Auth — transparent to the MCP host.
- `src/pages/oauth/token.ts` stored the `refresh_token` in KV with a **30-day TTL** on both the
  `authorization_code` and `refresh_token` grants.
- Net effect on the **happy path** (pre-#1210): a Claude.ai connector stayed alive well beyond 7 days without manual relogin.

> **Known robustness gap (low severity, tracked separately):** the proxy's KV re-store at `mcp.ts:62` /
> `semantic.ts:60` is gated on `if (data.refresh_token)` and lacks the `|| oldRefreshToken` fallback that
> `oauth/token.ts:81` already has. In the (rare, non-standard) case Supabase returns an access token with **no**
> refresh token, a stale rotated token can linger and the next refresh would fail → re-auth. Supabase echoes a new
> refresh token on every successful rotation, so this is defensive-only and does not affect the realistic path.
> Hardening is tracked in **[#580](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/580)** (see §7) and
> should ship as its own Worker-deploy PR, not bundled with docs.

**Tool surfaces (live):** `/mcp` full catalog · `/mcp/semantic` 4 tools (v0.2.0) — exact counts via
`https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/health`.

---

## 3. Team/Enterprise playbook — add as an org connector (Claude.ai admin UI)

> **⚠️ Requires a Team or Enterprise plan.** On individual plans (Free/Pro/Max) this area does **not** exist —
> `https://claude.ai/admin-settings/connectors` redirects to personal settings (verified 2026-06-07). If you are on
> an individual plan, **skip to §3b (member self-add)**. The steps below apply only once the org is on Team/Enterprise.
>
> These run in the **Claude.ai organization settings** (Owner / Primary Owner), at
> `https://claude.ai/admin-settings/connectors`, and cannot be done from the codebase. ~10 minutes.

1. **Claude.ai → Organization settings → Connectors** (`https://claude.ai/admin-settings/connectors`) → **Add**.
2. Paste the **Server URL**: `https://nucleoia.vitormr.dev/mcp`.
3. Fill **Name** / **description** / **icon** / **docs URL** from §1. **Leave "Advanced settings" (OAuth Client
   ID / Secret) blank** — the server self-registers via DCR; no client_id/secret to paste.
4. Save. Claude.ai performs OAuth discovery against `/.well-known/oauth-*` and registers via `/oauth/register`.
5. **Authorize once** as the admin: the browser opens `/oauth/authorize` → log in with a Núcleo account → approve
   consent. This is the "one fresh reconnect" that captures the updated `offline_access` metadata.
6. Confirm the connector shows **Connected** and tools load (ask Claude e.g. *"what are my upcoming Núcleo events?"*).
7. Members then **individually connect/enable** the connector (their own OAuth) per Claude.ai's connector-sharing
   controls — so each member only reaches data their own role permits.

> **Infra note — Claude connects from Anthropic's cloud, not your device.** Across every client (claude.ai,
> Desktop, Cowork, mobile), Claude reaches the MCP server from Anthropic's IP ranges over the public internet.
> Ours **already works** for per-user claude.ai today (same Cloudflare path), so no change is expected. If a future
> block appears, the WAF skip rule lives in `docs/infra/CLOUDFLARE_MCP_RULES.md` (allowlist Anthropic's IP ranges).

---

## 3b. Member self-add — the ADOPTED path (individual plans)

Since the org is on an individual plan, there is no centralized admin connector. The equivalent outcome is reached by
having **each member add the personal custom connector** once. Same security model as an org connector — the OAuth
login is per member and RLS scopes each user to their own data; the org-admin step just centralizes the "add", which
we don't have.

**Works for every member**, including Free-plan accounts (Free is limited to **one** custom connector, which this can
be). Distribute this short instruction (e.g. in a chapter announcement or the wiki):

> **Conecte o Claude ao Núcleo IA (1x):** No Claude.ai → **Customize → Connectors** → **Add custom connector** →
> cole `https://nucleoia.vitormr.dev/mcp` → **Save**. Uma janela abre → faça login com a sua conta do Núcleo e
> aprove o acesso. Pronto: pergunte ao Claude, ex. *"quais são meus próximos eventos do Núcleo?"*. Você só vê os
> seus próprios dados. (Não preencha "Advanced settings"/OAuth — deixe em branco.)

EN: *Claude.ai → Customize → Connectors → Add custom connector → paste `https://nucleoia.vitormr.dev/mcp` → Save →
log in with your Núcleo account + approve. Leave Advanced/OAuth blank.*

No "smoke" beyond this is needed — the PM's own personal connector already proves the flow (308 tools, OAuth + refresh
working). §4 below stays as the formal checklist if you want one member to confirm RLS scoping explicitly.

---

## 4. Member OAuth smoke checklist (one non-admin member)

Have a regular member (not the org admin) run this end-to-end to prove the org grant works for non-admins:

- [ ] Member sees the **Núcleo IA** connector available in their Claude.ai (via org sharing).
- [ ] Member clicks connect → OAuth window opens → logs in with **their own** Núcleo account → approves consent.
- [ ] Connector shows **Connected**.
- [ ] Member runs a **read** tool scoped to self — e.g. *"show my Núcleo profile"* (`get_my_profile`) or
      *"my upcoming events"* (`get_upcoming_events`) — and gets **their** data (RLS scoping correct, no PII leak).
- [ ] A tool the member is **not** authorized for (e.g. an admin dashboard) is correctly **denied** (fail-closed).
- [ ] **Continuity:** member leaves the connector untouched and confirms it is **still connected after ≥24h**
      (ideally 7 days) with **no relogin prompt**. (This is acceptance criterion #1 — observed over calendar time.)

If any step fails, capture the error and check `mcp_usage_log` + the Worker logs; the
[Troubleshooting table in the setup guide](MCP_SETUP_GUIDE.md#troubleshooting) covers the common cases.

---

## 5. Acceptance criteria status (#234)

| # | Criterion | Status | Evidence / residual |
|---|-----------|--------|---------------------|
| 1 | Connector usable 7 days w/o manual relogin after one fresh reconnect | **Observational** | Enabling infra live + verified; the PM's **personal connector is connected and working (308 tools)**. Confirmed fully by observing 7 calendar days with no relogin. |
| 2 | Prod OAuth metadata includes `offline_access` + `refresh_token` | **MET** | Both well-known endpoints, live (see §2). |
| 3 | Docs stop telling users Claude.ai requires hourly relogin | **MET** | In-repo docs teach the correct refresh model (`MCP_SETUP_GUIDE.md` "Security Model" + "Troubleshooting" sections; README MCP section: "auto-refresh keeps sessions alive for up to 30 days"). No "hourly relogin" passage in any in-repo doc. |
| 4 | `/docs/mcp` shows current runtime tool count (issue said "293") | **MET** | Live `/docs/mcp` renders the current manifest (308 `/mcp` + 4 `/semantic` as of 2026-06-07 — query `/health` for today's value); no "293" anywhere. |
| 5 | Decision recorded (private vs org/team vs Directory) | **MET** | Option B recorded → **revised 2026-06-07** to member self-add (§3b) after the individual-plan finding. #234 comment + decision doc addendum. |
| 6 | If pursuing official listing, create submission checklist | **N/A** (conditional) | Option C (Directory) not chosen. Stub kept in §8 in case it's revisited. |

**4 MET · 1 observational (PM 7-day reconnect) · 1 N/A.** No platform/code criterion remains open.

---

## 6. Open items (PM-only)

1. **Distribute the member self-add instruction** (§3b) to the chapters/members (chapter announcement or wiki). *(Org-settings add in §3 only applies if you upgrade to Team/Enterprise — agent-assistable via Claude for Chrome, §9.)*
2. **Run the member OAuth smoke** (§4) and record the result on #234.
3. **Observe 7-day continuity** and confirm criterion #1 on #234, then close the issue.
4. **Icon format:** only `favicon.svg` exists. If the org-connector UI requires a raster icon, export a **square
   PNG** (≥512×512) and host it (e.g. `public/connector-icon.png` → `https://nucleoia.vitormr.dev/connector-icon.png`).
   Optional for org-internal use.

---

## 7. Tracked follow-up — refresh-rotation hardening ([#580](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/580))

Filed from this session's security-engineer review (see §2 gap). Scope for a **separate** Worker-deploy PR:

- `mcp.ts` / `semantic.ts`: mirror `oauth/token.ts:81` — `const newRefresh = data.refresh_token || refreshToken;`
  then always re-store to KV (never leave a rotated-stale token).
- `oauth/token.ts:167-174`: the KV-store `try/catch` swallows base64 decode errors silently — a malformed
  `access_token` means the session never gets server-side refresh despite a successful OAuth. Log it.
- De-duplicate `decodeJwtPayload` + `tryAutoRefresh` (copy-pasted in `mcp.ts` and `semantic.ts`) into one shared
  module (the `#280` follow-up already notes this).
- Document the KV-TTL vs Supabase refresh-token-lifetime relationship (KV 30 d; keep ≤ the project's Supabase
  refresh TTL).

---

## 8. Option C (Directory) — deferred checklist stub

Only if the PM later revisits and chooses public submission to the Claude Connectors Directory:

- [ ] Canonical docs URL (have: `/docs/mcp`)
- [ ] Privacy page (have: `/privacy`) + **Terms of Service** page (missing — would need creating)
- [ ] Support/contact channel linked from the connector
- [ ] OAuth-flow evidence (have: §2) + MCP smoke evidence (have: §4)
- [ ] Square PNG icon (see §6.4)
- [ ] MFA-free review/demo account for Anthropic review
- [ ] Stable connector name/description/allowed-origins (have: §1)

---

## 9. Runbook executável por agente (Claude for Chrome)

The §3 steps are pure in-browser navigation of the Claude.ai admin UI — a good fit for **Claude for Chrome**
(the browser extension that reads/clicks/navigates the active tab; available on all paid plans). **Claude Cowork**
(desktop agent for local files/apps) can also drive the computer, but Chrome is the direct fit for this web flow.

**How to run it:** open **claude.ai logged in as an Owner**, then paste the self-contained prompt below into Claude
for Chrome. Keep **"Ask before acting"** ON and do the **Save click + the OAuth login/consent yourself** (the agent
should pause there). The prompt embeds the data, so the agent does **not** need to read this file.

```text
Você vai me ajudar a registrar um connector MCP customizado no nível da ORGANIZAÇÃO no Claude.ai.
Use "Ask before acting" e PARE para minha aprovação antes de qualquer Save/confirmar.

Dados do connector:
- Server URL: https://nucleoia.vitormr.dev/mcp
- Nome: Núcleo IA
- Descrição: Consulte e gerencie o AI & PM Research Hub (iniciativas, tribos, boards, eventos,
  governança, gamificação) em linguagem natural.
- Auth: OAuth 2.1 com Dynamic Client Registration — NÃO preencha Client ID/Secret em
  Advanced settings (deixe em branco; o servidor se registra sozinho).

Passos:
1. Vá em Organization settings → Connectors (sou Owner).
2. Clique em Add (custom connector / remote MCP server).
3. Cole a Server URL acima. Preencha Nome + Descrição se houver campos. Deixe Advanced/OAuth em branco.
4. Salve. Em seguida o fluxo OAuth abre um redirect para nucleoia.vitormr.dev —
   PARE e me deixe fazer o login + aprovar o consentimento.
5. Depois que eu aprovar, confirme que o connector aparece como "Connected" e que as tools carregam
   (faça um teste do tipo "quais são meus próximos eventos do Núcleo?").
6. Me diga o estado final e qualquer coisa que precise de mim (ex.: pedido pra liberar IPs da Anthropic,
   ou se algum host de redirect for rejeitado).
```

**Caveats:**
- You're using Claude *inside* Anthropic's own settings — usually fine, but the extension may guard sensitive
  account pages. That's why the **final Save + OAuth consent stay with you** (manual), not the agent.
- For the **member smoke** (§4), a member can paste an analogous prompt scoped to "connect + run `get_my_profile`"
  — but the OAuth login must be the member's own.
- If you'd rather have the agent "read the file": open the GitHub blob of this doc (logged into GitHub) and tell it
  to follow §3 — but the self-contained prompt above is more reliable (no repo access needed).

---

*Last verified live: 2026-06-07. Re-ground all numbers before relying on them (project grounding rule).*
