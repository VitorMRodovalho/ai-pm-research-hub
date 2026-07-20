// src/pages/.well-known/oauth-protected-resource/[...path].ts
// RFC 9728 path-suffixed Protected Resource Metadata (PPX-3 / FM-03 / FM-04, audit 2026-07-20).
//
// The bare /.well-known/oauth-protected-resource advertises resource=origin/mcp for
// back-compat with clients that cached it. This catch-all lets each MCP surface advertise
// the EXACT resource it serves, so a spec-strict client (RFC 8707/9728) that validates the
// resource identifier against the endpoint it connected to sees a matching value instead of
// a /mcp-vs-/mcp/semantic mismatch. Only the real surfaces resolve; anything else 404s so
// this is not an open metadata reflector.

import type { APIRoute } from "astro";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, Accept, MCP-Session-Id",
};

const KNOWN_SURFACES = new Set(["mcp", "mcp/semantic", "mcp/actions"]);

export const GET: APIRoute = ({ params, url }) => {
  const path = String(params.path ?? "").replace(/^\/+|\/+$/g, "");
  if (!KNOWN_SURFACES.has(path)) {
    return new Response(JSON.stringify({ error: "not_found" }), {
      status: 404,
      headers: { "Content-Type": "application/json", ...CORS },
    });
  }
  const origin = url.origin;
  return new Response(
    JSON.stringify({
      resource: `${origin}/${path}`,
      authorization_servers: [origin],
      scopes_supported: ["email"],
    }),
    { headers: { "Content-Type": "application/json", ...CORS } }
  );
};

export const OPTIONS: APIRoute = () => new Response(null, { status: 204, headers: CORS });
