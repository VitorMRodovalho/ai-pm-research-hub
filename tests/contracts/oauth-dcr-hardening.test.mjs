/**
 * OAuth DCR + Protected-Resource hardening (systemic audit 2026-07-20).
 *
 * Locks the two fixes that came out of the end-to-end MCP OAuth audit
 * (docs/audit/2026-07-20_MCP_OAUTH_SYSTEMIC_AUDIT.md):
 *
 *  FM-01 — /oauth/register must NEVER hand back a client_id GoTrue would reject,
 *          must NOT echo unregistered redirect_uris on the shared-client fallback,
 *          and must 400 when a non-empty redirect_uris request sanitizes to nothing.
 *          (Root of the Leticia class: a cached non-UUID client_id → GoTrue authorize
 *          400 "invalid client_id format", unrescuable server-side.)
 *
 *  PPX-3 — RFC 9728 protected-resource metadata must be path-aware so /mcp/semantic
 *          and /mcp/actions advertise their own resource (not a hardcoded /mcp), and
 *          each proxy's WWW-Authenticate must point at its path-scoped metadata.
 *
 * Static source assertions (same offline-safe style as 1210-mcp-native-oauth.test.mjs)
 * so the gate runs in CI without secrets or network.
 *
 * Cross-ref: docs/audit/2026-07-20_MCP_OAUTH_SYSTEMIC_AUDIT.md, memory
 * reference-mcp-oauth-cached-nonuuid-client-id-class, #1428.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (rel) => readFileSync(resolve(ROOT, rel), 'utf8');

const REGISTER = read('src/pages/oauth/register.ts');
const PR_PATH_ROUTE = 'src/pages/.well-known/oauth-protected-resource/[...path].ts';

// ── FM-01: register must only return a UUID client_id ────────────────────────
test('FM-01: register.ts guards the true-DCR client_id against non-UUID (UUID_RE)', () => {
  assert.match(REGISTER, /UUID_RE\s*=\s*\/\^\[0-9a-f\]\{8\}-/i,
    'a UUID regex must exist to validate the minted client_id');
  assert.match(REGISTER, /UUID_RE\.test\(\s*created\.client_id\s*\)/,
    'the true-DCR success path must gate on UUID_RE.test(created.client_id) before returning it');
});

test('FM-01: register fallback does NOT echo the caller\'s requested redirect_uris', () => {
  // The misleading pre-fix line was `redirect_uris: body.redirect_uris || []`.
  assert.doesNotMatch(REGISTER, /redirect_uris:\s*body\.redirect_uris\s*\|\|/,
    'fallback must not echo body.redirect_uris (reads as "your callback is live" when it is not registered)');
  assert.match(REGISTER, /redirect_uris:\s*\[\]/,
    'fallback must return an empty redirect_uris array');
});

test('FM-01: register 400s when a non-empty redirect_uris request sanitizes to nothing', () => {
  assert.match(REGISTER, /invalid_redirect_uri/,
    'must emit an RFC 7591 invalid_redirect_uri error');
  assert.match(
    REGISTER,
    /body\.redirect_uris\.length\s*>\s*0\s*&&\s*redirectUris\.length\s*===\s*0/,
    'the 400 must be gated strictly on "non-empty request sanitized to empty" (not on the no-service-role path)'
  );
});

// ── PPX-3 / FM-04: path-aware protected-resource metadata ────────────────────
test('PPX-3: path-suffixed protected-resource route exists (no more 404 on /mcp/semantic)', () => {
  assert.ok(existsSync(resolve(ROOT, PR_PATH_ROUTE)),
    `${PR_PATH_ROUTE} must exist so RFC 9728 path-suffixed discovery resolves`);
});

test('PPX-3: path-scoped metadata reflects the connected surface, gated to known surfaces', () => {
  const src = read(PR_PATH_ROUTE);
  assert.match(src, /resource:\s*`\$\{origin\}\/\$\{path\}`/,
    'resource must be origin + the connected path (not a hardcoded /mcp)');
  assert.match(src, /KNOWN_SURFACES/,
    'must restrict to known MCP surfaces so it is not an open metadata reflector');
  assert.match(src, /["']mcp\/semantic["']/, 'must know the /mcp/semantic surface');
  assert.match(src, /["']mcp\/actions["']/, 'must know the /mcp/actions surface');
});

test('PPX-3: each MCP proxy points WWW-Authenticate at its OWN path-scoped metadata', () => {
  const cases = [
    ['src/pages/mcp.ts', 'oauth-protected-resource/mcp"'],
    ['src/pages/mcp/semantic.ts', 'oauth-protected-resource/mcp/semantic"'],
    ['src/pages/mcp/actions.ts', 'oauth-protected-resource/mcp/actions"'],
  ];
  for (const [rel, needle] of cases) {
    const src = read(rel);
    assert.ok(
      src.includes(needle),
      `${rel} WWW-Authenticate must reference ${needle} so the advertised resource matches the connector`
    );
  }
});
