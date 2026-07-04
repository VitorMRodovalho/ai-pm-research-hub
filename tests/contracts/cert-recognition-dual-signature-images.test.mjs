/**
 * Contract: recognition certs (Ciclo 3 landscape template) embed BOTH Núcleo manager
 * handwriting signatures (approved mockup, owner request 2026-07-03).
 *
 * - The GP image comes from the issuer (certificates.issued_by → signature_url).
 * - The Co-GP image is the record of a REAL counter-sign act: resolved from
 *   certificates.counter_signed_by only (never a decorative default) — an
 *   un-counter-signed cert renders the plain line + typed name.
 * - Both resolutions go through the single shared resolveMemberSignatureUrl helper
 *   (private member-signatures bucket → short-TTL signed URL; #753 P1). No duplicated
 *   signed-URL plumbing.
 * - A missing URL degrades to '' — never a broken <img>, which would hold the PDF
 *   hostage in the #1047 all-images-decoded render guard.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const SRC = readFileSync(resolve(process.cwd(), 'src/lib/certificates/pdf.ts'), 'utf8');

test('recognition template renders both signature slots with conditional images', () => {
  assert.match(SRC, /\.rc-sigimg\{/, 'rc-sigimg CSS class exists');
  assert.match(SRC, /<div class="rc-sig">\$\{gpSigImg\}<div class="rc-sigline">/,
    'GP signature image slot precedes the GP line');
  assert.match(SRC, /<div class="rc-sig">\$\{coGpSigImg\}<div class="rc-sigline">/,
    'Co-GP signature image slot precedes the Co-GP line');
  assert.match(SRC, /const gpSigImg = certData\.signature_url \?/,
    'GP image is conditional on a resolved URL (degrades to empty, no broken <img>)');
  assert.match(SRC, /const coGpSigImg = certData\.co_signature_url \?/,
    'Co-GP image is conditional on a resolved URL');
});

test('co-signature resolves from counter_signed_by via the shared helper', () => {
  assert.match(SRC, /select\('counter_signed_by'\)/,
    'co-signer identity comes from certificates.counter_signed_by (a real counter-sign act)');
  assert.match(SRC, /async function resolveMemberSignatureUrl\(/, 'shared resolver exists');
  const calls = (SRC.match(/resolveMemberSignatureUrl\(sb,/g) || []).length;
  assert.ok(calls >= 2, `both GP and Co-GP resolve through the shared helper (got ${calls} call sites)`);
  const signedUrlSites = (SRC.match(/from\('member-signatures'\)\.createSignedUrl\(/g) || []).length;
  assert.equal(signedUrlSites, 1,
    'member-signatures signed-URL plumbing lives ONLY inside the shared helper (the certificates-bucket lookup is a different concern)');
});
