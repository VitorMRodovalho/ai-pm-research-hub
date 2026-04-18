/**
 * OAuth 2.1 redirect_uri allowlist for the MCP server.
 *
 * DCR (/oauth/register) is stateless and returns a fixed client_id,
 * so we cannot validate redirect_uri per-client. Instead, we enforce
 * a static allowlist of MCP host prefixes and custom URI schemes.
 *
 * Why this matters:
 *   Without validation, an attacker could initiate an OAuth flow with
 *   redirect_uri=https://attacker.example/cb, capture the auth code,
 *   and exchange it for a valid Supabase JWT (account takeover).
 *
 * Maintenance:
 *   - Add new hosts here only after confirming they are legitimate
 *     MCP clients (not arbitrary third parties).
 *   - HTTPS entries match URL prefixes (scheme + host + trailing slash).
 *   - Custom schemes match the scheme itself (e.g., "cursor:").
 *   - localhost is allowed over http for local development only.
 */

const HTTPS_PREFIXES: readonly string[] = [
  'https://claude.ai/',
  'https://app.claude.ai/',
  'https://chatgpt.com/',
  'https://www.chatgpt.com/',
  'https://openai.com/',
  'https://platform.openai.com/',
  'https://perplexity.ai/',
  'https://www.perplexity.ai/',
  'https://cursor.com/',
  'https://www.cursor.com/',
  'https://manus.im/',
  'https://www.manus.im/',
  'https://nucleoia.vitormr.dev/',
];

const CUSTOM_SCHEMES: readonly string[] = [
  'cursor://',
  'vscode://',
  'vscode-insiders://',
  'code-oss://',
];

const LOCALHOST_PREFIXES: readonly string[] = [
  'http://localhost:',
  'http://127.0.0.1:',
];

export function isAllowedRedirectUri(uri: string | undefined | null): boolean {
  if (!uri || typeof uri !== 'string') return false;

  for (const scheme of CUSTOM_SCHEMES) {
    if (uri.startsWith(scheme)) return true;
  }

  for (const prefix of HTTPS_PREFIXES) {
    if (uri.startsWith(prefix)) return true;
  }

  for (const prefix of LOCALHOST_PREFIXES) {
    if (uri.startsWith(prefix)) return true;
  }

  return false;
}
