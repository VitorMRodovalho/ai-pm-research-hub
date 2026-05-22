// p222 #280 alpha — Semantic MCP Gateway Worker proxy
// Mirrors src/pages/mcp.ts but forwards to the EF /semantic endpoint instead of /mcp.
// All shared logic (OAuth header gate, auto-refresh, rate limiting, tools/list spec strip,
// CORS, SSE pass-through) preserved. SPEC-280.B Option A; bridge-first per #280 PM decision.
// Future refactor (#280 follow-up): extract shared proxy logic into src/lib/mcp-proxy.ts.

import type { APIRoute } from 'astro';
import { env } from 'cloudflare:workers';
import {
  checkRateLimit,
  extractToolName,
  GENERAL_LIMIT_PER_MIN,
  DESTRUCTIVE_LIMIT_PER_MIN,
} from '../../lib/mcp-rate-limit';

async function kvLog(_endpoint: string, _data: any) {
  // No-op: KV debug logs disabled to protect free tier write limit (1k/day).
}

const UPSTREAM = 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/semantic';
const BASE = 'https://nucleoia.vitormr.dev';
const SUPABASE_URL = 'https://ldrfrvwhxsmgaabwmaik.supabase.co';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type, Accept, Mcp-Session-Id',
  'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
  'Access-Control-Expose-Headers': 'Mcp-Session-Id',
};

function decodeJwtPayload(token: string): { sub?: string; exp?: number } | null {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    return JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
  } catch { return null; }
}

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
    await kv.delete(`mcp_refresh:${sub}`);
    return null;
  }
  const data = await res.json();
  if (!data.access_token) {
    await kv.delete(`mcp_refresh:${sub}`);
    return null;
  }

  if (data.refresh_token) {
    await kv.put(`mcp_refresh:${sub}`, data.refresh_token, { expirationTtl: 2592000 });
  }

  return data.access_token;
}

export const ALL: APIRoute = async ({ request }) => {
  const reqBody = request.method === 'POST' ? await request.clone().text() : null;
  await kvLog("mcp-semantic-request", {
    method: request.method,
    hasAuth: !!request.headers.get("authorization"),
    contentType: request.headers.get("content-type"),
    accept: request.headers.get("accept"),
    mcpSessionId: request.headers.get("mcp-session-id"),
    userAgent: request.headers.get("user-agent")?.substring(0, 80),
    bodyPreview: reqBody?.substring(0, 300),
  });

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

  let activeToken = authHeader.replace(/^Bearer\s+/i, '');
  const kv = (env as any).SESSION;
  const payload = decodeJwtPayload(activeToken);

  if (kv && payload?.sub && payload?.exp) {
    const now = Math.floor(Date.now() / 1000);
    if (payload.exp - 300 < now) {
      await kvLog("mcp-semantic-auto-refresh-attempt", { sub: payload.sub, exp: payload.exp, now });
      const newToken = await tryAutoRefresh(payload.sub, kv);
      if (newToken) {
        activeToken = newToken;
        await kvLog("mcp-semantic-auto-refresh-ok", { sub: payload.sub });
      } else {
        await kvLog("mcp-semantic-auto-refresh-fail", { sub: payload.sub });
      }
    }
  }

  // ADR-0018 W2: rate limit per-member (semantic surface is read-only so destructive cap unused)
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

  const headers = new Headers();
  headers.set('authorization', `Bearer ${activeToken}`);
  for (const key of ['content-type', 'accept', 'mcp-session-id', 'last-event-id']) {
    const val = request.headers.get(key);
    if (val) headers.set(key, val);
  }

  // p220 — tools/list spec-cleanup (mirrors mcp.ts): strip non-MCP-spec
  // `execution.taskSupport` field emitted per-tool by @modelcontextprotocol/sdk@1.29.0.
  // Stricter MCP clients (Perplexity) silently drop tools array on unknown top-level fields.
  // Apply universally even for 3-tool semantic surface — same SDK, same field.
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

    const respHeaders = new Headers(res.headers);
    for (const [k, v] of Object.entries(CORS_HEADERS)) respHeaders.set(k, v);

    if (isToolsList) {
      const rawBody = await res.text();
      const cleanedBody = rawBody
        .replace(/,\s*"execution"\s*:\s*\{\s*"taskSupport"\s*:\s*"forbidden"\s*\}/g, '')
        .replace(/"execution"\s*:\s*\{\s*"taskSupport"\s*:\s*"forbidden"\s*\}\s*,?/g, '');
      const respHeadersOut = new Headers(respHeaders);
      respHeadersOut.delete('content-length');
      await kvLog("mcp-semantic-upstream-tools-list", {
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

    if (isSSE) {
      await kvLog("mcp-semantic-upstream", {
        status: res.status,
        contentType,
        streaming: true,
      });
      return new Response(res.body, {
        status: res.status,
        headers: respHeaders,
      });
    }

    const resBody = await res.text();
    await kvLog("mcp-semantic-upstream", {
      status: res.status,
      contentType,
      bodyLen: resBody.length,
      bodyPreview: resBody.substring(0, 500),
    });

    return new Response(resBody, {
      status: res.status,
      headers: respHeaders,
    });
  } catch (e: any) {
    await kvLog("mcp-semantic-error", { error: e.message, stack: e.stack?.substring(0, 300) });
    return new Response(JSON.stringify({ error: 'proxy_error', detail: e.message }), {
      status: 502,
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }
};
