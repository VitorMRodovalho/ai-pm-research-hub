import type { APIRoute } from 'astro';

const BASE = 'https://platform.ai-pm-research-hub.workers.dev';

export const GET: APIRoute = () => {
  return new Response(JSON.stringify({
    issuer: BASE,
    authorization_endpoint: `${BASE}/oauth/authorize`,
    token_endpoint: `${BASE}/oauth/token`,
    registration_endpoint: `${BASE}/oauth/register`,
    response_types_supported: ['code'],
    grant_types_supported: ['authorization_code', 'refresh_token'],
    code_challenge_methods_supported: ['S256'],
    token_endpoint_auth_methods_supported: ['none'],
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
};
