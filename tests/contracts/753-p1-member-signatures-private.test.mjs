/**
 * #753 Part 1 — member-signatures private bucket + signed-URL readers.
 *
 * Locks in: the bucket goes private; an owner-OR-issuer SELECT RLS policy gates reads; and EVERY signature
 * reader (client cert download, gamification cert, profile self-view, and — via hydrateCertData — the
 * server-side puppeteer render) resolves to a short-TTL signed URL instead of the raw public URL.
 *
 * Static source-parse (no DB) — flake-free. Live behaviour (own/issuer read allowed, public URL 404s) is
 * proven at apply time + a browser cert-render verify before the bucket flip goes live.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');

const MIG = (() => {
  const dir = join(ROOT, 'supabase/migrations');
  const f = readdirSync(dir).find((x) => x.includes('753_p1_member_signatures_private'));
  assert.ok(f, 'the #753 P1 migration must exist');
  return readFileSync(join(dir, f), 'utf8');
})();

test('migration makes member-signatures private + adds owner-OR-issuer SELECT policy', () => {
  assert.match(MIG, /UPDATE storage\.buckets SET public = false WHERE id = 'member-signatures'/,
    'bucket must be set private');
  assert.match(MIG, /CREATE POLICY member_signatures_read_own_or_issuer ON storage\.objects[\s\S]*?FOR SELECT/,
    'a SELECT policy must be created');
  // owner OR GP-issuer
  assert.match(MIG, /m\.auth_id = auth\.uid\(\)/, 'owner branch (own signature) required');
  assert.match(MIG, /can_by_member\(m\.id, 'manage_platform'\)/, 'issuer/GP branch required so certs still render');
  // escaped LIKE pattern (no fuzzy cross-member match), mirrors mig …256
  assert.match(MIG, /'_',\s*E'\\\\_'/, 'must escape the _ wildcard in the path pattern');
});

test('hydrateCertData (covers client cert + server puppeteer route) signs the issuer signature', () => {
  const src = read('src/lib/certificates/pdf.ts');
  const block = src.match(/Issuer signature[\s\S]*?\n  }/)[0];
  assert.match(block, /createSignedUrl\(/, 'issuer signature must resolve to a signed URL');
  assert.match(block, /from\('member-signatures'\)\.createSignedUrl/, 'sign against the member-signatures bucket');
  assert.doesNotMatch(block, /certData\.signature_url = issuer\.signature_url\b/,
    'must not assign the raw public URL directly anymore');
});

test('gamification cert reader signs the issuer signature', () => {
  const src = read('src/pages/gamification.astro');
  assert.match(src, /from\('member-signatures'\)\.createSignedUrl/, 'gamification cert must sign the issuer signature');
});

test('profile self-view signs the own signature (no raw public-URL SSR img)', () => {
  const src = read('src/pages/profile.astro');
  // SSR preview must carry data-sig + be signed client-side, NOT a raw <img src=signature_url>
  assert.match(src, /id="sig-preview"[^>]*data-sig=/, 'SSR preview must expose data-sig for client signing');
  assert.doesNotMatch(src, /id="sig-preview"[^>]*>\$\{m\.signature_url \? `<img src="\$\{m\.signature_url\}"/,
    'SSR must not embed the raw public signature URL directly');
  assert.match(src, /async function signOwnSig/, 'a client signing helper must exist');
  assert.match(src, /from\('member-signatures'\)\.createSignedUrl/, 'own signature must be signed client-side');
});
