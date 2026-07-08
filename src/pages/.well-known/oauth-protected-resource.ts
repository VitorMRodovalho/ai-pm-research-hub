// src/pages/.well-known/oauth-protected-resource.ts
// MCP Auth Discovery — RFC 9728
//
// #1210 — origin-aware: `resource` and `authorization_servers` reflect the host
// the client actually connected on, so the same route serves the canonical host
// today and the institutional alias (nucleoia.pmigo.org.br) once its Cloudflare
// redirect carve-out lands. The advertised authorization server is OUR metadata
// route (hybrid: authorize/token → Supabase native, registration → our shim).

import type { APIRoute } from "astro";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, Accept, MCP-Session-Id",
};

export const GET: APIRoute = ({ url }) => {
  const origin = url.origin;
  return new Response(
    JSON.stringify({
      resource: `${origin}/mcp`,
      authorization_servers: [origin],
      scopes_supported: ["email"],
    }),
    {
      headers: { "Content-Type": "application/json", ...CORS },
    }
  );
};

export const OPTIONS: APIRoute = () => {
  return new Response(null, { status: 204, headers: CORS });
};
