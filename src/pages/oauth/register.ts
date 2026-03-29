// src/pages/oauth/register.ts
// Dynamic Client Registration — RFC 7591
// FIX: Returns a client_secret to avoid Supabase Auth admin panel crash
// (NULL client_secret_hash causes Go sql.Scan error)

import type { APIRoute } from "astro";
import { env } from "cloudflare:workers";

async function kvLog(endpoint: string, data: any) {
  try { const kv = (env as any).SESSION; if (kv) await kv.put(`debug:${endpoint}:${Date.now()}`, JSON.stringify({ timestamp: new Date().toISOString(), endpoint, ...data }), { expirationTtl: 3600 }); } catch {}
}

// This is the Supabase Auth OAuth client ID registered for MCP
const SUPABASE_CLIENT_ID = "8636c0d0-a359-45f5-a2a4-8097dbdaabd6";

// Deterministic secret derived from client_id (not a real secret since this
// is a public client, but prevents NULL columns in Supabase Auth)
const CLIENT_SECRET_PLACEHOLDER = `mcp_pub_${SUPABASE_CLIENT_ID.replace(/-/g, "")}`;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

export const POST: APIRoute = async ({ request }) => {
  const rawBody = await request.text();
  await kvLog("register", { method: request.method, body: rawBody, userAgent: request.headers.get("user-agent") });
  const body = JSON.parse(rawBody || "{}") as any;

  return new Response(
    JSON.stringify({
      client_id: SUPABASE_CLIENT_ID,
      client_secret: CLIENT_SECRET_PLACEHOLDER,
      client_name: body.client_name || "mcp-client",
      redirect_uris: body.redirect_uris || [],
      grant_types: body.grant_types || ["authorization_code", "refresh_token"],
      response_types: body.response_types || ["code"],
      token_endpoint_auth_method: "none", // still public, secret is just placeholder
      client_id_issued_at: Math.floor(Date.now() / 1000),
      client_secret_expires_at: 0,
    }),
    {
      status: 201,
      headers: { "Content-Type": "application/json", ...CORS },
    }
  );
};

export const OPTIONS: APIRoute = () => {
  return new Response(null, { status: 204, headers: CORS });
};
