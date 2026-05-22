/**
 * OAuth 2.1 redirect_uri allowlist for the MCP server.
 *
 * DCR (/oauth/register) is stateless and returns a fixed client_id,
 * so we cannot validate redirect_uri per-client. Instead, we enforce
 * a static allowlist of trusted root hosts and custom URI schemes.
 *
 * Why this matters:
 *   Without validation, an attacker could initiate an OAuth flow with
 *   redirect_uri=https://attacker.example/cb, capture the auth code,
 *   and exchange it for a valid Supabase JWT (account takeover).
 *
 * Matching strategy (p220 — host suffix model):
 *   - HTTPS redirects: parse URL, accept if host === root OR host endsWith
 *     '.' + root for any root in TRUSTED_ROOT_HOSTS. Subdomain coverage is
 *     intentional: MCP providers commonly route callbacks via product-
 *     specific subdomains (api.perplexity.ai, comet.perplexity.ai,
 *     app.claude.ai, etc.) and the previous prefix-string approach
 *     silently blocked them — Perplexity rotated to api.perplexity.ai
 *     and the allowlist still listed only perplexity.ai + www.perplexity.ai,
 *     so connector tools/list went silent for the user.
 *   - Custom schemes (cursor://, vscode://): accept if scheme starts URI.
 *   - Localhost: accept any http://localhost:PORT or http://127.0.0.1:PORT
 *     for local dev.
 *   - All other inputs REJECTED.
 *
 * Maintenance:
 *   - Add new root hosts only after confirming they are legitimate MCP
 *     providers (Anthropic-published or vendor-published MCP support).
 *   - Subdomain trust is implicit: trusting `perplexity.ai` trusts
 *     `*.perplexity.ai`. This relies on the provider's DNS hygiene —
 *     subdomain takeover at a major MCP vendor would be a wider incident.
 */

const TRUSTED_ROOT_HOSTS: readonly string[] = [
  'claude.ai',
  'chatgpt.com',
  'openai.com',
  'perplexity.ai',
  'cursor.com',
  'manus.im',
  'vitormr.dev',
];

const CUSTOM_SCHEMES: readonly string[] = [
  'cursor://',
  'vscode://',
  'vscode-insiders://',
  'code-oss://',
];

const LOCALHOST_HOSTS: readonly string[] = [
  'localhost',
  '127.0.0.1',
];

function matchesTrustedRoot(host: string): boolean {
  const lower = host.toLowerCase();
  for (const root of TRUSTED_ROOT_HOSTS) {
    if (lower === root || lower.endsWith('.' + root)) return true;
  }
  return false;
}

export function isAllowedRedirectUri(uri: string | undefined | null): boolean {
  if (!uri || typeof uri !== 'string') return false;

  for (const scheme of CUSTOM_SCHEMES) {
    if (uri.startsWith(scheme)) return true;
  }

  let parsed: URL;
  try {
    parsed = new URL(uri);
  } catch {
    return false;
  }

  if (parsed.protocol === 'http:' && LOCALHOST_HOSTS.includes(parsed.hostname)) {
    return true;
  }

  if (parsed.protocol !== 'https:') return false;

  return matchesTrustedRoot(parsed.hostname);
}
