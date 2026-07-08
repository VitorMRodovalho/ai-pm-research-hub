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
 * Fix (#1053): remove the proxy-side refresh entirely — Claude became the sole
 * refresher through /oauth/token. #1210 finished the job: even that endpoint was
 * retired, because the consent flow still COPIED the browser session's refresh
 * token to Claude (browser↔Claude = the same two-holders collision). Token
 * issuance now lives in Supabase's native OAuth 2.1 server with client-scoped
 * sessions; the Worker performs zero token work.
 *
 * This test LOCKS both layers: the proxies must not refresh server-side, and
 * the Worker token route must never grow grant handling back.
 *
 * Cross-ref: #1053, #1210, #234, #580, src/lib/mcp-refresh.ts (helpers retained
 * for reference, unit-tested, unused by routes).
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

test('#1053 → #1210: the Worker performs NO token issuance or refresh at all', () => {
  // #1210 evolved the single-refresher model to its terminal form: token issuance
  // moved to Supabase Auth's native OAuth 2.1 server (client-scoped sessions), so
  // the browser↔Claude collision over one shared rotating refresh token is gone
  // by design. The Worker token route is a retired stub — it must never again
  // exchange codes, refresh tokens, or touch the KV refresh copy.
  const src = read('src/pages/oauth/token.ts');
  assert.doesNotMatch(src, /grant_type === 'refresh_token'/, 'token.ts must not implement the refresh grant (#1210)');
  assert.doesNotMatch(src, /grant_type=refresh_token/, 'token.ts must not call the Supabase session-refresh endpoint (#1210)');
  assert.doesNotMatch(src, /mcp_refresh/, 'token.ts must not touch the KV refresh copy (#1210)');
  assert.match(src, /invalid_grant/, 'stub must answer a clean OAuth invalid_grant so stale clients re-auth');
});

test('#1053: rate limiting still keys off the decoded JWT sub in both proxies', () => {
  // The decode stayed for rate limiting only; guard it did not get removed by accident.
  for (const rel of PROXIES) {
    const src = read(rel);
    assert.match(src, /const payload = decodeJwtPayload\(activeToken\);/, `${rel} must still decode the JWT for rate-limit keying`);
    assert.match(src, /checkRateLimit\(kv, payload\.sub/, `${rel} must still rate-limit per member`);
  }
});
