import type { APIRoute } from 'astro';
import { env } from 'cloudflare:workers';

async function kvLog(endpoint: string, data: any) {
  try { const kv = (env as any).SESSION; if (kv) await kv.put(`debug:${endpoint}:${Date.now()}`, JSON.stringify({ timestamp: new Date().toISOString(), endpoint, ...data }), { expirationTtl: 3600 }); } catch {}
}

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

export const POST: APIRoute = async ({ request }) => {
  try {
    const contentType = request.headers.get('Content-Type') || '';
    await kvLog("token-request", { contentType, userAgent: request.headers.get("user-agent") });
    let params: Record<string, string> = {};

    if (contentType.includes('application/x-www-form-urlencoded')) {
      const text = await request.text();
      const urlParams = new URLSearchParams(text);
      for (const [k, v] of urlParams) params[k] = v;
    } else if (contentType.includes('application/json')) {
      params = await request.json();
    }

    const { grant_type, code, code_verifier, client_id, redirect_uri } = params;
    await kvLog("token-params", { grant_type, client_id, code: code?.substring(0, 8), redirect_uri, verifierLen: code_verifier?.length });

    const kv = (env as any).SESSION;
    if (!kv) {
      return new Response(JSON.stringify({ error: 'server_error', detail: 'KV binding unavailable' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const SUPABASE_URL = import.meta.env.PUBLIC_SUPABASE_URL || '';
    const SUPABASE_ANON_KEY = import.meta.env.PUBLIC_SUPABASE_ANON_KEY || '';

    // ── grant_type=refresh_token ──
    if (grant_type === 'refresh_token') {
      const refresh_token = params.refresh_token;
      if (!refresh_token) {
        return new Response(JSON.stringify({ error: 'invalid_request', error_description: 'refresh_token required' }), {
          status: 400, headers: { 'Content-Type': 'application/json' },
        });
      }
      await kvLog("token-refresh", { refreshLen: refresh_token.length });

      try {
        // Exchange refresh_token for new session via Supabase Auth API
        const res = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=refresh_token`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'apikey': SUPABASE_ANON_KEY },
          body: JSON.stringify({ refresh_token }),
        });
        const data = await res.json();
        if (!res.ok || !data.access_token) {
          await kvLog("token-refresh-fail", { status: res.status, error: data.error_description || data.error || 'unknown' });
          return new Response(JSON.stringify({ error: 'invalid_grant', error_description: data.error_description || 'refresh failed' }), {
            status: 400, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
          });
        }
        await kvLog("token-refresh-ok", { newTokenLen: data.access_token.length });
        return new Response(JSON.stringify({
          access_token: data.access_token,
          token_type: 'Bearer',
          expires_in: data.expires_in || 3600,
          refresh_token: data.refresh_token || refresh_token,
        }), {
          status: 200,
          headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*' },
        });
      } catch (e: any) {
        await kvLog("token-refresh-error", { error: e.message });
        return new Response(JSON.stringify({ error: 'server_error', detail: e.message }), {
          status: 500, headers: { 'Content-Type': 'application/json' },
        });
      }
    }

    // ── grant_type=authorization_code ──
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

    // Look up code
    const raw = await kv.get(`mcp_code:${code}`);
    await kvLog("token-kv", { codeExists: !!raw });
    if (!raw) {
      return new Response(JSON.stringify({ error: 'invalid_grant', error_description: 'code expired or invalid' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const stored = JSON.parse(raw);

    // Verify PKCE
    const computedChallenge = await sha256base64url(code_verifier);
    const pkceValid = computedChallenge === stored.code_challenge;
    await kvLog("token-pkce", { valid: pkceValid, computed: computedChallenge?.substring(0, 16), stored: stored.code_challenge?.substring(0, 16) });
    if (computedChallenge !== stored.code_challenge) {
      return new Response(JSON.stringify({ error: 'invalid_grant', error_description: 'PKCE verification failed' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Delete code (one-time use)
    await kv.delete(`mcp_code:${code}`);

    // Return the Supabase access_token + refresh_token
    await kvLog("token-success", { tokenLen: stored.access_token?.length, hasRefresh: !!stored.refresh_token });
    const tokenResponse: Record<string, any> = {
      access_token: stored.access_token,
      token_type: 'Bearer',
      expires_in: 3600,
    };
    if (stored.refresh_token) {
      tokenResponse.refresh_token = stored.refresh_token;
    }
    return new Response(JSON.stringify(tokenResponse), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store',
        'Access-Control-Allow-Origin': '*',
      },
    });
  } catch (e: any) {
    return new Response(JSON.stringify({ error: 'server_error', detail: e?.message || 'unknown' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
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
