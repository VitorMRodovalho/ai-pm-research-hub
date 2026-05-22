import type { APIRoute } from 'astro';
import { env } from 'cloudflare:workers';
import {
  checkRateLimit,
  extractToolName,
  GENERAL_LIMIT_PER_MIN,
  DESTRUCTIVE_LIMIT_PER_MIN,
} from '../lib/mcp-rate-limit';

async function kvLog(_endpoint: string, _data: any) {
  // No-op: KV debug logs disabled to protect free tier write limit (1k/day).
  // Was writing `debug:${endpoint}:${Date.now()}` on every MCP/OAuth request.
  // Re-enable only with env.DEBUG_KV_LOGS flag if needed for specific debugging.
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
  const payload = decodeJwtPayload(activeToken);

  if (kv && payload?.sub && payload?.exp) {
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

  // ── ADR-0018 W2: rate limit per-member (100/min general + 10/min destructive) ──
  // Fail-open on KV errors; the RPC layer canV4 gate remains the authority guard.
  if (kv && payload?.sub) {
    const toolName = extractToolName(reqBody);
    const rl = await checkRateLimit(kv, payload.sub, toolName);
    if (!rl.allowed) {
      return new Response(JSON.stringify({
        jsonrpc: "2.0",
        error: {
          code: -32029,
          message: rl.reason || "Rate limit exceeded",
          data: { limitKind: rl.limitKind, retryAfter: rl.retryAfter ?? 60 },
        },
        id: null,
      }), {
        status: 429,
        headers: {
          "Content-Type": "application/json",
          "Retry-After": String(rl.retryAfter ?? 60),
          "X-RateLimit-Limit": String(rl.limitKind === "destructive" ? DESTRUCTIVE_LIMIT_PER_MIN : GENERAL_LIMIT_PER_MIN),
          "X-RateLimit-Remaining": "0",
          ...CORS_HEADERS,
        },
      });
    }
  }

  // Build upstream request with (possibly refreshed) token
  const headers = new Headers();
  headers.set('authorization', `Bearer ${activeToken}`);
  for (const key of ['content-type', 'accept', 'mcp-session-id', 'last-event-id']) {
    const val = request.headers.get(key);
    if (val) headers.set(key, val);
  }

  // p220: detect tools/list so we can post-process the response to strip
  // the non-MCP-spec `execution.taskSupport` field added by @modelcontextprotocol/sdk@1.29.0.
  // Stricter MCP clients (Perplexity) silently drop the entire tools array when
  // unknown top-level fields appear on each tool — symptom: "No tools to display"
  // despite tools/list returning 200 with all 299 tools. The field is Anthropic-
  // internal (Claude Managed Agents task scheduling hint) and not part of the
  // public MCP spec (https://spec.modelcontextprotocol.io). Strip universally so
  // every client sees a spec-compliant payload.
  const isToolsList = typeof reqBody === 'string' && /"method"\s*:\s*"tools\/list"/.test(reqBody);

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

    // p220 — tools/list spec-cleanup: buffer + strip `execution` from each tool
    // (works for both SSE-wrapped and plain JSON bodies; same regex either way
    // because the field's JSON serialization is constant).
    if (isToolsList) {
      const rawBody = await res.text();
      // Match optional leading/trailing comma + the constant execution object.
      // The SDK always emits this field with the exact taskSupport:"forbidden"
      // value, so a literal regex is safe (no parser cost).
      const cleanedBody = rawBody
        .replace(/,\s*"execution"\s*:\s*\{\s*"taskSupport"\s*:\s*"forbidden"\s*\}/g, '')
        .replace(/"execution"\s*:\s*\{\s*"taskSupport"\s*:\s*"forbidden"\s*\}\s*,?/g, '');
      const respHeadersOut = new Headers(respHeaders);
      respHeadersOut.delete('content-length'); // length changed after strip
      await kvLog("mcp-upstream-tools-list", {
        status: res.status,
        contentType,
        rawLen: rawBody.length,
        cleanedLen: cleanedBody.length,
        stripped: rawBody.length - cleanedBody.length,
      });
      return new Response(cleanedBody, {
        status: res.status,
        headers: respHeadersOut,
      });
    }

    // For SSE responses (non tools/list), stream through without buffering
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
