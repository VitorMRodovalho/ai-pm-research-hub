import { defineMiddleware } from 'astro:middleware';

/**
 * Bypass Astro's CSRF origin check for OAuth 2.1 and MCP proxy routes.
 * These endpoints receive POST from external origins (Claude.ai, ChatGPT)
 * and handle their own authentication (PKCE, JWT).
 *
 * All other routes benefit from checkOrigin: true in astro.config.
 */

const BYPASS_PREFIXES = ['/oauth/', '/mcp'];

export const onRequest = defineMiddleware((context, next) => {
  const path = context.url.pathname;
  const needsBypass = BYPASS_PREFIXES.some(p => path.startsWith(p));

  if (needsBypass) {
    // Set the origin header to match the URL so Astro's check passes
    const url = context.url;
    const origin = `${url.protocol}//${url.host}`;
    const headers = new Headers(context.request.headers);
    headers.set('origin', origin);
    const patched = new Request(context.request, { headers });
    return next(patched);
  }

  return next();
});
