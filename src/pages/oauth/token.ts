import type { APIRoute } from 'astro';

/**
 * OAuth 2.1 Token endpoint — RETIRED STUB (#1210).
 *
 * Token issuance (authorization_code + refresh_token grants) moved to Supabase
 * Auth's native OAuth 2.1 server (`/auth/v1/oauth/token`, advertised in the
 * .well-known metadata). This Worker route MUST NOT issue or refresh tokens:
 * the hand-rolled flow handed the MCP client a COPY of the browser session's
 * refresh token, and the two holders raced each other over one rotating chain
 * (refresh_token_already_used → invalid_grant → re-login every ~1h; see #1053
 * for the proxy-refresher episode of the same class).
 *
 * Any client still calling this endpoint holds a pre-#1210 session. We answer
 * a clean OAuth `invalid_grant` so it restarts discovery and lands on the
 * native flow. The per-user KV refresh-copy entries the old flow maintained
 * are dead — left to expire via their 30-day TTL.
 */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

export const POST: APIRoute = () => {
  return new Response(
    JSON.stringify({
      error: 'invalid_grant',
      error_description:
        'This endpoint was retired — token issuance moved to the native authorization server. Reconnect to re-authorize.',
    }),
    {
      status: 400,
      headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...CORS },
    }
  );
};

export const OPTIONS: APIRoute = () => {
  return new Response(null, { status: 204, headers: CORS });
};
