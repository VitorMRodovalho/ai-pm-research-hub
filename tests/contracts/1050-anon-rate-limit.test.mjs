/**
 * Contract: #1050 — rate limiting for anon-executable surfaces + secret-compare hardening.
 *
 * Origin: security audit 2026-07-02 (item #1, "rate limit ausente"). Verdict PARTIAL.
 *
 * Design (grounded live this session):
 *  - `verify_certificate` / `capture_visitor_lead` are called browser→Supabase DIRECT,
 *    so they bypass the Cloudflare Worker edge — zone/Worker rate rules cannot cover them.
 *    The only real control is an in-RPC per-IP throttle. Verified live that an anon
 *    PostgREST RPC can read cf-connecting-ip from current_setting('request.headers').
 *  - `/oauth/token` IS a Worker route → throttled in-code via a KV IP bucket.
 *  - `/ingest` rate-limit intentionally SKIPPED (high-entropy secret = low value); only
 *    its constant-time compare drive-by ships here (owner scope decision 2026-07-05).
 *  - Fail-open everywhere: a missing IP signal / KV or storage error must never block a
 *    legitimate caller.
 *
 * Offline-only (static source assertions). The live throttle behavior was exercised via
 * curl during implementation (30 allowed → then rate_limited on the real anon path).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');

// ── Migration: helper + counter table + throttle wiring ──────────────────────────
const MIG_DIR = 'supabase/migrations';
const migFile = readdirSync(resolve(ROOT, MIG_DIR)).find((f) => f.includes('anon_rpc_ip_rate_limit_1050'));
const MIG = migFile ? read(`${MIG_DIR}/${migFile}`) : '';

test('migration file for #1050 exists', () => {
  assert.ok(migFile, 'migration *anon_rpc_ip_rate_limit_1050*.sql present');
});

test('migration: counter table is unlogged, RLS-enabled, revoked from anon', () => {
  assert.match(MIG, /CREATE UNLOGGED TABLE IF NOT EXISTS public\.anon_rate_counters/);
  assert.match(MIG, /ALTER TABLE public\.anon_rate_counters ENABLE ROW LEVEL SECURITY/);
  assert.match(MIG, /REVOKE ALL ON public\.anon_rate_counters FROM anon, authenticated/);
});

test('migration: helper reads cf-connecting-ip, is fail-open, and is not anon-callable', () => {
  assert.match(MIG, /FUNCTION public\.rl_check_and_bump/);
  assert.match(MIG, /request\.headers.*cf-connecting-ip|cf-connecting-ip/);
  // fail-open: missing IP → return true; any storage error → return true
  assert.match(MIG, /IF v_ip IS NULL OR v_ip = ''\s+THEN\s+RETURN true/);
  assert.match(MIG, /EXCEPTION WHEN others THEN\s+RETURN true/);
  // internal helper must not be exposed on the PostgREST anon surface
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.rl_check_and_bump\(text, int, int\) FROM public, anon, authenticated/);
});

test('migration: both hot RPCs call the throttle before doing work', () => {
  assert.match(MIG, /rl_check_and_bump\('verify_certificate', 30, 60\)/);
  assert.match(MIG, /rl_check_and_bump\('capture_visitor_lead', 10, 60\)/);
});

test('migration: capture_visitor_lead closes the idempotent enumeration oracle', () => {
  // both existing-lead and new-lead paths must return the SAME shape (no 'idempotent' key)
  assert.ok(!/'idempotent', true/.test(MIG), "must not return the distinguishing 'idempotent' flag");
});

// ── /oauth/token: in-code IP throttle ────────────────────────────────────────────
const IPRL = read('src/lib/ip-rate-limit.ts');
const TOKEN = read('src/pages/oauth/token.ts');

test('ip-rate-limit lib: keys by IP+action, reads cf-connecting-ip, fail-open', () => {
  assert.ok(IPRL, 'src/lib/ip-rate-limit.ts exists');
  assert.match(IPRL, /cf-connecting-ip/);
  assert.match(IPRL, /iprl:\$\{action\}:\$\{ip\}:\$\{bucket\}/);
  // fail-open when kv or ip missing
  assert.match(IPRL, /if \(!kv \|\| !ip\) return \{ allowed: true/);
});

test('token endpoint throttles both grants (30/min/IP) with a 429 + Retry-After', () => {
  assert.match(TOKEN, /import \{ checkIpRateLimit, clientIpFrom \} from '\.\.\/\.\.\/lib\/ip-rate-limit'/);
  assert.match(TOKEN, /checkIpRateLimit\(kv, clientIpFrom\(request\), 'oauth_token', 30\)/);
  assert.match(TOKEN, /status: 429/);
  assert.match(TOKEN, /'Retry-After'/);
  // placed before grant branching so it covers authorization_code AND refresh_token
  const rlIdx = TOKEN.indexOf("'oauth_token'");
  const grantIdx = TOKEN.indexOf("grant_type === 'refresh_token'");
  assert.ok(rlIdx > -1 && grantIdx > -1 && rlIdx < grantIdx, 'throttle runs before grant handling');
});

// ── Drive-by: constant-time secret compares ──────────────────────────────────────
const TSE_MAIN = read('src/lib/timing-safe-equal.ts');
const TSE_VEP = read('cloudflare-workers/pmi-vep-sync/src/timing-safe-equal.ts');
const CERTPDF = read('src/pages/api/internal/cert-pdf-render/[id].ts');
const VEP = read('cloudflare-workers/pmi-vep-sync/src/index.ts');

test('timing-safe-equal helpers exist in both build contexts', () => {
  for (const [name, src] of [['main', TSE_MAIN], ['pmi-vep-sync', TSE_VEP]]) {
    assert.ok(src, `timing-safe-equal.ts (${name}) exists`);
    assert.match(src, /crypto\.subtle\.sign\('HMAC'/, `${name} uses HMAC digest compare`);
  }
});

test('cert-pdf-render compares the Bearer secret in constant time (not raw !==)', () => {
  assert.match(CERTPDF, /import \{ timingSafeEqual \}/);
  assert.match(CERTPDF, /await timingSafeEqual\(auth, `Bearer \$\{expectedSecret\}`\)/);
  assert.ok(!/auth !== `Bearer \$\{expectedSecret\}`/.test(CERTPDF), 'no raw !== secret compare');
});

test('pmi-vep-sync /ingest compares the shared secret in constant time (not raw !==)', () => {
  assert.match(VEP, /import \{ timingSafeEqual \} from '\.\/timing-safe-equal'/);
  assert.match(VEP, /await timingSafeEqual\(secret, env\.INGEST_SHARED_SECRET\)/);
  assert.ok(!/secret !== env\.INGEST_SHARED_SECRET/.test(VEP), 'no raw !== secret compare');
});

// ── Drive-by: middleware no-Origin passthrough documented as intentional ─────────
test('middleware documents the no-Origin passthrough as intentional (#1050)', () => {
  const MW = read('src/middleware.ts');
  assert.match(MW, /no-Origin passthrough below is INTENTIONAL/);
  assert.match(MW, /Referer/); // warns a future reviewer not to fall back to Referer
});
