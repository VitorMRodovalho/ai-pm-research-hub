import type { APIRoute } from 'astro';
import { env } from 'cloudflare:workers';
import { resolveSupabaseAuthConfig } from '../../lib/mcp-refresh';

/**
 * OAuth 2.1 Authorization endpoint — COMPAT PASSTHROUGH (#1210).
 *
 * Token issuance moved to Supabase Auth's native OAuth 2.1 server; fresh
 * discovery sends clients straight to `/auth/v1/oauth/authorize`. This route
 * survives only for clients holding CACHED pre-#1210 metadata: it forwards the
 * request (same query string) to the native endpoint, where client_id,
 * redirect_uri and PKCE are validated against the registered OAuth app.
 * GoTrue then redirects the user to our consent page with ?authorization_id=.
 */
const GOTRUE_SCOPES = new Set(['openid', 'email', 'profile', 'phone']);

export const GET: APIRoute = ({ url }) => {
  const supabaseUrl = resolveSupabaseAuthConfig(env as any, import.meta.env).url;
  const target = new URL(`${supabaseUrl}/auth/v1/oauth/authorize`);
  url.searchParams.forEach((value, key) => target.searchParams.set(key, value));

  // Pre-#1210 metadata advertised custom scopes (mcp:tools, offline_access) that
  // GoTrue rejects. Keep only scopes it supports; drop the param entirely when
  // none survive (GoTrue then applies its default: email).
  const scope = target.searchParams.get('scope');
  if (scope) {
    const kept = scope.split(/\s+/).filter((s) => GOTRUE_SCOPES.has(s));
    if (kept.length) target.searchParams.set('scope', kept.join(' '));
    else target.searchParams.delete('scope');
  }

  return new Response(null, {
    status: 302,
    headers: { 'Location': target.toString() },
  });
};
