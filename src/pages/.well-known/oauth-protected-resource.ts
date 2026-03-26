import type { APIRoute } from 'astro';

/**
 * RFC 9728 — OAuth Protected Resource Metadata
 * Claude.ai fetches this to discover which authorization server protects the MCP endpoint.
 */

const BASE = 'https://platform.ai-pm-research-hub.workers.dev';

export const GET: APIRoute = () => {
  return new Response(JSON.stringify({
    resource: `${BASE}/mcp`,
    authorization_servers: [BASE],
    scopes_supported: ['mcp:tools'],
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
};
