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
