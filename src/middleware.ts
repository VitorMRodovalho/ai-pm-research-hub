// src/middleware.ts
// Canonical domain redirect + CSRF protection (manual, because Astro checkOrigin
// runs before middleware and blocks MCP/OAuth cross-origin POSTs)

import { defineMiddleware, sequence } from "astro:middleware";

const CANONICAL_HOST = "nucleoia.vitormr.dev";
const LEGACY_HOSTS = [
  "platform.ai-pm-research-hub.workers.dev",
  "ai-pm-research-hub.pages.dev",
  "mcp.vitormr.dev",
];

// Paths that accept cross-origin POST (MCP clients, OAuth flow)
const CSRF_BYPASS_PREFIXES = ["/oauth/", "/mcp", "/.well-known/"];

// Redirect legacy domains to canonical (301 permanent)
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

// Manual CSRF: block cross-origin form POSTs on non-bypass routes
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

export const onRequest = sequence(redirectMiddleware, csrfMiddleware);
