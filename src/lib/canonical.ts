// src/lib/canonical.ts
// ─────────────────────────────────────────────────────────────────────────────
// SINGLE SOURCE OF TRUTH for the platform's canonical public host.
//
// The canonical domain flip (Rider — Ciclo 4) lives HERE and nowhere else.
// To flip the public domain to `nucleoia.pmigo.org.br`, change CANONICAL_HOST
// below — it is the only host literal in `src/`. A contract test
// (`tests/contracts/canonical-host-centralization.test.mjs`) fails the build if
// any other file under `src/` hardcodes the host, so this constant cannot
// silently drift.
//
// WHY a constant (not an env var): the OAuth issuer/resource identifiers
// (`.well-known/oauth-*`) and the MCP base must be stable and reviewable — an
// env misconfiguration would break the OAuth flow silently. The flip is a
// deliberate, gated one-time PR, not a runtime toggle.
//
// FLIP CHECKLIST (do these BEFORE/with changing the value here — they are NOT
// in `src/` and the contract test cannot guard them):
//   1. Supabase Auth → URL Configuration: add the new origin to the redirect
//      allowlist (and Site URL if appropriate).
//   2. `src/lib/oauth-security.ts` TRUSTED_ROOT_HOSTS: add the new root host
//      (`pmigo.org.br`) — MCP client redirect_uri allowlist (suffix model).
//   3. Cloudflare: confirm the pmigo subdomain (Pages custom domain) does NOT
//      have Bot Fight Mode blocking datacenter IPs (the reason we left
//      `.workers.dev`); confirm CNAME → `ai-pm-research-hub.pages.dev`.
//   4. Re-register / re-point MCP clients (OAuth identifiers change).
//   5. Google Search Console: add the new property; keep the old one.
//   6. Keep `vitormr.dev` co-hosted FOREVER: already-issued certificate PDFs
//      crave the verification URL at issuance, and live MCP clients reference it.
//   7. Edge Functions (Deno, separate runtime — do NOT import this module) and
//      historical migration bodies still emit vitormr.dev; that is fine while
//      co-hosted. Re-point EF email templates as a follow-up, not a blocker.
//   8. Dev tooling outside `src/` (not covered by the ratchet test): update
//      `scripts/smoke-test.mjs` (default base) and `scripts/audit-mcp-tool-matrix.mjs`
//      (RUNTIME_URL) so post-flip smoke/audit runs hit the new host.
// ─────────────────────────────────────────────────────────────────────────────

/** Canonical public host (no scheme). The ONE place to change for a domain flip. */
export const CANONICAL_HOST = "nucleoia.vitormr.dev";

/** Canonical origin, e.g. `https://nucleoia.vitormr.dev`. Use for absolute URLs. */
export const CANONICAL_ORIGIN = `https://${CANONICAL_HOST}`;

// ─────────────────────────────────────────────────────────────────────────────
// CERTIFICATE VERIFICATION HOST — the institutional (chapter) domain PRINTED on
// certificates, decoupled from CANONICAL_HOST on purpose.
//
// WHY separate: a recognition certificate is a chapter-institutional artifact; it
// should carry the PMI Goiás domain (`nucleoia.pmigo.org.br`), not the platform's
// operational canonical host (which also identifies the OAuth issuer / MCP base and
// is only flipped via the gated checklist above). `nucleoia.pmigo.org.br` already
// resolves and 30x-redirects to CANONICAL_HOST/verify, so a printed link lands on
// the same verify page. Declared HERE (not hardcoded in pdf.ts) so the
// canonical-host-centralization contract test stays green — this is the sanctioned
// place for public-host literals.
// ─────────────────────────────────────────────────────────────────────────────

/** Host printed on certificate PDFs for the verification link (chapter-institutional). */
export const CERT_VERIFY_HOST = "nucleoia.pmigo.org.br";

// ─────────────────────────────────────────────────────────────────────────────
// WHY `nucleoia.pmigo.org.br` STILL 301s, AND WHY THAT IS NOT A BUG
// (measured 2026-09-19; nothing below is inferred from code alone)
//
// The app moved from Cloudflare Pages to the Worker `platform`. The Worker is
// the only production owner today, and Pages was left serving PR previews only:
// the project has `production_deployments_enabled: false`, so every push to
// `main` creates a deployment that is born `is_skipped: true` and never builds.
// That is DELIBERATE — turning it back on resurrects two services answering for
// the same app, which is the thing the migration removed.
//
// `nucleoia.pmigo.org.br` did NOT come along. It is a CNAME at HostGator
// pointing to `ai-pm-research-hub.pages.dev`, and it is a custom domain on the
// Pages project. So it is served by the frozen Pages production build, whose
// LEGACY_HOSTS still listed it — hence the 301 to CANONICAL_HOST. Following the
// redirect it reaches the app in one hop, which is why nobody noticed.
//
// It could not come along: Workers Custom Domains require "an active Cloudflare
// zone" and refuse "a zone you do not own" (Cloudflare docs). The zone
// `pmigo.org.br` lives on HostGator nameservers (ns854/855) and is NOT in this
// Cloudflare account — the Worker's own domain record points at a zone id this
// account reads as "Invalid zone identifier".
//
// CONSEQUENCES, so nobody re-derives this:
//   · Do NOT "fix" it by enabling Pages production deployments. That undoes the
//     migration's single-owner property.
//   · Do NOT remove the Pages custom domain either: the HostGator CNAME would
//     then point at a project that does not claim the host, and Cloudflare's own
//     docs say that produces a 522.
//   · Serving the chapter domain WITHOUT a redirect requires the zone in a
//     Cloudflare account the Worker can reach — i.e. moving `pmigo.org.br`
//     nameservers. That is a chapter-side decision with a DNS window, and it
//     also moves the chapter WordPress DNS (root A record, HostGator IP), which
//     is otherwise untouched by anything here.
//   · Two co-equal entrances are possible for SERVING; what cannot be duplicated
//     is the OAuth issuer / MCP base identity, which is what CANONICAL_HOST is.
//     Co-hosting 200 on both while the canonical stays here breaks no registered
//     MCP client; flipping the canonical does (see the checklist above).
// ─────────────────────────────────────────────────────────────────────────────
