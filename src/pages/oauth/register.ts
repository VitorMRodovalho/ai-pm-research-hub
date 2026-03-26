import type { APIRoute } from 'astro';

/**
 * OAuth 2.1 Dynamic Client Registration (RFC 7591)
 * Returns our pre-registered Supabase OAuth client_id.
 * Claude.ai/ChatGPT call this before starting the OAuth flow.
 */

const SUPABASE_CLIENT_ID = '8636c0d0-a359-45f5-a2a4-8097dbdaabd6';

export const POST: APIRoute = async ({ request }) => {
  const body = await request.json().catch(() => ({}));

  return new Response(JSON.stringify({
    client_id: SUPABASE_CLIENT_ID,
    client_name: body.client_name || 'mcp-client',
    redirect_uris: body.redirect_uris || [],
    grant_types: body.grant_types || ['authorization_code', 'refresh_token'],
    response_types: body.response_types || ['code'],
    token_endpoint_auth_method: 'none',
    client_id_issued_at: Math.floor(Date.now() / 1000),
    client_secret_expires_at: 0,
  }), {
    status: 201,
    headers: { 'Content-Type': 'application/json' },
  });
};
