// src/pages/.well-known/oauth-authorization-server.ts
// OAuth 2.1 Authorization Server Metadata — RFC 8414
//
// #1210 — token issuance migrated to Supabase Auth's NATIVE OAuth 2.1 server.
// authorize/token now point at GoTrue (`/auth/v1/oauth/*`), which mints a
// DEDICATED session per OAuth client (client-scoped refresh chain). This kills
// the ~1h re-login: the old hand-rolled flow handed Claude a COPY of the
// browser session's refresh token, so browser and connector raced each other
// over one rotating chain (refresh_token_already_used → invalid_grant).
//
// registration_endpoint stays OURS: a static shim returning the pre-registered
// Supabase OAuth app client_id (see src/pages/oauth/register.ts) — this keeps
// MCP-client DCR working WITHOUT enabling open dynamic registration on the
// Supabase project.
//
// issuer/registration derive from the REQUEST origin (not the pinned canonical
// constant) so the metadata stays self-consistent if served on the institutional
// alias (nucleoia.pmigo.org.br) once its Cloudflare redirect carve-out lands
// (#1210 scope 2). RFC 8414 §3.3: issuer must match the metadata's own URL.

import type { APIRoute } from "astro";
import { env } from "cloudflare:workers";
import { resolveSupabaseAuthConfig } from "../../lib/mcp-refresh";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, Accept, MCP-Session-Id",
};

export const GET: APIRoute = ({ url }) => {
  const origin = url.origin;
  const supabaseUrl = resolveSupabaseAuthConfig(env as any, import.meta.env).url;

  return new Response(
    JSON.stringify({
      issuer: origin,
      authorization_endpoint: `${supabaseUrl}/auth/v1/oauth/authorize`,
      token_endpoint: `${supabaseUrl}/auth/v1/oauth/token`,
      registration_endpoint: `${origin}/oauth/register`,
      jwks_uri: `${supabaseUrl}/auth/v1/.well-known/jwks.json`,
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      // GoTrue's OAuth server supports only openid/email/profile/phone (default:
      // email). Do NOT advertise the old custom scopes — GoTrue rejects them.
      scopes_supported: ["email"],
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
