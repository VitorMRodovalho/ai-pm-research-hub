// src/pages/oauth/register.ts
// Dynamic Client Registration — RFC 7591 (TRUE DCR since #1428 member onboarding).
//
// HISTORY: this used to be a SHIM that returned a single shared, hardcoded client_id
// (8636c0d0) and merely echoed the requested redirect_uris without persisting them.
// GoTrue validates redirect_uri against that ONE client's fixed allow-list, so every
// client whose callback was not pre-listed (Perplexity, Cursor, Manus, xAI, ...) failed
// authorize with 400 invalid_redirect_uri. And Supabase's admin "update OAuth client"
// endpoint is currently broken (500), so widening the shared allow-list is impossible.
//
// NOW: each registration CREATES a dedicated public OAuth client via the GoTrue admin
// API (POST /auth/v1/admin/oauth/clients), persisting the client's own redirect_uris.
// Admin CREATE + DELETE work (only UPDATE is broken), so per-client creation is the
// clean path. Existing connectors on the old shared client keep working (create-only,
// nothing is mutated). See memory reference-mcp-dcr-shim-fixed-client-redirect-allowlist.
//
// Security: DCR is an open, unauthenticated endpoint by design (MCP clients register
// BEFORE the user logs in). A created client can do NOTHING until a real user completes
// the consent flow and approves it — user auth + the consent screen remain the gate.
// We validate redirect_uris (https, or http://localhost for dev) and cap the count to
// limit spam value. Data access is never granted by registration alone.

import type { APIRoute } from "astro";
import { env as cfEnv } from "cloudflare:workers";

// Backward-compat fallback: the pre-existing shared client. Used only when the admin
// API is unreachable (e.g. local dev without a service role key). Its fixed allow-list
// (claude.ai, claude.com, chatgpt.com, localhost) still works for those callbacks.
const FALLBACK_CLIENT_ID = "8636c0d0-a359-45f5-a2a4-8097dbdaabd6";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

const json = (obj: unknown, status = 201) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });

// IMPORTANT: we register PUBLIC clients (token_endpoint_auth_method: "none", PKCE) and MUST
// NOT return a client_secret. Returning even a placeholder secret makes some clients
// (observed: Perplexity) treat themselves as confidential and send `client_secret_post` at
// /oauth/token, which GoTrue rejects — "client is registered for 'none' but 'client_secret_post'
// was used" (400 invalid_credentials). RFC 7591: a public client gets no client_secret.

function sanitizeRedirectUris(input: unknown): string[] {
  if (!Array.isArray(input)) return [];
  const out: string[] = [];
  for (const raw of input) {
    if (typeof raw !== "string" || out.length >= 5) continue;
    try {
      const u = new URL(raw);
      const isHttpsProd = u.protocol === "https:";
      const isLocalDev = u.protocol === "http:" && (u.hostname === "localhost" || u.hostname === "127.0.0.1");
      if ((isHttpsProd || isLocalDev) && !out.includes(raw)) out.push(raw);
    } catch { /* skip malformed URI */ }
  }
  return out;
}

export const POST: APIRoute = async ({ request }) => {
  let body: any = {};
  try { body = JSON.parse((await request.text()) || "{}"); } catch { /* keep {} */ }

  const redirectUris = sanitizeRedirectUris(body.redirect_uris);
  const clientName = typeof body.client_name === "string" && body.client_name.trim()
    ? body.client_name.trim().slice(0, 120)
    : "mcp-client";
  const grantTypes = Array.isArray(body.grant_types) && body.grant_types.length
    ? body.grant_types
    : ["authorization_code", "refresh_token"];
  const responseTypes = Array.isArray(body.response_types) && body.response_types.length
    ? body.response_types
    : ["code"];

  const supabaseUrl = (cfEnv as any)?.SUPABASE_URL || import.meta.env.PUBLIC_SUPABASE_URL;
  const serviceRoleKey = (cfEnv as any)?.SUPABASE_SERVICE_ROLE_KEY;

  // TRUE DCR: mint a dedicated public client with the caller's own redirect_uris.
  if (supabaseUrl && serviceRoleKey && redirectUris.length) {
    try {
      const resp = await fetch(`${supabaseUrl}/auth/v1/admin/oauth/clients`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${serviceRoleKey}`,
          apikey: serviceRoleKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          client_name: clientName,
          client_type: "public",
          token_endpoint_auth_method: "none",
          grant_types: grantTypes,
          response_types: responseTypes,
          redirect_uris: redirectUris,
        }),
      });

      if (resp.ok) {
        const created = (await resp.json()) as any;
        return json({
          client_id: created.client_id,
          client_name: created.client_name ?? clientName,
          redirect_uris: created.redirect_uris ?? redirectUris,
          grant_types: created.grant_types ?? grantTypes,
          response_types: created.response_types ?? responseTypes,
          token_endpoint_auth_method: "none",
          client_id_issued_at: Math.floor(Date.now() / 1000),
        });
      }
      // Non-2xx from admin API → fall through to the shared-client fallback below.
    } catch { /* network/parse error → fall through */ }
  }

  // Fallback (no service role, or admin API failed): return the shared client. Only its
  // pre-registered callbacks will pass authorize — same behavior as before true DCR.
  return json({
    client_id: FALLBACK_CLIENT_ID,
    client_name: clientName,
    redirect_uris: body.redirect_uris || [],
    grant_types: grantTypes,
    response_types: responseTypes,
    token_endpoint_auth_method: "none",
    client_id_issued_at: Math.floor(Date.now() / 1000),
  });
};

export const OPTIONS: APIRoute = () => {
  return new Response(null, { status: 204, headers: CORS });
};
