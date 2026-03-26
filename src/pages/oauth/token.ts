import type { APIRoute } from 'astro';

const SUPABASE_URL = 'https://ldrfrvwhxsmgaabwmaik.supabase.co';
const ANON_KEY = import.meta.env.PUBLIC_SUPABASE_ANON_KEY;

/**
 * OAuth 2.1 Token endpoint proxy.
 * Forwards to Supabase Auth with the apikey header injected.
 */
export const POST: APIRoute = async ({ request }) => {
  const body = await request.text();

  const res = await fetch(`${SUPABASE_URL}/auth/v1/oauth/token`, {
    method: 'POST',
    headers: {
      'Content-Type': request.headers.get('Content-Type') || 'application/x-www-form-urlencoded',
      'apikey': ANON_KEY,
    },
    body,
  });

  const respHeaders = new Headers(res.headers);
  respHeaders.set('Access-Control-Allow-Origin', '*');

  return new Response(res.body, {
    status: res.status,
    headers: respHeaders,
  });
};

// Handle CORS preflight
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
