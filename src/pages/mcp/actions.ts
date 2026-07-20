// #1377 — /actions overflow MCP Worker proxy
// Mirrors src/pages/mcp/semantic.ts but forwards to the EF /actions endpoint instead of /semantic.
// Rationale: the Claude connector caps ONE connector at 256 tools (alphabetical), so /mcp (~339)
// silently drops its write/action tail. /actions re-exposes that tail as a second connector.
// All shared logic (OAuth header gate, rate limiting, tools/list spec strip, CORS, SSE pass-through)
// preserved. Unlike /semantic this surface IS write-heavy, but checkRateLimit already classifies
// destructive tools by name internally, so no change is needed there.
// Future refactor (#280 follow-up): extract shared proxy logic into src/lib/mcp-proxy.ts.

import type { APIRoute } from 'astro';
import { env } from 'cloudflare:workers';
import {
  checkRateLimit,
  extractToolName,
  GENERAL_LIMIT_PER_MIN,
  DESTRUCTIVE_LIMIT_PER_MIN,
} from '../../lib/mcp-rate-limit';
// #1053 — single-refresher model: this proxy no longer refreshes server-side (see
// src/pages/mcp.ts for the rationale — it raced Claude's own refresh over the same
// rotating Supabase refresh token → forced re-login each ~1h). Claude refreshes via
// /oauth/token. decodeJwtPayload is imported only to read `sub` for the rate limit.
import { decodeJwtPayload } from '../../lib/mcp-refresh';
import { CANONICAL_ORIGIN } from '../../lib/canonical';

async function kvLog(_endpoint: string, _data: any) {
  // No-op: KV debug logs disabled to protect free tier write limit (1k/day).
}

const UPSTREAM = 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/actions';
const BASE = CANONICAL_ORIGIN;

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type, Accept, Mcp-Session-Id',
  'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
  'Access-Control-Expose-Headers': 'Mcp-Session-Id',
};

export const ALL: APIRoute = async ({ request }) => {
  const reqBody = request.method === 'POST' ? await request.clone().text() : null;
  await kvLog("mcp-actions-request", {
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
        'WWW-Authenticate': `Bearer resource_metadata="${BASE}/.well-known/oauth-protected-resource/mcp/actions"`,
        ...CORS_HEADERS,
      },
    });
  }

  // #1053 — NO server-side refresh (see mcp.ts). Forward the bearer as-is; Claude
  // is the sole refresher via /oauth/token. `payload` is decoded only to key the
  // per-member rate limit below.
  const activeToken = authHeader.replace(/^Bearer\s+/i, '');
  const kv = (env as any).SESSION;
  const payload = decodeJwtPayload(activeToken);

  // ADR-0018 W2: rate limit per-member. This surface is write-heavy, so the destructive
  // cap matters — checkRateLimit classifies the tool by name internally.
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
      await kvLog("mcp-actions-upstream-tools-list", {
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
      await kvLog("mcp-actions-upstream", {
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
    await kvLog("mcp-actions-upstream", {
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
    await kvLog("mcp-actions-error", { error: e.message, stack: e.stack?.substring(0, 300) });
    return new Response(JSON.stringify({ error: 'proxy_error', detail: e.message }), {
      status: 502,
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }
};
