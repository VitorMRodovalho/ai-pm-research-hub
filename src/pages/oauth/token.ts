import type { APIRoute } from 'astro';

/**
 * OAuth 2.1 Token endpoint.
 * Exchanges authorization code for access_token.
 * Verifies PKCE code_challenge before returning.
 */

async function sha256base64url(input: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(input);
  const hash = await crypto.subtle.digest('SHA-256', data);
  const base64 = btoa(String.fromCharCode(...new Uint8Array(hash)));
  return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export const POST: APIRoute = async ({ request, locals }) => {
  const contentType = request.headers.get('Content-Type') || '';
  let params: Record<string, string> = {};

  if (contentType.includes('application/x-www-form-urlencoded')) {
    const text = await request.text();
    const urlParams = new URLSearchParams(text);
    for (const [k, v] of urlParams) params[k] = v;
  } else if (contentType.includes('application/json')) {
    params = await request.json();
  }

  const { grant_type, code, code_verifier, client_id } = params;

  if (grant_type !== 'authorization_code') {
    return new Response(JSON.stringify({ error: 'unsupported_grant_type' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  if (!code || !code_verifier) {
    return new Response(JSON.stringify({ error: 'invalid_request', error_description: 'code and code_verifier required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const kv = (locals as any).runtime?.env?.SESSION;
  if (!kv) {
    return new Response(JSON.stringify({ error: 'server_error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Look up code
  const raw = await kv.get(`mcp_code:${code}`);
  if (!raw) {
    return new Response(JSON.stringify({ error: 'invalid_grant', error_description: 'code expired or invalid' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const stored = JSON.parse(raw);

  // Verify PKCE
  const computedChallenge = await sha256base64url(code_verifier);
  if (computedChallenge !== stored.code_challenge) {
    return new Response(JSON.stringify({ error: 'invalid_grant', error_description: 'PKCE verification failed' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Delete code (one-time use)
  await kv.delete(`mcp_code:${code}`);

  // Return the Supabase access_token
  return new Response(JSON.stringify({
    access_token: stored.access_token,
    token_type: 'Bearer',
    expires_in: 3600,
  }), {
    status: 200,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
      'Access-Control-Allow-Origin': '*',
    },
  });
};

export const OPTIONS: APIRoute = () => {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    },
  });
};
