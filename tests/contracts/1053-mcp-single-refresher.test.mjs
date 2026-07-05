/**
 * #1053 — MCP re-login every ~1h: single-refresher model.
 *
 * Root cause (confirmed by code read, 2026-07-05): TWO refreshers competed over
 * the SAME rotating Supabase refresh token —
 *   1. the Worker proxies (src/pages/mcp.ts + src/pages/mcp/semantic.ts) did a
 *      server-side auto-refresh on every expiring request, rotating R→R' and
 *      re-storing R' in KV, but never handing R' back to Claude; and
 *   2. Claude itself refreshed proactively ~5 min before expiry with its OWN copy.
 * Under Supabase refresh-token rotation (default ON) whoever refreshed first
 * invalidated the other's token. When the proxy won, Claude's next refresh 400'd
 * ("already used") → /oauth/token returned invalid_grant → Claude dropped to a
 * full re-login, each ~1h token cycle. The #580 KV re-store could not fix it: it
 * kept the SERVER copy fresh, but there is no channel to push R' back to Claude.
 *
 * Fix: remove the proxy-side refresh entirely. Claude is the sole refresher (it
 * refreshes reactively on 401 + proactively before expiry, per the official
 * connector behaviour), through /oauth/token — which keeps the KV mcp_refresh:{sub}
 * copy in sync on the single rotation chain.
 *
 * This test LOCKS that model: the proxies must not refresh server-side, and
 * /oauth/token must keep implementing the refresh_token grant.
 *
 * Cross-ref: #1053, #234, #580, src/lib/mcp-refresh.ts (helpers retained but
 * deprecated for proxy use).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (rel) => readFileSync(resolve(ROOT, rel), 'utf8');

const PROXIES = ['src/pages/mcp.ts', 'src/pages/mcp/semantic.ts'];

test('#1053: neither proxy performs a server-side token refresh', () => {
  for (const rel of PROXIES) {
    const src = read(rel);
    assert.doesNotMatch(src, /tryAutoRefresh\s*\(/, `${rel} must not call tryAutoRefresh (single-refresher model, #1053)`);
    assert.doesNotMatch(src, /isExpiringSoon\s*\(/, `${rel} must not gate on isExpiringSoon (no proxy refresh, #1053)`);
    assert.doesNotMatch(src, /grant_type=refresh_token/, `${rel} must not hit the Supabase refresh grant directly`);
  }
});

test('#1053: proxies still forward the bearer as-is (no token mutation before upstream)', () => {
  for (const rel of PROXIES) {
    const src = read(rel);
    // The forwarded token comes straight from the Authorization header, unmodified.
    assert.match(src, /const activeToken = authHeader\.replace\(\/\^Bearer\\s\+\/i, ''\);/, `${rel} must forward the bearer verbatim`);
    assert.doesNotMatch(src, /activeToken\s*=\s*newToken/, `${rel} must not reassign the token from a refresh`);
  }
});

test('#1053: /oauth/token remains the sole server-side refresher (refresh_token grant intact)', () => {
  const src = read('src/pages/oauth/token.ts');
  assert.match(src, /grant_type === 'refresh_token'/, 'token.ts must still handle the refresh_token grant');
  assert.match(src, /grant_type=refresh_token/, 'token.ts must still call the Supabase refresh endpoint');
  // It keeps the KV copy in sync on rotation so the single chain stays consistent.
  assert.match(src, /mcp_refresh:\$\{refreshPayload\.sub\}/, 'token.ts must re-store the rotated refresh token in KV');
});

test('#1053: rate limiting still keys off the decoded JWT sub in both proxies', () => {
  // The decode stayed for rate limiting only; guard it did not get removed by accident.
  for (const rel of PROXIES) {
    const src = read(rel);
    assert.match(src, /const payload = decodeJwtPayload\(activeToken\);/, `${rel} must still decode the JWT for rate-limit keying`);
    assert.match(src, /checkRateLimit\(kv, payload\.sub/, `${rel} must still rate-limit per member`);
  }
});
