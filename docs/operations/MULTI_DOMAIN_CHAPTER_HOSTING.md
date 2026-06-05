# Multi-domain (per-chapter) hosting — topology, decision & code-readiness plan

> Status: **PLAN** (2026-06-04). Infra side (Cloudflare/Supabase) = PM/dashboard. Code side = dedicated session.
> Goal: serve the SAME single app under multiple chapter domains **transparently** (URL stays on the
> chapter's domain, e.g. `nucleoia.pmigo.org.br`), with `nucleoia.vitormr.dev` as sede/canonical.

## 1. Authoritative topology (confirmed via dashboard + live curls, 2026-06-04)

| Thing | Reality |
|---|---|
| **Production app** | Cloudflare **Worker `platform`** — `nucleoia.vitormr.dev` is its **Custom Domain** (Worker → Domains & Routes). Has bindings BROWSER (cert-PDF), SESSION (KV), IMAGES, ASSETS + secrets. **This is prod — do NOT delete.** |
| **Pages project `ai-pm-research-hub`** | A **stub/redirector** — `pages.dev` 301→`workers.dev`. Only custom domain = `nucleoia.pmigo.org.br`. NOT running the app. **This is the deletable one** (after moving pmigo off it). |
| `nucleoia.pmigo.org.br` (today) | 301 → `platform.…workers.dev` → (app middleware) → `nucleoia.vitormr.dev`. So it currently **redirects away** (not transparent yet). |
| `pmi-vep-sync` Worker | Separate Worker (VEP sync). **Never delete.** |
| Middleware (`src/middleware.ts`) | Only 301s 3 LEGACY_HOSTS → canonical; **all other hosts pass through transparently**. Per-host CSRF (origin===requestHost) already multi-domain-safe. |

## 2. Consolidation recommendation (infra — PM side)

The premise "delete the Worker, keep Pages" is **inverted**. Cloudflare's official 2026 guidance: **use Workers, Pages is legacy/maintenance** (there is an official "Migrate from Pages to Workers" guide). The app correctly runs on the Worker. So: keep the Worker; the Pages project is the deletable stub.

**⚠️ Correction (verified vs official docs 2026):** you CANNOT add `nucleoia.pmigo.org.br` as a plain **Worker Custom Domain** — Worker Custom Domains require the **zone to be on your Cloudflare account** ("cannot create a Custom Domain ... on a zone you do not own / on a hostname with an existing CNAME"). `pmigo.org.br` lives on cPanel/PMI-GO, not your CF account. (Pages accepts external domains via CNAME — that's why pmigo attached there — but Pages is legacy + would be a binding-less parallel deploy.)

**Correct mechanism for external chapter domains on the Worker = Cloudflare for SaaS (Custom Hostnames).** Free for the first 100 hostnames (Free/Pro/Biz), then $0.10/mo each → effectively free at chapter scale. Steps (on the `vitormr.dev` zone as the SaaS zone):
1. SSL/TLS → Custom Hostnames → **Enable Cloudflare for SaaS**.
2. **Fallback origin** = an originless proxied DNS record, e.g. `ssl.vitormr.dev AAAA 100::` (proxied).
3. **Workers Routes** on vitormr.dev: `*/*` → Worker `platform` (catches all custom-hostname traffic). ⚠️ `*/*` captures the whole vitormr.dev zone — add bypass routes (route → no Worker) for any other personal subdomains on that zone.
4. Add custom hostname `nucleoia.pmigo.org.br` (+ each future chapter).
5. Chapter (cPanel/DNS): create **CNAME** `nucleoia` → the CF target (e.g. `ssl.vitormr.dev`) **+ the TXT DCV** record CF asks for.
6. CF auto-provisions TLS → pmigo serves the Worker transparently (URL stays).
7. **Remove pmigo from the Pages project + any redirect rule**, then the Pages stub is deletable. NEVER delete the Worker.

**Alternative (Path 2):** a chapter moves its full zone (nameservers) to Cloudflare → then a plain Worker Custom Domain works (no SaaS). High political friction per partner; SaaS-via-CNAME is easier for them. Do NOT go "only Pages" (legacy + binding parity migration).

Docs: Workers Custom Domains; Cloudflare for SaaS getting-started + "Worker as origin" + plans/pricing; Migrate-from-Pages-to-Workers.

## 3. Supabase Auth

- **Redirect URLs allowlist** = the #1 hard **login blocker** (1 project = 1 allowlist). Already set for vitormr + pmigo ✅. For each future chapter add `https://nucleoia.<chapter>/**`. (Explicit `/oauth/consent`+`/oauth/callback` are redundant under `/**` but harmless.)
- **Google social login domain display:** by default the OAuth round-trips through `ldrfrvwhxsmgaabwmaik.supabase.co/auth/v1/callback` → the **Supabase project ref shows** in the URL bar + Google "continue to" line (not the chapter). Login still WORKS.
  - Cheap fix: set the **Google OAuth consent screen** app name + logo ("Núcleo IA / PMI-GO").
  - Full fix: **Supabase Custom Auth Domain** add-on (~US$10/mo) → auth on e.g. `auth.nucleoia.vitormr.dev`; ref disappears. **1 project = 1 custom auth domain** → all chapters share ONE auth host (pick sede/neutral); per-chapter branded auth needs separate projects (not warranted).
  - Magic-link (email) has **no** domain-display issue (the link points to the app domain — fixed by the host-relative code work below).

## 4. Code-readiness audit (7-agent workflow `wf_90d7abbe`, 2026-06-04)

**Cross-cutting (build FIRST):** there is **NO per-tenant base-URL infra today** (no `base_url`/`custom_domain` column, no `resolveTenantBaseUrl`). Two distinct origin sources — do NOT conflate:
- **Browser-invoked surfaces** (video-upload CORS, cert download, governance PDF islands, print footers, og:url) → use the **request origin** (`req.headers.get('Origin')` validated vs allowlist, or client `window.location.origin`).
- **Server/cron surfaces with no browser origin** (transactional email EFs, cert-pdf-render autogen) → resolve base URL from the **recipient's tenant** (recipient→chapter/org→base_url). A cron has no Origin header.

**MUST-FIX before any chapter cutover (breaks login/feature):**
- ✅ (config, done for pmigo) Supabase Redirect-URL allowlist.
- `pmi-video-init-upload` + `pmi-video-finalize-upload` — `ALLOWED_ORIGIN` hardcoded → applicant **video upload CORS-blocked** on a chapter domain. Echo validated request Origin vs allowlist (not `*`).
- `send-email-verification:119` — verify link hardcoded to sede → secondary-email verify can break cross-origin.

**Brand-leak (works, but routes chapter users to vitormr) — depends on the base-URL infra:**
- Email EFs: `send-notification-email` (17 hits incl. weekly digests), `send-campaign` (incl. `{unsubscribe_url}` + List-Unsubscribe header), `send-global-onboarding`, `send-allocation-notify`, `send-email-verification:54`.
- Certs/governance: `src/lib/certificates/pdf.ts` (logo host **and** chapter-slug pmigo-pinned; verify stamp), `ChainPDFDocument.tsx`, `ChainAuditReportPDF.tsx`, `cert-pdf-render/[id].ts` (autogen — uses stored per-org base_url, no browser origin), `MeetingsPage.tsx`, `admin/cycle-report.astro` + 3-dict i18n `cycleReport.*`.

**SEO:**
- BaseLayout has **no `<link rel=canonical>`** → add ONE cross-host canonical that host-swaps the path onto sede (dedups all chapter hosts → vitormr; matches "vitormr canonical"). `og:url` at BaseLayout:47 is already host-relative.
- Delete/relativize 5 duplicate per-page `og:url` overrides (about, blog/index, blog/[slug] incl og:image fallback, meetings, webinars).
- Keep `astro.config` `site`, about JSON-LD `url`, and both RSS feed `site` **pinned to canonical** on purpose (one authoritative sitemap/feed).

**Canonical-by-design — do NOT host-relativize (would break MCP login):**
- `.well-known/oauth-*`, `mcp.ts`, `mcp/semantic.ts` BASE = vitormr — issuer/resource_metadata MUST equal the value registered with the Supabase OAuth client + the `mcp_refresh:{sub}` KV key is origin-anchored. Add a code comment to prevent a future "make it host-relative" refactor. OAuth flow routes (authorize/exchange/consent) already use request-relative origins (safe).
- `sync-artia` host refs = internal Artia prose (not member links). `nucleo-mcp:401` prompt prose = cosmetic.

**Middleware:** already correct (transparent pass-through). Optional hardening: a `CHAPTER_HOSTS`/host→org allowlist (reusing the base-URL lookup) so an unprovisioned/typo'd/attacker CNAME falls through deliberately instead of silently serving sede. **Do NOT redirect chapter hosts.**

## 5. PR slices (dedicated code session)

- **PR-0** (config, gates cutover): chapter origins in Supabase Redirect-URL allowlist (+ optional 1 neutral Custom Auth Domain). *(pmigo: done.)*
- **PR-1** (infra enabler): per-org `base_url`/`custom_domain` column + migration + host→org / recipient→base_url resolver + shared `resolveTenantBaseUrl` in `_shared/` + browser origin helper. No user-visible change.
- **PR-2** (must-fix, independent): video-upload EFs CORS request-Origin echo vs allowlist; deploy both EFs.
- **PR-3** (must-fix): `send-email-verification` link from caller-supplied origin / recipient tenant.
- **PR-4** (email brand-leaks, dep PR-1): thread `resolveTenantBaseUrl` through the 4 email EFs (per-recipient).
- **PR-5** (cert/governance brand-leaks, browser paths): `certificates/pdf.ts`, ChainPDF*, MeetingsPage, cycle-report + 3-dict i18n.
- **PR-6** (cert autogen, dep PR-1): `cert-pdf-render/[id].ts` per-org base_url + chapter slug.
- **PR-7** (SEO): BaseLayout cross-host canonical; delete/relativize 5 og:url overrides; deliberate feed `site`.
- **PR-8** (optional hardening): middleware `CHAPTER_HOSTS` allowlist + unknown-host fallback; canonical-only comments on MCP/OAuth discovery BASE.

> Full per-finding detail: workflow run `wf_90d7abbe-f2e` (transcript in session subagents dir).
