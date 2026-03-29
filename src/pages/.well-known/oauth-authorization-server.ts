// src/pages/.well-known/oauth-authorization-server.ts
// OAuth 2.1 Authorization Server Metadata — RFC 8414
// FIX: Added CORS headers + OPTIONS handler for MCP client compatibility

import type { APIRoute } from "astro";

const BASE = "https://mcp.vitormr.dev";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, Accept, MCP-Session-Id",
};

export const GET: APIRoute = () => {
  return new Response(
    JSON.stringify({
      issuer: BASE,
      authorization_endpoint: `${BASE}/oauth/authorize`,
      token_endpoint: `${BASE}/oauth/token`,
      registration_endpoint: `${BASE}/oauth/register`,
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none"],
    }),
    {
      headers: { "Content-Type": "application/json", ...CORS },
    }
  );
};

export const OPTIONS: APIRoute = () => {
  return new Response(null, { status: 204, headers: CORS });
};
