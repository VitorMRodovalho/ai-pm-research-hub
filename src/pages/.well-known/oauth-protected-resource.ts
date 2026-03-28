// src/pages/.well-known/oauth-protected-resource.ts
// MCP Auth Discovery — RFC 9728
// FIX: Added CORS headers + OPTIONS handler for MCP client compatibility

import type { APIRoute } from "astro";

const BASE = "https://platform.ai-pm-research-hub.workers.dev";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, Accept, MCP-Session-Id",
};

export const GET: APIRoute = () => {
  return new Response(
    JSON.stringify({
      resource: `${BASE}/mcp`,
      authorization_servers: [BASE],
      scopes_supported: ["mcp:tools"],
    }),
    {
      headers: { "Content-Type": "application/json", ...CORS },
    }
  );
};

export const OPTIONS: APIRoute = () => {
  return new Response(null, { status: 204, headers: CORS });
};
