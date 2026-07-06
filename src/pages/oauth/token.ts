import type { APIRoute } from 'astro';
import { env } from 'cloudflare:workers';
import { isAllowedRedirectUri } from '../../lib/oauth-security';
// #580 — single source for JWT decode + the KV refresh-token TTL (shared with the proxies).
import {
  decodeJwtPayload,
  MCP_REFRESH_TTL_SECONDS,
  resolveSupabaseAuthConfig,
} from '../../lib/mcp-refresh';
// #1050 — per-IP throttle on the token endpoint (brute-force/flood dampening).
import { checkIpRateLimit, clientIpFrom } from '../../lib/ip-rate-limit';

async function kvLog(_endpoint: string, _data: any) {
  // No-op: KV debug logs disabled (free tier 1k writes/day protection).
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

    // #1050 — throttle token grants per client IP (30/min). Covers both the
    // authorization_code and refresh_token grants. Fail-open (see ip-rate-limit.ts).
    const rl = await checkIpRateLimit(kv, clientIpFrom(request), 'oauth_token', 30);
    if (!rl.allowed) {
      return new Response(JSON.stringify({ error: 'rate_limited', error_description: 'Too many token requests — retry shortly' }), {
        status: 429,
        headers: {
          'Content-Type': 'application/json',
          'Retry-After': String(rl.retryAfter ?? 60),
          'Access-Control-Allow-Origin': '*',
        },
      });
    }

    const supabaseAuth = resolveSupabaseAuthConfig(env as any, import.meta.env);
    const SUPABASE_URL = supabaseAuth.url;
    const SUPABASE_ANON_KEY = supabaseAuth.anonKey;

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
          await kvLog("token-refresh-fail", { status: res.status, error: data.error_description || data.error || 'unknown', refreshLen: refresh_token.length });
          // Clean stale KV entry so next auto-refresh fails fast and forces re-auth.
          // We can't know which sub this token belongs to, so we scan on best-effort basis.
          // Instead, we signal invalid_grant + revoked so the client initiates a new OAuth flow.
          return new Response(JSON.stringify({ error: 'invalid_grant', error_description: data.error_description || 'refresh_token revoked or expired — reconnect required' }), {
            status: 400, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
          });
        }
        await kvLog("token-refresh-ok", { newTokenLen: data.access_token.length });

        // Update stored refresh_token for server-side auto-refresh.
        // #580 LOW — log (not swallow) decode/KV-store failures: a malformed
        // access_token would otherwise silently leave the session without
        // server-side auto-refresh. Kept fail-safe: the client still gets its 200.
        // The `|| refresh_token` fallback re-stores the CLIENT-supplied token on a
        // partial 200. Safe: the client must present a valid Supabase refresh_token
        // to get a 200 at all, and the write only touches its own mcp_refresh:{sub}.
        const newRefresh = data.refresh_token || refresh_token;
        try {
          const refreshPayload = decodeJwtPayload(data.access_token);
          if (refreshPayload?.sub) {
            await kv.put(`mcp_refresh:${refreshPayload.sub}`, newRefresh, { expirationTtl: MCP_REFRESH_TTL_SECONDS });
          } else {
            await kvLog("token-refresh-store-skip", { reason: "jwt-decode-no-sub", tokenLen: data.access_token?.length });
          }
        } catch (e: any) {
          await kvLog("token-refresh-store-error", { error: e?.message });
        }

        return new Response(JSON.stringify({
          access_token: data.access_token,
          token_type: 'Bearer',
          expires_in: data.expires_in || 3600,
          refresh_token: newRefresh,
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

    if (redirect_uri && !isAllowedRedirectUri(redirect_uri)) {
      return new Response(JSON.stringify({ error: 'invalid_grant', error_description: 'redirect_uri not permitted' }), {
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

    // RFC 6749 §4.1.3: if redirect_uri was used in the authorization request,
    // the token request MUST include the same redirect_uri (binding).
    if (stored.redirect_uri && redirect_uri && stored.redirect_uri !== redirect_uri) {
      return new Response(JSON.stringify({ error: 'invalid_grant', error_description: 'redirect_uri mismatch' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

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

    // Store refresh_token in KV keyed by user_id for server-side auto-refresh.
    // #580 LOW — log (not swallow) decode/KV-store failures (see refresh grant above).
    if (stored.refresh_token) {
      try {
        const codePayload = decodeJwtPayload(stored.access_token);
        if (codePayload?.sub) {
          await kv.put(`mcp_refresh:${codePayload.sub}`, stored.refresh_token, { expirationTtl: MCP_REFRESH_TTL_SECONDS });
          await kvLog("token-refresh-stored", { sub: codePayload.sub });
        } else {
          await kvLog("token-refresh-store-skip", { reason: "jwt-decode-no-sub", tokenLen: stored.access_token?.length });
        }
      } catch (e: any) {
        await kvLog("token-refresh-store-error", { error: e?.message });
      }
    }

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
