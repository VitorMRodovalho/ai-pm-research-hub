import type { APIRoute } from 'astro';
import { env } from 'cloudflare:workers';

async function kvLog(endpoint: string, data: any) {
  try { const kv = (env as any).SESSION; if (kv) await kv.put(`debug:${endpoint}:${Date.now()}`, JSON.stringify({ timestamp: new Date().toISOString(), endpoint, ...data }), { expirationTtl: 3600 }); } catch {}
}

const UPSTREAM = 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/mcp';
const BASE = 'https://nucleoia.vitormr.dev';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type, Accept, Mcp-Session-Id',
  'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
  'Access-Control-Expose-Headers': 'Mcp-Session-Id',
};

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

  // Build upstream request
  const headers = new Headers();
  for (const key of ['authorization', 'content-type', 'accept', 'mcp-session-id', 'last-event-id']) {
    const val = request.headers.get(key);
    if (val) headers.set(key, val);
  }

  try {
    const upstream = new Request(UPSTREAM, {
      method: request.method,
      headers,
      body: request.method !== 'GET' && request.method !== 'HEAD' ? request.body : null,
      // @ts-ignore — duplex needed for streaming body in Workers
      duplex: 'half',
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
