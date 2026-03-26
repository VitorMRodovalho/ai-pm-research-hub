import type { APIRoute } from 'astro';

const UPSTREAM = 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/mcp';

export const ALL: APIRoute = async ({ request }) => {
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
  respHeaders.set('Access-Control-Allow-Origin', '*');
  respHeaders.set('Access-Control-Allow-Headers', 'Authorization, Content-Type, Accept, MCP-Session-Id');
  respHeaders.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');

  return new Response(res.body, {
    status: res.status,
    headers: respHeaders,
  });
};
