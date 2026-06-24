// tests/contracts/855-ssr-security-headers-parity.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json
// (SEDIMENT-186.C) before running.
/**
 * Contract: SSR security headers (src/middleware.ts) stay in lockstep with the
 * Cloudflare-Pages `public/_headers` policy (#855).
 *
 * WHY: deploy is Cloudflare WORKERS (astro.config output:'server'). `_headers`
 * is a Pages feature — on Workers it only decorates the static-asset system
 * (/_astro/*); SSR HTML routes get ZERO headers from it. The live middleware
 * (src/middleware.ts) re-applies the SAME policy onto SSR responses from a shared
 * SSOT (src/lib/securityHeaders.ts). This test is the RATCHET that stops the two
 * from drifting: it parses the `/*` block of public/_headers, extracts the CSP
 * (and the other global headers), and asserts they byte-equal the shared
 * constants the middleware uses.
 *
 * It also pins the #855 footgun's fix: the policy must live in src/middleware.ts —
 * the file Astro actually loads. (There is a separate, KNOWN-DEAD shadow at
 * src/middleware/index.ts that Astro ignores whenever src/middleware.ts exists;
 * retiring it + its dormant auth gate is tracked outside this headers-only PR.)
 * This test requires the LOADED middleware to import the SSOT and apply it.
 *
 * Offline-only (static source assertions); no DB gating.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');

// ── Tiny parser for Cloudflare `_headers` syntax ──────────────────────────────
// Lines with no leading whitespace that start with `/` open a path block; the
// indented `Header: value` lines under it belong to that block.
function parseHeadersFile(text) {
  const blocks = {}; // path -> { headerName: value }
  let current = null;
  for (const raw of text.split('\n')) {
    if (!raw.trim() || raw.trim().startsWith('#')) continue;
    if (!/^\s/.test(raw)) {
      current = raw.trim(); // path line (e.g. "/*", "/admin/*")
      blocks[current] = {};
      continue;
    }
    if (!current) continue;
    const idx = raw.indexOf(':');
    if (idx === -1) continue;
    blocks[current][raw.slice(0, idx).trim()] = raw.slice(idx + 1).trim();
  }
  return blocks;
}

const headers = parseHeadersFile(read('public/_headers'));
const SSOT = read('src/lib/securityHeaders.ts');

// Reconstruct the CSP the SSOT exports (built from concatenated string literals).
function extractExportedCsp(src) {
  const m = src.match(/export const CSP\s*=([\s\S]*?);\n/);
  assert.ok(m, 'securityHeaders.ts exports a CSP constant');
  const parts = [...m[1].matchAll(/"([^"]*)"|'([^']*)'/g)].map((x) => x[1] ?? x[2]);
  assert.ok(parts.length > 0, 'CSP is built from string literals');
  return parts.join('');
}
const ssotCsp = extractExportedCsp(SSOT);

test('parity: _headers has a /* block with a CSP', () => {
  assert.ok(headers['/*'], 'public/_headers defines a /* block');
  assert.ok(headers['/*']['Content-Security-Policy'], '/* block declares a CSP');
});

test('parity: middleware CSP byte-equals _headers /* CSP (anti-drift)', () => {
  assert.equal(
    ssotCsp,
    headers['/*']['Content-Security-Policy'],
    'src/lib/securityHeaders.ts CSP must byte-match public/_headers /* CSP — change BOTH in the same PR.',
  );
});

test('parity: CSP carries frame-ancestors and frame-src none (clickjacking layer)', () => {
  assert.match(ssotCsp, /frame-ancestors 'none'/, "CSP must declare frame-ancestors 'none'");
  assert.match(ssotCsp, /frame-src 'none'/, "CSP must declare frame-src 'none'");
});

test('parity: the other global headers match between _headers /* and the SSOT', () => {
  const want = {
    'X-Frame-Options': 'DENY',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
  };
  const esc = (s) => s.replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&');
  for (const [name, value] of Object.entries(want)) {
    assert.equal(headers['/*'][name], value, `_headers /* ${name}`);
    assert.match(SSOT, new RegExp(`["']${esc(name)}["']\\s*:\\s*["']${esc(value)}["']`),
      `securityHeaders.ts declares ${name}: ${value}`);
  }
});

test('middleware: imports the SSOT and applies headers (not a hardcoded copy)', () => {
  const mw = read('src/middleware.ts');
  assert.match(mw, /from ["']\.\/lib\/securityHeaders["']/, 'middleware imports the SSOT');
  assert.match(mw, /applySecurityHeaders/, 'middleware applies applySecurityHeaders');
  assert.ok(!/default-src 'self'/.test(mw), 'middleware must not inline the CSP string');
});

test('#855: the security-header policy lives in the Astro-loaded middleware', () => {
  // Astro loads src/middleware.ts and ignores src/middleware/index.ts when both
  // exist. The #855 root cause was the policy sitting in the IGNORED shadow file,
  // so it never reached SSR responses. Guard: the loaded file is present and is the
  // one applying the SSOT (covered above), NOT only the shadow.
  assert.ok(existsSync(resolve(ROOT, 'src/middleware.ts')), 'src/middleware.ts (the loaded middleware) exists');
});

test('parity: no-store + noindex per-route policy matches _headers', () => {
  const NO_STORE = 'no-cache, no-store, must-revalidate';
  const noStorePaths = Object.entries(headers)
    .filter(([, h]) => h['Cache-Control'] === NO_STORE).map(([p]) => p);
  const cover = (p) => p.endsWith('/*') ? SSOT.includes(`"${p.slice(0, -1)}"`) : SSOT.includes(`"${p}"`);
  for (const p of noStorePaths) assert.ok(cover(p), `SSOT covers no-store for ${p}`);
  assert.ok(!noStorePaths.includes('/'), '_headers does not no-store the home');

  const noindexPaths = Object.entries(headers)
    .filter(([, h]) => /noindex/.test(h['X-Robots-Tag'] || '')).map(([p]) => p);
  assert.deepEqual(noindexPaths, ['/admin/*'], 'noindex is admin-only in _headers');
  assert.match(SSOT, /NOINDEX_PREFIXES[\s\S]*?["']\/admin\/["']/, 'SSOT noindex = /admin/');
});
