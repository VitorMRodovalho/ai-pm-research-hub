import type { APIRoute } from 'astro';

const projectRef = 'ldrfrvwhxsmgaabwmaik';

export const GET: APIRoute = () => {
  return new Response(JSON.stringify({
    issuer: `https://${projectRef}.supabase.co/auth/v1`,
    authorization_endpoint: `https://${projectRef}.supabase.co/auth/v1/oauth/authorize`,
    token_endpoint: `https://${projectRef}.supabase.co/auth/v1/oauth/token`,
    registration_endpoint: `https://${projectRef}.supabase.co/auth/v1/oauth/register`,
    response_types_supported: ['code'],
    grant_types_supported: ['authorization_code', 'refresh_token'],
    code_challenge_methods_supported: ['S256'],
    token_endpoint_auth_methods_supported: ['none'],
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
};
