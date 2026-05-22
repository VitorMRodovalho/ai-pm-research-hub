/**
 * Forward-defense: OAuth redirect_uri allowlist host-suffix matching.
 *
 * Origin: p220 session (2026-05-22) — PM reported MCP tools disappearing
 * in Perplexity. Diagnosis: previous prefix-string allowlist covered only
 * perplexity.ai + www.perplexity.ai, blocking api.perplexity.ai (Perplexity's
 * actual MCP callback domain). Same vulnerability latent for app.claude.ai
 * (Claude.ai mobile), api.cursor.com, etc.
 *
 * Fix: switch to URL parser + host suffix match against TRUSTED_ROOT_HOSTS.
 * `host === root || host endsWith '.' + root` covers root + subdomains.
 *
 * Cross-ref:
 *   - src/lib/oauth-security.ts (the allowlist)
 *   - src/pages/oauth/exchange.ts, src/pages/oauth/token.ts (consumers)
 *   - p220 session log (MCP tools missing in Perplexity)
 *   - Original allowlist via prefix string match: ee14b998
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { isAllowedRedirectUri } from '../../src/lib/oauth-security.ts';

test('OAuth allowlist: root hosts accepted', () => {
  for (const uri of [
    'https://claude.ai/oauth/callback',
    'https://chatgpt.com/oauth/cb',
    'https://openai.com/oauth/callback',
    'https://perplexity.ai/oauth/callback',
    'https://cursor.com/oauth/cb',
    'https://manus.im/oauth/callback',
    'https://vitormr.dev/oauth/callback',
  ]) {
    assert.equal(isAllowedRedirectUri(uri), true, `Root host must be allowed: ${uri}`);
  }
});

test('OAuth allowlist: subdomains of trusted roots accepted (Perplexity bug fix)', () => {
  for (const uri of [
    'https://api.perplexity.ai/connection/oauth/callback',
    'https://comet.perplexity.ai/oauth/cb',
    'https://mcp.perplexity.ai/callback',
    'https://www.perplexity.ai/oauth/callback',
    'https://app.claude.ai/oauth/callback',
    'https://api.claude.ai/oauth/callback',
    'https://www.chatgpt.com/oauth/cb',
    'https://platform.openai.com/oauth/callback',
    'https://api.openai.com/oauth/callback',
    'https://www.cursor.com/oauth/callback',
    'https://api.cursor.com/oauth/cb',
    'https://www.manus.im/oauth/callback',
    'https://nucleoia.vitormr.dev/oauth/callback',
  ]) {
    assert.equal(isAllowedRedirectUri(uri), true, `Subdomain of trusted root must be allowed: ${uri}`);
  }
});

test('OAuth allowlist: attacker domains rejected', () => {
  for (const uri of [
    'https://attacker.example/cb',
    'https://perplexity.ai.attacker.com/cb',          // suffix-injection prevention
    'https://fake-perplexity.ai/cb',                  // similar-but-not-actual
    'https://perplexity-ai.com/cb',                   // typo-squat variant
    'https://my-claude.ai.attacker.example/cb',       // host smuggling
    'https://malicious.com/path?x=perplexity.ai',     // query injection
    'https://claudeai.evil.com/cb',                   // no dot separator
  ]) {
    assert.equal(isAllowedRedirectUri(uri), false, `Attacker URI must be REJECTED: ${uri}`);
  }
});

test('OAuth allowlist: custom schemes accepted (Cursor, VSCode)', () => {
  for (const uri of [
    'cursor://mcp/callback',
    'vscode://anthropic.claude/callback',
    'vscode-insiders://anthropic.claude/cb',
    'code-oss://anthropic/cb',
  ]) {
    assert.equal(isAllowedRedirectUri(uri), true, `Custom scheme must be allowed: ${uri}`);
  }
});

test('OAuth allowlist: localhost accepted for dev', () => {
  for (const uri of [
    'http://localhost:3000/callback',
    'http://localhost:8080/oauth/cb',
    'http://127.0.0.1:5173/callback',
    'http://127.0.0.1:54323/auth/v1/callback',
  ]) {
    assert.equal(isAllowedRedirectUri(uri), true, `Localhost must be allowed: ${uri}`);
  }
});

test('OAuth allowlist: non-https remote rejected (downgrade prevention)', () => {
  // Localhost over http is explicitly allowed (dev), but ANY OTHER http URL
  // must be rejected — even if the host is a trusted root.
  for (const uri of [
    'http://perplexity.ai/cb',
    'http://claude.ai/cb',
    'http://api.perplexity.ai/cb',
    'http://chatgpt.com/cb',
  ]) {
    assert.equal(isAllowedRedirectUri(uri), false,
      `HTTP (non-localhost) must be REJECTED to prevent downgrade attacks: ${uri}`);
  }
});

test('OAuth allowlist: empty/garbage rejected', () => {
  for (const uri of ['', '   ', 'not-a-url', 'ftp://perplexity.ai/cb', null, undefined]) {
    assert.equal(isAllowedRedirectUri(uri), false, `Garbage must be rejected: ${String(uri)}`);
  }
});

test('OAuth allowlist: hostname case-insensitivity (Host header normalization)', () => {
  // Per RFC 3986, hostnames are case-insensitive. URL parser already
  // lowercases them, but our matcher should be defensive.
  assert.equal(isAllowedRedirectUri('https://API.PERPLEXITY.AI/oauth/callback'), true);
  assert.equal(isAllowedRedirectUri('https://Claude.AI/cb'), true);
});

test('OAuth allowlist: query/path/fragment do not affect decision', () => {
  // Allowlist decides on host only — path/query/fragment are caller concern.
  assert.equal(isAllowedRedirectUri('https://api.perplexity.ai/x?a=1&b=2#frag'), true);
  assert.equal(isAllowedRedirectUri('https://claude.ai/long/nested/path?with=many&q=params'), true);
});
