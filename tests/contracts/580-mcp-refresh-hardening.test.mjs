/**
 * #580 — Harden MCP server-side refresh-token rotation.
 *
 * Origin: security-engineer review during #234 (org-connector enablement). The
 * server-side OAuth auto-refresh that keeps Claude.ai / MCP connectors alive
 * multi-day was sound on the happy path, but had defensive-consistency gaps:
 *   - MEDIUM: the proxy KV re-store gated the write on `if (data.refresh_token)`.
 *     A partial 200 (access_token, no refresh_token) left the rotated-invalidated
 *     token in KV → the NEXT auto-refresh 400s → entry purged → re-auth mid-session.
 *   - LOW: oauth/token.ts swallowed JWT-decode/KV-store failures in `catch {}`.
 *   - INFO: decodeJwtPayload + tryAutoRefresh were copy-pasted across both proxies.
 *
 * Fix: extract a shared `src/lib/mcp-refresh.ts` (single source for the
 * always-restore behaviour + the TTL constant + the decode/window helpers), used
 * by both proxies and (decode + TTL) by token.ts; log the swallowed catches.
 *
 * Cross-ref:
 *   - src/lib/mcp-refresh.ts (the shared helper — the fix lives here)
 *   - src/pages/mcp.ts, src/pages/mcp/semantic.ts (proxy consumers)
 *   - src/pages/oauth/token.ts (decode + TTL consumer; logging hardened)
 *   - #580, #234, #280 follow-up (broader mcp-proxy.ts extraction)
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  decodeJwtPayload,
  isExpiringSoon,
  tryAutoRefresh,
  MCP_REFRESH_TTL_SECONDS,
} from '../../src/lib/mcp-refresh.ts';

const SRC = (rel) => readFileSync(new URL(`../../src/${rel}`, import.meta.url), 'utf8');

// ── Mocks ──────────────────────────────────────────────────────────────────
function makeMockKV(initial = {}, throwOn = {}) {
  const store = new Map(Object.entries(initial));
  const calls = { put: [], delete: [], get: [] };
  return {
    store,
    calls,
    async get(key) { calls.get.push(key); if (throwOn.get) throw new Error('kv get failure'); return store.get(key) ?? null; },
    async put(key, value, opts) { calls.put.push({ key, value, opts }); if (throwOn.put) throw new Error('kv put failure'); store.set(key, value); },
    async delete(key) { calls.delete.push(key); if (throwOn.delete) throw new Error('kv delete failure'); store.delete(key); },
  };
}

function makeFetch(responseSpec) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    return {
      ok: responseSpec.ok,
      status: responseSpec.status ?? (responseSpec.ok ? 200 : 400),
      json: async () => responseSpec.body,
    };
  };
  return { fetchImpl, calls };
}

function makeThrowingFetch() {
  const calls = [];
  const fetchImpl = async (url, init) => { calls.push({ url, init }); throw new TypeError('network unreachable'); };
  return { fetchImpl, calls };
}

function makeJwt(payload) {
  const b64 = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');
  return `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64(payload)}.sig`;
}

const CFG = { anonKey: 'anon-test-key', fetchImpl: undefined };

// ── decodeJwtPayload ─────────────────────────────────────────────────────────
test('decodeJwtPayload: extracts sub/exp from a well-formed token', () => {
  const p = decodeJwtPayload(makeJwt({ sub: 'user-123', exp: 1999999999 }));
  assert.equal(p.sub, 'user-123');
  assert.equal(p.exp, 1999999999);
});

test('decodeJwtPayload: returns null for non-3-part input', () => {
  assert.equal(decodeJwtPayload('not.a'), null);
  assert.equal(decodeJwtPayload('only-one-part'), null);
  assert.equal(decodeJwtPayload(''), null);
});

test('decodeJwtPayload: returns null for garbage payload', () => {
  assert.equal(decodeJwtPayload('aaa.@@@not-base64-json@@@.ccc'), null);
});

// ── isExpiringSoon ───────────────────────────────────────────────────────────
test('isExpiringSoon: false when exp is well beyond the 5-min window', () => {
  assert.equal(isExpiringSoon(2000, 300, 1000), false); // 2000-300=1700 < 1000 → false
});

test('isExpiringSoon: true when already expired', () => {
  assert.equal(isExpiringSoon(500, 300, 1000), true); // 200 < 1000 → true
});

test('isExpiringSoon: true inside the skew window, boundary is exclusive', () => {
  assert.equal(isExpiringSoon(1299, 300, 1000), true);  // 999 < 1000 → true
  assert.equal(isExpiringSoon(1300, 300, 1000), false); // 1000 < 1000 → false (exact boundary)
});

// ── tryAutoRefresh ───────────────────────────────────────────────────────────
test('tryAutoRefresh: no stored token → null, no fetch', async () => {
  const kv = makeMockKV();
  const { fetchImpl, calls } = makeFetch({ ok: true, body: {} });
  const out = await tryAutoRefresh('user-1', kv, { ...CFG, fetchImpl });
  assert.equal(out, null);
  assert.equal(calls.length, 0);
  assert.equal(kv.calls.put.length, 0);
  assert.equal(kv.calls.delete.length, 0);
});

test('tryAutoRefresh: happy path with rotated refresh_token → stores the NEW token', async () => {
  const kv = makeMockKV({ 'mcp_refresh:user-1': 'old-refresh' });
  const { fetchImpl } = makeFetch({ ok: true, body: { access_token: 'new-access', refresh_token: 'new-refresh' } });
  const out = await tryAutoRefresh('user-1', kv, { ...CFG, fetchImpl });
  assert.equal(out, 'new-access');
  assert.equal(kv.calls.put.length, 1);
  assert.equal(kv.calls.put[0].value, 'new-refresh');
  assert.equal(kv.calls.put[0].opts.expirationTtl, MCP_REFRESH_TTL_SECONDS);
  assert.equal(kv.calls.delete.length, 0);
});

test('tryAutoRefresh: MEDIUM — partial 200 (no refresh_token) re-stores the OLD token (not dropped)', async () => {
  const kv = makeMockKV({ 'mcp_refresh:user-1': 'old-refresh' });
  const { fetchImpl } = makeFetch({ ok: true, body: { access_token: 'new-access' } }); // NO refresh_token
  const out = await tryAutoRefresh('user-1', kv, { ...CFG, fetchImpl });
  assert.equal(out, 'new-access');
  // The fix: KV must NOT be left with a (potentially) rotated-invalidated token,
  // and must NOT be deleted. The old token is re-persisted with a fresh TTL.
  assert.equal(kv.calls.delete.length, 0, 'must not delete on a successful 200');
  assert.equal(kv.calls.put.length, 1, 'must re-store even without a rotated token');
  assert.equal(kv.calls.put[0].value, 'old-refresh');
  assert.equal(kv.calls.put[0].opts.expirationTtl, MCP_REFRESH_TTL_SECONDS);
  assert.equal(kv.store.get('mcp_refresh:user-1'), 'old-refresh');
});

test('tryAutoRefresh: non-2xx → deletes stale KV entry, returns null', async () => {
  const kv = makeMockKV({ 'mcp_refresh:user-1': 'old-refresh' });
  const { fetchImpl } = makeFetch({ ok: false, status: 400, body: { error: 'invalid_grant' } });
  const out = await tryAutoRefresh('user-1', kv, { ...CFG, fetchImpl });
  assert.equal(out, null);
  assert.deepEqual(kv.calls.delete, ['mcp_refresh:user-1']);
  assert.equal(kv.calls.put.length, 0);
});

test('tryAutoRefresh: 200 without access_token → deletes, returns null', async () => {
  const kv = makeMockKV({ 'mcp_refresh:user-1': 'old-refresh' });
  const { fetchImpl } = makeFetch({ ok: true, body: { refresh_token: 'whatever' } }); // no access_token
  const out = await tryAutoRefresh('user-1', kv, { ...CFG, fetchImpl });
  assert.equal(out, null);
  assert.deepEqual(kv.calls.delete, ['mcp_refresh:user-1']);
  assert.equal(kv.calls.put.length, 0);
});

test('tryAutoRefresh: sends the stored token + anon key to the Supabase token endpoint', async () => {
  const kv = makeMockKV({ 'mcp_refresh:user-1': 'old-refresh' });
  const { fetchImpl, calls } = makeFetch({ ok: true, body: { access_token: 'a', refresh_token: 'b' } });
  await tryAutoRefresh('user-1', kv, { anonKey: 'my-anon', fetchImpl });
  assert.equal(calls.length, 1);
  assert.match(calls[0].url, /\/auth\/v1\/token\?grant_type=refresh_token$/);
  assert.equal(calls[0].init.headers.apikey, 'my-anon');
  assert.deepEqual(JSON.parse(calls[0].init.body), { refresh_token: 'old-refresh' });
});

test('tryAutoRefresh: supabaseUrl override is honored', async () => {
  const kv = makeMockKV({ 'mcp_refresh:user-1': 'old-refresh' });
  const { fetchImpl, calls } = makeFetch({ ok: true, body: { access_token: 'a', refresh_token: 'b' } });
  await tryAutoRefresh('user-1', kv, { anonKey: 'k', supabaseUrl: 'https://custom.example.com', fetchImpl });
  assert.match(calls[0].url, /^https:\/\/custom\.example\.com\/auth\/v1\/token/);
});

// ── #580 fold (council GO_W_FIXES): tryAutoRefresh is total — never throws; fails open ──
test('tryAutoRefresh: empty anonKey → null, NO fetch, NO KV touch (prevents mass-purge on misconfig)', async () => {
  const kv = makeMockKV({ 'mcp_refresh:user-1': 'old-refresh' });
  const { fetchImpl, calls } = makeFetch({ ok: true, body: { access_token: 'a' } });
  const out = await tryAutoRefresh('user-1', kv, { anonKey: '', fetchImpl });
  assert.equal(out, null);
  assert.equal(calls.length, 0, 'must not call Supabase without an anon key');
  assert.equal(kv.calls.get.length, 0, 'must not even read KV');
  assert.equal(kv.calls.delete.length, 0, 'must NOT purge the KV entry');
  assert.equal(kv.calls.put.length, 0);
});

test('tryAutoRefresh: fetch throws (network blip) → null, fails open, does NOT purge KV', async () => {
  const kv = makeMockKV({ 'mcp_refresh:user-1': 'old-refresh' });
  const { fetchImpl } = makeThrowingFetch();
  const out = await tryAutoRefresh('user-1', kv, { anonKey: 'k', fetchImpl });
  assert.equal(out, null);
  assert.equal(kv.calls.delete.length, 0, 'transient network error must not delete a possibly-valid token');
  assert.equal(kv.calls.put.length, 0);
  assert.equal(kv.store.get('mcp_refresh:user-1'), 'old-refresh');
});

test('tryAutoRefresh: kv.get throws → null, fails open, no fetch', async () => {
  const kv = makeMockKV({ 'mcp_refresh:user-1': 'old-refresh' }, { get: true });
  const { fetchImpl, calls } = makeFetch({ ok: true, body: { access_token: 'a' } });
  const out = await tryAutoRefresh('user-1', kv, { anonKey: 'k', fetchImpl });
  assert.equal(out, null);
  assert.equal(calls.length, 0);
});

test('tryAutoRefresh: kv.put throws on happy path → STILL returns the fresh access_token', async () => {
  const kv = makeMockKV({ 'mcp_refresh:user-1': 'old-refresh' }, { put: true });
  const { fetchImpl } = makeFetch({ ok: true, body: { access_token: 'new-access', refresh_token: 'new-refresh' } });
  const out = await tryAutoRefresh('user-1', kv, { anonKey: 'k', fetchImpl });
  // A KV write failure only affects the NEXT refresh — must not discard the token we got.
  assert.equal(out, 'new-access');
});

test('tryAutoRefresh: kv.delete throwing on a rejected refresh does not crash (best-effort)', async () => {
  const kv = makeMockKV({ 'mcp_refresh:user-1': 'old-refresh' }, { delete: true });
  const { fetchImpl } = makeFetch({ ok: false, status: 400, body: { error: 'invalid_grant' } });
  const out = await tryAutoRefresh('user-1', kv, { anonKey: 'k', fetchImpl });
  assert.equal(out, null); // does not throw despite the delete failing
});

// ── Static invariants (lock the de-dup + single-source + no-swallow) ─────────
test('TTL constant is 30 days and single-sourced (no 2592000 literal in consumers)', () => {
  assert.equal(MCP_REFRESH_TTL_SECONDS, 2592000);
  for (const f of ['pages/mcp.ts', 'pages/mcp/semantic.ts', 'pages/oauth/token.ts']) {
    assert.equal(SRC(f).includes('2592000'), false, `${f} must reference MCP_REFRESH_TTL_SECONDS, not the literal`);
  }
});

test('both proxies import from the shared helper and keep NO local refresh copies', () => {
  for (const f of ['pages/mcp.ts', 'pages/mcp/semantic.ts']) {
    const src = SRC(f);
    assert.match(src, /from '\.\.?\/(?:\.\.\/)?lib\/mcp-refresh'/, `${f} must import the shared helper`);
    // Catch both `function X(` and `const/let/var X =` redeclarations (arrow-fn too).
    assert.equal(/(?:function\s+tryAutoRefresh|(?:const|let|var)\s+tryAutoRefresh)\s*[=(]/.test(src), false, `${f} must not redeclare tryAutoRefresh`);
    assert.equal(/(?:function\s+decodeJwtPayload|(?:const|let|var)\s+decodeJwtPayload)\s*[=(]/.test(src), false, `${f} must not redeclare decodeJwtPayload`);
  }
});

test('shared tryAutoRefresh always re-stores (|| fallback), never gates the put on data.refresh_token', () => {
  const src = SRC('lib/mcp-refresh.ts');
  assert.match(src, /const newRefresh = data\.refresh_token \|\| refreshToken;/);
  // The buggy pattern (gated put) must be gone.
  assert.equal(/if\s*\(\s*data\.refresh_token\s*\)/.test(src), false, 'put must not be gated on data.refresh_token');
});

test('token.ts is a retired stub with no refresh-store surface at all (#1210)', () => {
  // Pre-#1210 this test pinned the no-swallow logging around the KV refresh
  // store. #1210 moved token issuance to Supabase's native OAuth server, so the
  // hardened surface this guarded no longer exists — the stub must not have
  // grown it back.
  const src = SRC('pages/oauth/token.ts');
  assert.doesNotMatch(src, /mcp_refresh/, 'stub must not store refresh tokens');
  assert.doesNotMatch(src, /decodeJwtPayload/, 'stub has no JWT to decode');
  assert.doesNotMatch(src, /MCP_REFRESH_TTL_SECONDS/, 'stub must not reference the KV TTL');
});
