/**
 * Contract: #1051 — self-service revocation of MCP client access from /profile.
 *
 * Origin: security audit 2026-07-02 (item #4, "JWT na URL / token vivo pós-logout").
 * The gap: an MCP client (Claude) that completed the OAuth flow keeps a Supabase
 * refresh token; signing out of the SITE does not revoke it, so the AI host stays
 * connected. There was no "disconnect my MCP clients" control.
 *
 * The effective cut (post-#1053 reality — the invariant this test guards):
 *   - Nothing reads KV `mcp_refresh:{sub}` anymore (the proxy refresh was removed in
 *     #1053; only the deprecated `tryAutoRefresh` reads it). So `kv.delete` would
 *     revoke NOTHING — the client holds its own copy. This test asserts the action
 *     does NOT depend on a KV delete for the cut.
 *   - The refresh token the MCP client holds was minted from a normal GoTrue session
 *     at /oauth/consent login, so it lives in the user's session pool. A GLOBAL
 *     signout revokes ALL of the user's refresh tokens → the MCP client can no longer
 *     mint access tokens → dies within <= 1h (access-token TTL). This is the cut.
 *   - Global scope also ends the browser session (by design, owner decision
 *     2026-07-05): the copy warns the user + the handler redirects to re-auth.
 *
 * Offline-only (static source + dictionary assertions); no DB gating.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');

const PROFILE = read('src/pages/profile.astro');
const PT = read('src/i18n/pt-BR.ts');
const EN = read('src/i18n/en-US.ts');
const ES = read('src/i18n/es-LATAM.ts');

const NEW_KEYS = [
  'profile.mcpSessionsTitle',
  'profile.mcpSessionsDesc',
  'profile.mcpDisconnectBtn',
  'profile.mcpDisconnectWarn',
  'profile.mcpDisconnectConfirm',
  'profile.toastMcpDisconnected',
  'profile.toastMcpDisconnectError',
];

// ── i18n: every new key exists in ALL 3 dictionaries (GC-097 i18n parity) ────────
test('i18n: all #1051 keys exist in pt-BR / en-US / es-LATAM', () => {
  for (const key of NEW_KEYS) {
    assert.ok(PT.includes(`'${key}'`), `pt-BR missing ${key}`);
    assert.ok(EN.includes(`'${key}'`), `en-US missing ${key}`);
    assert.ok(ES.includes(`'${key}'`), `es-LATAM missing ${key}`);
  }
});

test('i18n: keys are wired into the PROFILE_I18N frontmatter object', () => {
  assert.match(PROFILE, /mcpDisconnectConfirm:\s*t\('profile\.mcpDisconnectConfirm', lang\)/);
  assert.match(PROFILE, /toastMcpDisconnected:\s*t\('profile\.toastMcpDisconnected', lang\)/);
});

// ── UI: the card + button exist and are discoverable ─────────────────────────────
test('profile: MCP sessions card + disconnect action button present', () => {
  assert.match(PROFILE, /PROFILE_I18N\.mcpSessionsTitle/);
  assert.match(PROFILE, /data-action="disconnect-mcp"/);
  assert.match(PROFILE, /PROFILE_I18N\.mcpDisconnectBtn/);
});

// ── Handler wiring: data-action dispatches to the handler ─────────────────────────
test('profile: disconnect-mcp action dispatches to disconnectMcpClients()', () => {
  assert.match(PROFILE, /case 'disconnect-mcp':\s*\n\s*disconnectMcpClients\(\);/);
});

// ── The invariant: the cut is a GLOBAL signout, not a KV delete ──────────────────
test('profile: disconnect uses signOut with scope global (the effective revocation)', () => {
  const fn = PROFILE.slice(PROFILE.indexOf('async function disconnectMcpClients'));
  const body = fn.slice(0, fn.indexOf('async function exportMyData'));
  assert.ok(body, 'disconnectMcpClients() function found before exportMyData');
  assert.match(body, /signOut\(\{\s*scope:\s*['"]global['"]\s*\}\)/);
  // must confirm first (global signout also ends the browser session — destructive)
  assert.match(body, /PROFILE_I18N\.mcpDisconnectConfirm/);
  // must redirect to re-auth after the browser session is gone
  assert.match(body, /location\.href\s*=/);
});

test('profile: disconnect handler does NOT rely on a KV mcp_refresh delete (dead post-#1053)', () => {
  const fn = PROFILE.slice(PROFILE.indexOf('async function disconnectMcpClients'));
  const body = fn.slice(0, fn.indexOf('async function exportMyData'));
  assert.ok(!/mcp_refresh/.test(body), 'handler must not depend on KV mcp_refresh — it is unread post-#1053');
});

// ── UX honesty: the warning copy tells the user the browser session ends too ─────
test('i18n: pt-BR warning discloses that ALL sessions (incl. browser) end', () => {
  const warnLine = PT.split('\n').find((l) => l.includes("'profile.mcpDisconnectWarn'")) || '';
  assert.match(warnLine, /navegador/i, 'warning must mention the browser session ends');
});
