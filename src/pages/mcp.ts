import type { APIRoute } from 'astro';
import { env } from 'cloudflare:workers';

async function kvLog(endpoint: string, data: any) {
  try { const kv = (env as any).SESSION; if (kv) await kv.put(`debug:${endpoint}:${Date.now()}`, JSON.stringify({ timestamp: new Date().toISOString(), endpoint, ...data }), { expirationTtl: 3600 }); } catch {}
}

const UPSTREAM = 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/mcp';
const BASE = 'https://nucleoia.vitormr.dev';
const SUPABASE_URL = 'https://ldrfrvwhxsmgaabwmaik.supabase.co';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type, Accept, Mcp-Session-Id',
  'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
  'Access-Control-Expose-Headers': 'Mcp-Session-Id',
};

// Decode JWT payload without verification (safe for reading sub/exp from our own tokens)
function decodeJwtPayload(token: string): { sub?: string; exp?: number } | null {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    return JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
  } catch { return null; }
}

// Try to refresh an expired token using the stored refresh_token in KV.
// On failure (stale/revoked token), DELETE the KV entry to prevent the stale
// token from being retried. Next /mcp call will return 401 and force re-auth.
async function tryAutoRefresh(sub: string, kv: any): Promise<string | null> {
  const refreshToken = await kv.get(`mcp_refresh:${sub}`);
  if (!refreshToken) return null;

  const ANON_KEY = import.meta.env.PUBLIC_SUPABASE_ANON_KEY || '';
  const res = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=refresh_token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'apikey': ANON_KEY },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });

  if (!res.ok) {
    // Refresh failed — purge stale KV entry to prevent retry loop
    await kv.delete(`mcp_refresh:${sub}`);
    return null;
  }
  const data = await res.json();
  if (!data.access_token) {
    await kv.delete(`mcp_refresh:${sub}`);
    return null;
  }

  // Update KV with new refresh_token
  if (data.refresh_token) {
    await kv.put(`mcp_refresh:${sub}`, data.refresh_token, { expirationTtl: 2592000 }); // 30 days
  }

  return data.access_token;
}

export const ALL: APIRoute = async ({ request }) => {
  const reqBody = request.method === 'POST' ? await request.clone().text() : null;
  await kvLog("mcp-request", {
    method: request.method,
    hasAuth: !!request.headers.get("authorization"),
    contentType: request.headers.get("content-type"),
    accept: request.headers.get("accept"),
    mcpSessionId: request.headers.get("mcp-session-id"),
    userAgent: request.headers.get("user-agent")?.substring(0, 80),
    bodyPreview: reqBody?.substring(0, 300),
  });

  // CORS preflight — allow without auth
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  // RFC 9728: if no Authorization header, return 401 to trigger OAuth flow
  const authHeader = request.headers.get('authorization');
  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'unauthorized', error_description: 'Bearer token required' }), {
      status: 401,
      headers: {
        'Content-Type': 'application/json',
        'WWW-Authenticate': `Bearer resource_metadata="${BASE}/.well-known/oauth-protected-resource"`,
        ...CORS_HEADERS,
      },
    });
  }

  // ── Auto-refresh: check if JWT is expired and refresh transparently ──
  let activeToken = authHeader.replace(/^Bearer\s+/i, '');
  const kv = (env as any).SESSION;

  if (kv) {
    const payload = decodeJwtPayload(activeToken);
    if (payload?.sub && payload?.exp) {
      const now = Math.floor(Date.now() / 1000);
      // Refresh if expired or will expire within 5 minutes
      if (payload.exp - 300 < now) {
        await kvLog("mcp-auto-refresh-attempt", { sub: payload.sub, exp: payload.exp, now });
        const newToken = await tryAutoRefresh(payload.sub, kv);
        if (newToken) {
          activeToken = newToken;
          await kvLog("mcp-auto-refresh-ok", { sub: payload.sub });
        } else {
          await kvLog("mcp-auto-refresh-fail", { sub: payload.sub });
        }
      }
    }
  }

  // Build upstream request with (possibly refreshed) token
  const headers = new Headers();
  headers.set('authorization', `Bearer ${activeToken}`);
  for (const key of ['content-type', 'accept', 'mcp-session-id', 'last-event-id']) {
    const val = request.headers.get(key);
    if (val) headers.set(key, val);
  }

  try {
    const upstream = new Request(UPSTREAM, {
      method: request.method,
      headers,
      body: request.method !== 'GET' && request.method !== 'HEAD'
        ? (reqBody ?? null)
        : null,
    });

    const res = await fetch(upstream);
    const contentType = res.headers.get("content-type") || "";
    const isSSE = contentType.includes("text/event-stream");

    // Forward response headers with CORS
    const respHeaders = new Headers(res.headers);
    for (const [k, v] of Object.entries(CORS_HEADERS)) respHeaders.set(k, v);

    // For SSE responses, stream through without buffering
    if (isSSE) {
      await kvLog("mcp-upstream", {
        status: res.status,
        contentType,
        streaming: true,
        headers: Object.fromEntries([...res.headers.entries()].filter(([k]) => !k.startsWith('x-') && k !== 'date')),
      });

      return new Response(res.body, {
        status: res.status,
        headers: respHeaders,
      });
    }

    // Non-SSE responses: buffer for logging, then forward
    const resBody = await res.text();

    await kvLog("mcp-upstream", {
      status: res.status,
      contentType,
      bodyLen: resBody.length,
      bodyPreview: resBody.substring(0, 500),
      headers: Object.fromEntries([...res.headers.entries()].filter(([k]) => !k.startsWith('x-') && k !== 'date')),
    });

    return new Response(resBody, {
      status: res.status,
      headers: respHeaders,
    });
  } catch (e: any) {
    await kvLog("mcp-error", { error: e.message, stack: e.stack?.substring(0, 300) });
    return new Response(JSON.stringify({ error: 'proxy_error', detail: e.message }), {
      status: 502,
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }
};
