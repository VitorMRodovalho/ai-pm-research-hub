import type { APIRoute } from 'astro';

const SUPABASE_URL = 'https://ldrfrvwhxsmgaabwmaik.supabase.co';
const ANON_KEY = import.meta.env.PUBLIC_SUPABASE_ANON_KEY;

/**
 * OAuth 2.1 Authorization endpoint proxy.
 * Forwards to Supabase Auth with the apikey header injected.
 */
export const GET: APIRoute = async ({ request }) => {
  const url = new URL(request.url);
  const params = url.searchParams.toString();

  // Redirect browser to Supabase's authorize endpoint with apikey as query param
  const target = `${SUPABASE_URL}/auth/v1/oauth/authorize?${params}&apikey=${ANON_KEY}`;

  return Response.redirect(target, 302);
};
