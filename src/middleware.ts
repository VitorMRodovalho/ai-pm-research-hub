// src/middleware.ts
// Canonical domain redirect + CSRF bypass for OAuth/MCP paths

import { defineMiddleware, sequence } from "astro:middleware";

const CANONICAL_HOST = "nucleoia.vitormr.dev";
const LEGACY_HOSTS = [
  "platform.ai-pm-research-hub.workers.dev",
  "ai-pm-research-hub.pages.dev",
  "mcp.vitormr.dev",
];

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

// CORS/origin bypass for MCP and OAuth paths (checkOrigin: true)
const BYPASS_PREFIXES = ["/oauth/", "/mcp", "/.well-known/"];

const corsMiddleware = defineMiddleware((context, next) => {
  const path = context.url.pathname;
  const needsBypass = BYPASS_PREFIXES.some((p) => path.startsWith(p));

  if (needsBypass) {
    const url = context.url;
    const origin = `${url.protocol}//${url.host}`;
    const headers = new Headers(context.request.headers);
    headers.set("origin", origin);
    const patched = new Request(context.request, { headers });
    return next(patched);
  }

  return next();
});

export const onRequest = sequence(redirectMiddleware, corsMiddleware);
