// src/lib/canonical.ts
// ─────────────────────────────────────────────────────────────────────────────
// SINGLE SOURCE OF TRUTH for the platform's canonical public host.
//
// The canonical domain flip (Rider — Ciclo 4) lives HERE and nowhere else.
// To flip the OAuth/MCP identity host, change CANONICAL_HOST below. Every public
// host literal in `src/` lives in this file (CANONICAL_HOST, SEO_CANONICAL_HOST,
// CERT_VERIFY_HOST). A contract test
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
//      — MCP client redirect_uri allowlist (suffix model).
//   3. Cloudflare: confirm the new host is served by the Worker `platform`
//      (Custom Domain, or SaaS custom hostname — see the block at the end of this
//      file), NOT by the frozen Pages project, and that Bot Fight Mode does not
//      block datacenter IPs (the reason we left `.workers.dev`).
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
// SEO CANONICAL HOST — what search engines and link previews should index,
// decoupled from CANONICAL_HOST on purpose (GP decision, 2026-09-25, #2471).
//
// The same app answers 200 on several hosts (the OAuth/MCP host above, the
// chapter-seat entrance `nucleoia.pmigo.org.br`, and `nucleoia.org`). Without a
// declared canonical, search engines see duplicate sites. `nucleoia.org` was
// registered for the initiative itself: neutral across the 5 chapters and not a
// personal domain. So every page declares it in `<link rel="canonical">` and
// `og:url`, and the sitemap/feeds use it (astro.config `site`).
//
// Changing this constant re-points SEO only. It does NOT move the OAuth issuer,
// the MCP base or the certificate verification host; moving the OAuth identity is
// the FLIP CHECKLIST above, a separate decision.
// ─────────────────────────────────────────────────────────────────────────────

/** Host declared to search engines and link previews (no scheme). */
export const SEO_CANONICAL_HOST = "nucleoia.org";

/** SEO canonical origin, e.g. `https://nucleoia.org`. For canonical/og:url/sitemap/feeds only. */
export const SEO_CANONICAL_ORIGIN = `https://${SEO_CANONICAL_HOST}`;

// ─────────────────────────────────────────────────────────────────────────────
// CERTIFICATE VERIFICATION HOST — the institutional (chapter) domain PRINTED on
// certificates, decoupled from CANONICAL_HOST on purpose.
//
// WHY separate: a recognition certificate is a chapter-institutional artifact; it
// should carry the PMI Goiás domain (`nucleoia.pmigo.org.br`), not the platform's
// operational canonical host (which also identifies the OAuth issuer / MCP base and
// is only flipped via the gated checklist above). Since 2026-09-25
// `nucleoia.pmigo.org.br` is served directly by the Worker (no redirect; see the
// block below), so a printed link opens the verify page on the chapter host
// itself. Declared HERE (not hardcoded in pdf.ts) so the
// canonical-host-centralization contract test stays green — this is the sanctioned
// place for public-host literals.
// ─────────────────────────────────────────────────────────────────────────────

/** Host printed on certificate PDFs for the verification link (chapter-institutional). */
export const CERT_VERIFY_HOST = "nucleoia.pmigo.org.br";

// ─────────────────────────────────────────────────────────────────────────────
// HOW `nucleoia.pmigo.org.br` IS SERVED (since 2026-09-25, #2471)
// (measured on the live hosts unless a line says otherwise)
//
// The app moved from Cloudflare Pages to the Worker `platform`. The Worker is
// the only production owner, and Pages serves PR previews only: the project has
// `production_deployments_enabled: false`, so every push to `main` creates a
// deployment born `is_skipped: true`. That is DELIBERATE. Turning it back on
// resurrects two services answering for the same app. Do NOT "fix" anything by
// enabling Pages production deployments.
//
// The zone `pmigo.org.br` stays on the chapter's HostGator nameservers, so the
// host cannot be a Worker Custom Domain (those require the zone in this account).
// It is served through Cloudflare for SaaS on the dedicated zone `nucleoia.org`:
//   · HostGator: CNAME `nucleoia` → `saas.nucleoia.org` (plus 3 TXT records used
//     for the first certificate).
//   · Zone `nucleoia.org`: `saas.nucleoia.org AAAA 100::` (proxied) is the
//     fallback origin; `nucleoia.pmigo.org.br` is a custom hostname (cert by
//     SSL.com; per the vendor doc, not exercised yet, Cloudflare renews it over
//     HTTP once the host is proxied); the Worker route is the SPECIFIC
//     pattern `nucleoia.pmigo.org.br/*` → `platform`. Never `*/*`: on the shared
//     `vitormr.dev` zone that pattern hijacked every other site (2026-06-04).
//   · The middleware must NOT list this host in LEGACY_HOSTS, or it 301s again.
//
// LESSONS, so nobody re-derives them:
//   · A host already served by ANY Cloudflare product (here, the Pages custom
//     domain) is "orange-to-orange": TXT pre-validation does NOT activate it. The
//     custom hostname only activated after the CNAME pointed at the SaaS zone.
//     The certificate, though, was issued before the swap, so TLS had no gap.
//   · The edge routes by HOSTNAME, not by the IP a client resolved, so stale DNS
//     caches still land on whatever the edge assigns the host to.
//   · ROLLBACK is two-handed and in this order: delete the custom hostname on
//     `nucleoia.org` FIRST, then point the CNAME back to Pages. Not exercised; it
//     follows from the edge routing by hostname: reverting only the CNAME would
//     not return traffic while the custom hostname is active. This is
//     why the Pages custom domain is kept until the new path is proven; removing
//     it is the last step, and after it the rollback is no longer cheap.
//   · Two co-equal entrances are fine for SERVING; what cannot be duplicated is
//     the OAuth issuer / MCP base identity, which is what CANONICAL_HOST is. SEO
//     is a third, separate choice (SEO_CANONICAL_HOST above).
// ─────────────────────────────────────────────────────────────────────────────
