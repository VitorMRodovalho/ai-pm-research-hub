import type { APIRoute } from 'astro';

/**
 * OAuth 2.1 Authorization endpoint.
 * Redirects to consent page with all OAuth params encoded in the URL.
 */
export const GET: APIRoute = async ({ request }) => {
  const url = new URL(request.url);
  const state = url.searchParams.get('state') || '';
  const redirectUri = url.searchParams.get('redirect_uri') || '';
  const codeChallenge = url.searchParams.get('code_challenge') || '';
  const codeChallengeMethod = url.searchParams.get('code_challenge_method') || 'S256';
  const clientId = url.searchParams.get('client_id') || '';

  if (!redirectUri || !codeChallenge) {
    return new Response(JSON.stringify({ error: 'invalid_request', error_description: 'redirect_uri and code_challenge required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Encode OAuth params as base64 for the consent page
  const oauthData = btoa(JSON.stringify({
    client_id: clientId,
    redirect_uri: redirectUri,
    code_challenge: codeChallenge,
    code_challenge_method: codeChallengeMethod,
    state,
  }));

  const consentUrl = new URL('/oauth/consent', url.origin);
  consentUrl.searchParams.set('mcp_state', state);
  consentUrl.searchParams.set('oauth_data', oauthData);

  return new Response(null, {
    status: 302,
    headers: { 'Location': consentUrl.toString() },
  });
};
