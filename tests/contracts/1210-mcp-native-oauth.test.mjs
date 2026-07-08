/**
 * #1210 — MCP OAuth migrated to Supabase Auth's NATIVE OAuth 2.1 server.
 *
 * Root cause of the persistent ~1h re-login (post-#1053): the hand-rolled flow
 * handed the MCP client a COPY of the BROWSER session's refresh token
 * (/oauth/consent posted session tokens to /oauth/exchange). Browser and
 * connector then raced each other over ONE rotating refresh chain — whoever
 * refreshed second got `refresh_token_already_used` → invalid_grant → re-auth.
 * Confirmed live 2026-07-08 in auth logs (both failure directions within 41
 * minutes; request_ids in issue #1210).
 *
 * Fix: token issuance moved to GoTrue's native OAuth 2.1 server, which mints a
 * DEDICATED session per OAuth client. The browser session is only the approver
 * identity on the consent page — never copied to the client.
 *
 * This test LOCKS the migrated shape:
 *   1. AS metadata points authorize/token at GoTrue (`/auth/v1/oauth/*`),
 *      registration at our shim, and advertises only GoTrue-supported scopes.
 *   2. Discovery routes are origin-aware (alias-ready, #1210 scope 2).
 *   3. consent.astro drives the authorization_id flow via auth.oauth.* and
 *      NEVER posts the browser session's tokens anywhere.
 *   4. exchange.ts is GONE; token.ts is a stub that issues nothing.
 *   5. authorize.ts only forwards to the native endpoint (compat passthrough).
 *
 * Cross-ref: #1210, #1053 (proxy-refresher episode), #1051 (per-client
 * revocation — native grants close it), .claude/rules/mcp.md.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (rel) => readFileSync(resolve(ROOT, rel), 'utf8');

const AS_META = read('src/pages/.well-known/oauth-authorization-server.ts');
const PR_META = read('src/pages/.well-known/oauth-protected-resource.ts');
const CONSENT = read('src/pages/oauth/consent.astro');
const AUTHORIZE = read('src/pages/oauth/authorize.ts');
const TOKEN = read('src/pages/oauth/token.ts');

test('#1210: AS metadata delegates authorize + token to the native GoTrue OAuth server', () => {
  assert.match(AS_META, /authorization_endpoint: `\$\{supabaseUrl\}\/auth\/v1\/oauth\/authorize`/);
  assert.match(AS_META, /token_endpoint: `\$\{supabaseUrl\}\/auth\/v1\/oauth\/token`/);
  // Registration stays OUR shim (fixed pre-registered client_id — no open DCR).
  assert.match(AS_META, /registration_endpoint: `\$\{origin\}\/oauth\/register`/);
  // GoTrue rejects unknown scopes — the old custom ones must not be advertised.
  assert.doesNotMatch(AS_META, /mcp:tools|offline_access/);
});

test('#1210: discovery routes are origin-aware (no CANONICAL_ORIGIN pin — alias-ready)', () => {
  for (const [rel, src] of [['oauth-authorization-server.ts', AS_META], ['oauth-protected-resource.ts', PR_META]]) {
    assert.doesNotMatch(src, /CANONICAL_ORIGIN/, `${rel} must derive origin from the request`);
    assert.match(src, /url\.origin/, `${rel} must use the request origin`);
  }
});

test('#1210: consent drives the authorization_id flow via auth.oauth.*', () => {
  assert.match(CONSENT, /authorization_id/);
  assert.match(CONSENT, /supabase\.auth\.oauth\.getAuthorizationDetails\(/);
  assert.match(CONSENT, /supabase\.auth\.oauth\.approveAuthorization\(/);
  assert.match(CONSENT, /supabase\.auth\.oauth\.denyAuthorization\(/);
});

test('#1210: consent NEVER ships the browser session tokens to the client (the collision root)', () => {
  assert.doesNotMatch(CONSENT, /oauth\/exchange/, 'exchange call must be gone');
  assert.doesNotMatch(CONSENT, /refresh_token:\s*session\.refresh_token/, 'browser refresh token must never leave the page');
  assert.doesNotMatch(CONSENT, /access_token:\s*session\.access_token/, 'browser access token must never be posted');
});

test('#1210: exchange.ts removed; token.ts issues nothing', () => {
  assert.equal(existsSync(resolve(ROOT, 'src/pages/oauth/exchange.ts')), false, 'exchange.ts must not exist');
  assert.doesNotMatch(TOKEN, /access_token/, 'stub must not return tokens');
  assert.doesNotMatch(TOKEN, /mcp_code/, 'stub must not look up authorization codes');
});

test('#1210: authorize.ts is a passthrough to the native endpoint, sanitizing legacy scopes', () => {
  assert.match(AUTHORIZE, /\/auth\/v1\/oauth\/authorize/);
  assert.match(AUTHORIZE, /GOTRUE_SCOPES/);
  assert.doesNotMatch(AUTHORIZE, /mcp_state|oauth_data/, 'legacy consent params must be gone');
});
