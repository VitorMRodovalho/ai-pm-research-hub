import type { APIRoute } from 'astro';

const UPSTREAM = 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/mcp';
const BASE = 'https://nucleoia.vitormr.dev';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type, Accept, MCP-Session-Id',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
};

export const ALL: APIRoute = async ({ request }) => {
  // CORS preflight — allow without auth
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  // RFC 9728: if no Authorization header, return 401 to trigger OAuth flow
  // Claude.ai only initiates OAuth when it receives 401 + WWW-Authenticate
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

  const headers = new Headers();
  // Forward auth and content headers
  for (const key of ['authorization', 'content-type', 'accept', 'mcp-session-id']) {
    const val = request.headers.get(key);
    if (val) headers.set(key, val);
  }

  const upstream = new Request(UPSTREAM, {
    method: request.method,
    headers,
    body: request.method !== 'GET' && request.method !== 'HEAD' ? request.body : null,
    // @ts-ignore — duplex needed for streaming body in Workers
    duplex: 'half',
  });

  const res = await fetch(upstream);

  // Forward response with CORS
  const respHeaders = new Headers(res.headers);
  for (const [k, v] of Object.entries(CORS_HEADERS)) respHeaders.set(k, v);

  return new Response(res.body, {
    status: res.status,
    headers: respHeaders,
  });
};
