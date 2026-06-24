// src/middleware.ts
// Canonical domain redirect + CSRF protection (manual, because Astro checkOrigin
// runs before middleware and blocks MCP/OAuth cross-origin POSTs) + SSR security
// headers (#855).
//
// #855: `public/_headers` is a Cloudflare-PAGES feature; on Workers it is a NO-OP
// for SSR HTML (it only decorates the static-asset system, /_astro/*). So the CSP /
// X-Frame-Options / etc. it declares never reach SSR responses (home `/`, every
// .astro page). We re-apply the SAME policy here, from the shared SSOT
// (src/lib/securityHeaders.ts), so SSR routes carry it too. A parity contract test
// (tests/contracts/855-ssr-security-headers-parity.test.mjs) keeps the two in sync.

import { defineMiddleware, sequence } from "astro:middleware";
import { CANONICAL_HOST } from "./lib/canonical";
import { applySecurityHeaders } from "./lib/securityHeaders";

const LEGACY_HOSTS = [
  "platform.ai-pm-research-hub.workers.dev",
  "ai-pm-research-hub.pages.dev",
  "mcp.vitormr.dev",
];

// Paths that accept cross-origin POST (MCP clients, OAuth flow, internal-only callbacks)
// /api/internal/ — invoked by DB trigger pg_net (cert PDF auto-gen, p225 #281)
const CSRF_BYPASS_PREFIXES = ["/oauth/", "/mcp", "/.well-known/", "/api/internal/"];

// 1) Redirect legacy domains to canonical (301 permanent). Short-circuits WITHOUT
//    next(), so a bare 301 never reaches the header step below — intended (a
//    redirect needs no CSP), identical to current prod behavior.
const redirectMiddleware = defineMiddleware((context, next) => {
  const host = context.url.hostname;
  if (LEGACY_HOSTS.includes(host)) {
    const newUrl = new URL(context.url);
    newUrl.hostname = CANONICAL_HOST;
    newUrl.protocol = "https:";
    return new Response(null, {
      status: 301,
      headers: { Location: newUrl.toString() },
    });
  }
  return next();
});

// 2) Manual CSRF: block cross-origin form POSTs on non-bypass routes. The 403
//    short-circuit also returns WITHOUT next() and stays header-free (intended).
const csrfMiddleware = defineMiddleware((context, next) => {
  const method = context.request.method;
  if (method !== "POST" && method !== "PUT" && method !== "DELETE") {
    return next();
  }

  const path = context.url.pathname;
  const isBypassed = CSRF_BYPASS_PREFIXES.some((p) => path.startsWith(p));
  if (isBypassed) {
    return next();
  }

  // Check origin matches host for non-bypassed POST routes
  const origin = context.request.headers.get("origin");
  if (origin) {
    try {
      const originHost = new URL(origin).hostname;
      const requestHost = context.url.hostname;
      if (originHost !== requestHost) {
        return new Response("Cross-site POST forbidden", { status: 403 });
      }
    } catch {
      return new Response("Invalid origin", { status: 403 });
    }
  }

  return next();
});

// 3) Security headers on every SSR response (#855). Runs LAST so it decorates the
//    rendered response coming back up. The header set + the Workers-immutability
//    guard live in the SSOT (applySecurityHeaders). Static assets (/_astro/*) are
//    served by the Cloudflare assets system and never enter Astro middleware, so
//    public/_headers keeps sole ownership of their immutable cache — no double-set.
const securityHeadersMiddleware = defineMiddleware(async (context, next) => {
  const response = await next();
  return applySecurityHeaders(response, context.url.pathname);
});

export const onRequest = sequence(
  redirectMiddleware,
  csrfMiddleware,
  securityHeadersMiddleware,
);
