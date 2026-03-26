import type { APIRoute } from 'astro';

/**
 * OAuth 2.1 Dynamic Client Registration (RFC 7591)
 * Claude.ai needs this to register itself as an OAuth client before starting the auth flow.
 * We accept the registration and return a client_id that maps to our Supabase OAuth app.
 */

export const POST: APIRoute = async ({ request }) => {
  const body = await request.json();

  // Generate a deterministic client_id from the client_name + redirect_uris
  const clientName = body.client_name || 'mcp-client';
  const redirectUris: string[] = body.redirect_uris || [];
  const clientId = `nucleo-mcp-${crypto.randomUUID().slice(0, 8)}`;

  return new Response(JSON.stringify({
    client_id: clientId,
    client_name: clientName,
    redirect_uris: redirectUris,
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
