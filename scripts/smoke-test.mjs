#!/usr/bin/env node
// GC-097 Phase 2 — Post-deploy smoke test
// Usage: node scripts/smoke-test.mjs [--base https://nucleoia.vitormr.dev]

import { strict as assert } from 'node:assert';

const baseArg = process.argv.find(a => a.startsWith('--base='));
const baseIdx = process.argv.indexOf('--base');
const BASE = baseArg ? baseArg.split('=')[1]
  : (baseIdx > -1 && process.argv[baseIdx + 1]?.startsWith('http') ? process.argv[baseIdx + 1] : null)
  || 'https://nucleoia.vitormr.dev';

const SUPABASE_URL = 'https://ldrfrvwhxsmgaabwmaik.supabase.co';
const ANON_KEY = process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxkcmZydndoeHNtZ2FhYndtYWlrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI3MjU5NDQsImV4cCI6MjA4ODMwMTk0NH0.gzibKd7Jyck3Ya61vzrloX1YZt-0pNReTuefdi4mAmw';

let passed = 0;
let failed = 0;
const failures = [];

async function test(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`  ✅ ${name}`);
  } catch (err) {
    failed++;
    failures.push({ name, error: err.message });
    console.log(`  ❌ ${name}: ${err.message}`);
  }
}

console.log(`\n🔍 Smoke Test — ${BASE}\n`);
const start = Date.now();

// ═══ GROUP 1: Site availability ═══
console.log('── Site ──');

await test('Homepage returns 200', async () => {
  const res = await fetch(BASE);
  assert.equal(res.status, 200);
  const html = await res.text();
  assert.ok(html.includes('</html>'), 'Response is HTML');
});

await test('Legacy redirect: workers.dev → 301', async () => {
  const res = await fetch('https://platform.ai-pm-research-hub.workers.dev/', { redirect: 'manual' });
  assert.equal(res.status, 301);
  const location = res.headers.get('location');
  assert.ok(location?.includes('nucleoia.vitormr.dev'), `Redirects to custom domain, got: ${location}`);
});

await test('i18n: /en/ serves English', async () => {
  const res = await fetch(`${BASE}/en/`);
  assert.equal(res.status, 200);
  const html = await res.text();
  assert.ok(html.includes('lang="en"') || html.includes('lang="en-US"'), 'HTML lang attribute set');
});

// ═══ GROUP 2: OAuth Discovery ═══
console.log('\n── OAuth Discovery ──');

await test('.well-known/oauth-protected-resource', async () => {
  const res = await fetch(`${BASE}/.well-known/oauth-protected-resource`);
  assert.equal(res.status, 200);
  const json = await res.json();
  assert.equal(json.resource, `${BASE}/mcp`);
  assert.ok(json.scopes_supported?.includes('mcp:tools'));
});

await test('.well-known/oauth-authorization-server', async () => {
  const res = await fetch(`${BASE}/.well-known/oauth-authorization-server`);
  assert.equal(res.status, 200);
  const json = await res.json();
  assert.equal(json.issuer, BASE);
  assert.ok(json.authorization_endpoint?.includes('/oauth/authorize'));
  assert.ok(json.token_endpoint?.includes('/oauth/token'));
  assert.ok(json.code_challenge_methods_supported?.includes('S256'));
});

// ═══ GROUP 3: OAuth Endpoints ═══
console.log('\n── OAuth Endpoints ──');

await test('OAuth register: POST → 201 + client_id', async () => {
  const res = await fetch(`${BASE}/oauth/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ client_name: `smoke-test-${Date.now()}`, redirect_uris: ['https://example.com/callback'], grant_types: ['authorization_code'], response_types: ['code'], token_endpoint_auth_method: 'none' }),
  });
  assert.ok([200, 201].includes(res.status), `Expected 200/201, got ${res.status}`);
  const json = await res.json();
  assert.ok(json.client_id, 'Response has client_id');
});

await test('OAuth authorize: GET → redirect to consent', async () => {
  const res = await fetch(`${BASE}/oauth/authorize?client_id=test&redirect_uri=https://example.com/cb&response_type=code&code_challenge=abc&code_challenge_method=S256&state=smoke`, { redirect: 'manual' });
  assert.ok([200, 302].includes(res.status), `Expected 200 or 302, got ${res.status}`);
});

// ═══ GROUP 4: MCP Endpoint ═══
console.log('\n── MCP ──');

await test('MCP: POST without auth → 401 + WWW-Authenticate', async () => {
  const res = await fetch(`${BASE}/mcp`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize' }),
  });
  assert.equal(res.status, 401);
  const wwwAuth = res.headers.get('www-authenticate');
  assert.ok(wwwAuth, 'WWW-Authenticate header present');
  assert.ok(wwwAuth.includes('Bearer'), 'WWW-Authenticate is Bearer scheme');
});

// ═══ GROUP 5: Edge Function Health ═══
console.log('\n── Edge Functions ──');

await test('nucleo-mcp/health → ok + version + 52 tools', async () => {
  const res = await fetch(`${SUPABASE_URL}/functions/v1/nucleo-mcp/health`, {
    headers: { 'Authorization': `Bearer ${ANON_KEY}` },
  });
  assert.equal(res.status, 200);
  const json = await res.json();
  assert.equal(json.status, 'ok');
  assert.ok(json.version, 'Has version');
  assert.ok(json.tools >= 50, `Expected ≥50 tools, got ${json.tools}`);
});

// ═══ GROUP 6: Public RPCs ═══
console.log('\n── Public RPCs ──');

await test('get_public_leaderboard → returns rows', async () => {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/get_public_leaderboard`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'apikey': ANON_KEY, 'Authorization': `Bearer ${ANON_KEY}` },
    body: '{"p_limit": 3}',
  });
  assert.equal(res.status, 200);
  const data = await res.json();
  assert.ok(Array.isArray(data), 'Response is array');
  assert.ok(data.length > 0, 'Has leaderboard entries');
});

await test('get_public_platform_stats → returns stats', async () => {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/get_public_platform_stats`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'apikey': ANON_KEY, 'Authorization': `Bearer ${ANON_KEY}` },
    body: '{}',
  });
  assert.equal(res.status, 200);
  const data = await res.json();
  assert.ok(data.active_members > 0, 'Has active members');
});

// ═══ SUMMARY ═══
const elapsed = ((Date.now() - start) / 1000).toFixed(1);
console.log(`\n${'═'.repeat(40)}`);
console.log(`  ${passed} passed, ${failed} failed (${elapsed}s)`);
if (failures.length > 0) {
  console.log('\n  Failures:');
  failures.forEach(f => console.log(`    • ${f.name}: ${f.error}`));
}
console.log(`${'═'.repeat(40)}\n`);

process.exit(failed > 0 ? 1 : 0);
