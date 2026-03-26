import type { APIRoute } from 'astro';
import { env } from 'cloudflare:workers';

/**
 * OAuth code exchange endpoint.
 * Called by the consent page after user approves.
 * Generates an authorization code, stores code→access_token in KV,
 * and returns the redirect URL for Claude's callback.
 */
export const POST: APIRoute = async ({ request }) => {
  try {
    const body = await request.json().catch(() => ({}));
    const { access_token, oauth_data } = body as { access_token?: string; oauth_data?: string };

    if (!access_token || !oauth_data) {
      return new Response(JSON.stringify({ error: 'missing access_token or oauth_data' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    let oauthParams: any;
    try {
      oauthParams = JSON.parse(atob(oauth_data));
    } catch {
      return new Response(JSON.stringify({ error: 'invalid oauth_data' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Generate authorization code
    const code = crypto.randomUUID();

    // Store code → access_token + code_challenge in KV
    // Astro v6 + @astrojs/cloudflare v13: use import { env } from 'cloudflare:workers'
    const kv = (env as any).SESSION;
    if (kv) {
      await kv.put(`mcp_code:${code}`, JSON.stringify({
        access_token,
        code_challenge: oauthParams.code_challenge,
        code_challenge_method: oauthParams.code_challenge_method,
        client_id: oauthParams.client_id,
      }), { expirationTtl: 120 });
    } else {
      return new Response(JSON.stringify({ error: 'KV storage unavailable' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Build redirect URL
    const redirectUrl = new URL(oauthParams.redirect_uri);
    redirectUrl.searchParams.set('code', code);
    if (oauthParams.state) redirectUrl.searchParams.set('state', oauthParams.state);

    return new Response(JSON.stringify({ redirect_url: redirectUrl.toString() }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e: any) {
    return new Response(JSON.stringify({ error: 'server_error', detail: e?.message || 'unknown' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
};
