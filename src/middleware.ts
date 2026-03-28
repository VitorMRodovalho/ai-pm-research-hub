// src/middleware.ts
// FIX: Add /.well-known/ to bypass prefixes so OAuth discovery
// endpoints get proper origin headers and aren't blocked by auth middleware.

import { defineMiddleware, sequence } from "astro:middleware";

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

export const onRequest = sequence(corsMiddleware);
