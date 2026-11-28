/**
 * Contract: anonymous download of an EVENT GUEST certificate PDF by code
 * (src/pages/api/certificates/guest-pdf/[code].ts) and its button on /verify.
 *
 * The route runs with the service-role key on an anonymous surface, so each assertion binds the
 * CONDITION to the RESULT inside the block that decides (see .claude/rules/guards.md):
 *   A. only guest codes pass the shape check, and a bad shape returns the 404
 *   B. a row that is not `issued`, has no PDF, or a PDF outside guests/ returns the SAME 404
 *      (oracle-free, mirroring verify_certificate #991)
 *   C. a throttled caller gets the same 404, not a distinguishable status
 *   D. the redirect is a signed URL with a short TTL, never a public URL
 *   E. the route reads only event_guest_certificates, so member certificates are not reachable
 *   F. /verify shows the button only for audience === 'event_guest'
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const route = readFileSync(resolve(ROOT, 'src/pages/api/certificates/guest-pdf/[code].ts'), 'utf8');
const page = readFileSync(resolve(ROOT, 'src/pages/verify/[code].astro'), 'utf8');

test('A: the code shape check returns the 404, and the shape is guest-only', () => {
  assert.match(route, /if\s*\(\s*!GUEST_CODE_RE\.test\(code\)\s*\)\s*return notFound\(\);/);
  const m = route.match(/const GUEST_CODE_RE = (\/.+\/);/);
  assert.ok(m, 'GUEST_CODE_RE must be declared');
  const re = eval(m[1]);
  assert.equal(re.test('CERT-EVT-2026-A1B2C3'), true);
  assert.equal(re.test('CERT-2026-A1B2C3'), false, 'member code shape must not pass');
  assert.equal(re.test('CERT-EVT-2026-A1B2C3x'), false, 'anchored at the end');
  assert.equal(re.test('xCERT-EVT-2026-A1B2C3'), false, 'anchored at the start');
});

test('B: not issued, no PDF, or a path outside guests/ all return the same 404', () => {
  const m = route.match(/if\s*\(([^{]*?)\)\s*\{\s*return notFound\(\);\s*\}/);
  assert.ok(m, 'one block must decide the not-found case');
  const cond = m[1];
  assert.match(cond, /!row\b/);
  assert.match(cond, /row\.status\s*!==\s*'issued'/);
  assert.match(cond, /!row\.pdf_url/);
  assert.match(cond, /!String\(row\.pdf_url\)\.startsWith\('guests\/'\)/);
  // every early exit that is about the document is the same response
  const notFoundFn = route.match(/function notFound\(\): Response \{([\s\S]*?)\n\}/);
  assert.ok(notFoundFn);
  assert.match(notFoundFn[1], /status:\s*404/);
});

test('C: a throttled caller is indistinguishable from not found', () => {
  assert.match(route, /if\s*\(\s*!rl\.allowed\s*\)\s*return notFound\(\);/);
});

test('D: the redirect target is a signed URL with a short TTL', () => {
  const ttl = route.match(/const SIGNED_URL_TTL_S = (\d+);/);
  assert.ok(ttl);
  assert.ok(Number(ttl[1]) > 0 && Number(ttl[1]) <= 300, `TTL ${ttl[1]}s must be at most 300s`);
  assert.match(route, /\.createSignedUrl\(row\.pdf_url,\s*SIGNED_URL_TTL_S/);
  assert.match(route, /status:\s*302,\s*headers:\s*\{\s*Location:\s*signed\.signedUrl/);
  assert.doesNotMatch(route, /getPublicUrl/);
});

test('E: the route reads only the guest table', () => {
  const tables = [...route.matchAll(/\.from\('([^']+)'\)/g)].map(x => x[1]);
  assert.deepEqual(tables, ['event_guest_certificates']);
  assert.match(route, /\.eq\('verification_code',\s*code\)/);
});

test('F: /verify offers the download only for event guest certificates', () => {
  assert.match(
    page,
    /const download = data\.audience === 'event_guest' && data\.verification_code\s*\?\s*`[^`]*\/api\/certificates\/guest-pdf\/\$\{encodeURIComponent/,
  );
  assert.match(page, /\$\{download\}/);
});
