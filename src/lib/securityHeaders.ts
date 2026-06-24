// src/lib/securityHeaders.ts
// ─────────────────────────────────────────────────────────────────────────────
// SINGLE SOURCE OF TRUTH for the SSR security-header policy (#855).
//
// WHY this exists: the platform deploys to Cloudflare WORKERS (astro.config
// output:'server', adapter @astrojs/cloudflare, wrangler main =
// @astrojs/cloudflare/entrypoints/server). `public/_headers` is a Cloudflare
// PAGES feature — on Workers it ONLY decorates the static-asset system
// (/_astro/*). SSR HTML routes (home `/`, `/admin/*`, every .astro page) are
// served by the Worker and `_headers` NEVER touches them. So the CSP /
// X-Frame-Options / etc. that `_headers` declares are a NO-OP for SSR responses
// (confirmed live 2026-06-23: /_astro/* carries them, `/` and `/admin` return
// 200 with ZERO of them).
//
// The fix (src/middleware.ts) re-applies the SAME policy from THIS module onto
// SSR responses. To stop the two from drifting, the canonical CSP and the global
// header map live HERE, and a contract test
// (tests/contracts/855-ssr-security-headers-parity.test.mjs) parses the `/*`
// block of public/_headers and asserts it byte-equals CSP below.
//
// Framework-free on purpose: NO astro imports, so the contract test can import
// it under plain `node --test`.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Canonical Content-Security-Policy. MUST stay byte-identical to the `/*` block
 * of public/_headers (guarded by the parity contract test). When you change the
 * CSP, change it in BOTH places in the same PR — the test fails the build if you
 * forget one side.
 *
 * `frame-ancestors 'none'` mirrors `X-Frame-Options: DENY` in the CSP layer
 * (modern UAs prefer frame-ancestors; this prevents a future permissive CSP from
 * silently overriding the XFO header). `frame-src 'none'` keeps the page from
 * EMBEDDING third-party frames; both are intentional for the public surface.
 */
export const CSP =
  "default-src 'self'; " +
  "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://us-assets.i.posthog.com https://us.posthog.com; " +
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; " +
  "font-src 'self' https://fonts.gstatic.com; " +
  "img-src 'self' data: blob: https://ldrfrvwhxsmgaabwmaik.supabase.co https://*.googleusercontent.com; " +
  "connect-src 'self' https://ldrfrvwhxsmgaabwmaik.supabase.co wss://ldrfrvwhxsmgaabwmaik.supabase.co https://us.posthog.com https://us-assets.i.posthog.com https://*.sentry.io; " +
  "frame-src 'none'; " +
  "object-src 'none'; " +
  "frame-ancestors 'none'; " +
  "base-uri 'self'";

/**
 * Global security headers applied to EVERY SSR response (mirrors `_headers /*`).
 * HSTS is intentionally NOT here — Cloudflare already terminates TLS +
 * http→https-redirects, and app-level HSTS with includeSubDomains would pin
 * EVERY *.vitormr.dev subdomain; vitormr.dev must stay co-hosted FOREVER for
 * already-issued cert-PDF verification URLs + live MCP clients. Add it
 * deliberately, with a short max-age first and NO `preload`, if/when we decide
 * to (separate PR, not #855).
 */
export const GLOBAL_SECURITY_HEADERS: Readonly<Record<string, string>> = {
  "X-Frame-Options": "DENY",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
  "Content-Security-Policy": CSP,
};

/**
 * Path prefixes / exact-paths that must NOT be cached (mirrors the per-route
 * `Cache-Control: no-cache, no-store, must-revalidate` blocks in _headers).
 * The public home (`/`) is deliberately ABSENT so it stays cacheable-ish.
 * `/api/` is added defensively: Workers do not cache Worker responses by default,
 * but a future cache rule could otherwise catch JSON endpoints.
 */
export const NO_STORE_PREFIXES: readonly string[] = [
  "/tribe/",
  "/admin/",
  "/en/",
  "/es/",
  "/api/",
];
export const NO_STORE_EXACT: readonly string[] = ["/profile", "/workspace"];

/** Path prefixes that must carry X-Robots-Tag: noindex, nofollow (admin only). */
export const NOINDEX_PREFIXES: readonly string[] = ["/admin/"];

export const NO_STORE_VALUE = "no-cache, no-store, must-revalidate";
export const NOINDEX_VALUE = "noindex, nofollow";

/**
 * Set both the legacy `X-Frame-Options`/etc. headers and the CSP onto a response.
 * Defensive against Cloudflare Workers immutable-Headers responses: a normal
 * Astro SSR render returns a Response with MUTABLE headers, but a cached/redirect
 * Response can have immutable headers and `.set()` would throw. On throw we clone
 * into a fresh mutable Response so we never 500 a page over a header write.
 *
 * Lives here (not in middleware.ts) so it is framework-free and so the parity
 * test sees the SSOT applying its own constants.
 *
 * @param response  the Response coming back from `next()`
 * @param pathname  context.url.pathname (drives per-route no-store / noindex)
 * @returns         the same response (mutated) or a mutable clone of it
 */
export function applySecurityHeaders(
  response: Response,
  pathname: string,
): Response {
  let target = response;
  try {
    target.headers.set(
      "X-Frame-Options",
      GLOBAL_SECURITY_HEADERS["X-Frame-Options"],
    );
  } catch {
    target = new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: new Headers(response.headers),
    });
    target.headers.set(
      "X-Frame-Options",
      GLOBAL_SECURITY_HEADERS["X-Frame-Options"],
    );
  }

  for (const [name, value] of Object.entries(GLOBAL_SECURITY_HEADERS)) {
    target.headers.set(name, value);
  }

  if (isNoStorePath(pathname)) {
    target.headers.set("Cache-Control", NO_STORE_VALUE);
  }
  if (isNoIndexPath(pathname)) {
    target.headers.set("X-Robots-Tag", NOINDEX_VALUE);
  }

  return target;
}

// A `/foo/` prefix also matches the BARE `/foo` (no trailing slash). Without this,
// the index route `/admin` escaped `/admin/` and shipped without no-store/noindex
// (caught in live validation of #855) while `/admin/members` was covered.
function prefixMatches(pathname: string, prefix: string): boolean {
  return pathname === prefix.slice(0, -1) || pathname.startsWith(prefix);
}

/** True when `pathname` must be served with a no-store Cache-Control. */
export function isNoStorePath(pathname: string): boolean {
  return (
    NO_STORE_EXACT.includes(pathname) ||
    NO_STORE_PREFIXES.some((p) => prefixMatches(pathname, p))
  );
}

/** True when `pathname` must carry X-Robots-Tag: noindex, nofollow. */
export function isNoIndexPath(pathname: string): boolean {
  return NOINDEX_PREFIXES.some((p) => prefixMatches(pathname, p));
}
