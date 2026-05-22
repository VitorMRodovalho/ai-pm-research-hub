/**
 * Forward-defense: /certificates page MUST wire downloadCertificatePDF so members
 * can actually access (LGPD Art. 18) the content of certs they've earned/signed.
 *
 * Origin: p218 BUG-217.B / Issue #258. PM smoke of PR #253 (RESOLVED-217.A) surfaced
 * that /certificates page showed the volunteer_agreement card correctly but offered
 * NO download/view path — only a "Verificar" link to public /verify/{code} (which
 * correctly shows metadata-only per LGPD; full content_snapshot is PII-heavy and must
 * NOT be exposed via a public verify URL).
 *
 * The PDF generation pipeline (src/lib/certificates/pdf.ts — 606 lines including
 * hydrateCertData + downloadCertificatePDF + buildCertificateHTML + print template)
 * already exists and is wired in /gamification.astro + /admin/certificates.astro.
 * Only /certificates.astro was missing the wire. Real fix scope: import + button + handler.
 *
 * Cross-ref:
 *   - src/pages/certificates.astro (member-facing list — this is what we're guarding)
 *   - src/lib/certificates/pdf.ts (the existing PDF pipeline)
 *   - src/pages/gamification.astro:1495 + admin/certificates.astro:282 (reference wires)
 *   - certificates.content_snapshot (LGPD-relevant: PII-heavy, member-private)
 *   - certificates.verification_code (public-facing identifier — drives hydration)
 *   - record_certificate_download RPC (download tracking)
 *   - P162 BUG-217.B
 *
 * Scope: static analysis. No DB env required.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const CERT_PAGE = resolve(ROOT, 'src/pages/certificates.astro');

test('certificates.astro imports downloadCertificatePDF from lib/certificates/pdf', () => {
  const body = readFileSync(CERT_PAGE, 'utf8');
  const importPattern = /import\s*\{[^}]*\bdownloadCertificatePDF\b[^}]*\}\s*from\s*['"]\.\.\/lib\/certificates\/pdf['"]/;
  assert.match(body, importPattern,
    'src/pages/certificates.astro must import downloadCertificatePDF from ../lib/certificates/pdf ' +
    '— this is the canonical PDF rendering pipeline used by /gamification and /admin/certificates');
});

test('certificates.astro renders a download button per cert (data-action="download-cert")', () => {
  const body = readFileSync(CERT_PAGE, 'utf8');
  const buttonPattern = /data-action=["']download-cert["']/;
  assert.match(body, buttonPattern,
    'src/pages/certificates.astro must render a download button per cert card with data-action="download-cert" ' +
    '— this is what event delegation hooks for the download click handler');
});

test('certificates.astro wires a click handler that calls downloadCertificatePDF', () => {
  const body = readFileSync(CERT_PAGE, 'utf8');
  // Event delegation handler calls downloadCertificatePDF (the imported fn, not a window global)
  const handlerPattern = /downloadCertificatePDF\s*\(/;
  assert.match(body, handlerPattern,
    'src/pages/certificates.astro must invoke downloadCertificatePDF() — without an invocation, the import is dead and the bug persists');
});

test('certificates.astro records download via record_certificate_download RPC for audit/LGPD', () => {
  const body = readFileSync(CERT_PAGE, 'utf8');
  const trackingPattern = /sb\.rpc\(\s*['"]record_certificate_download['"]/;
  assert.match(body, trackingPattern,
    'src/pages/certificates.astro must call record_certificate_download RPC before/after triggering download ' +
    '— LGPD Art. 37 audit trail requirement + matches /gamification + /admin/certificates pattern');
});

test('certificates.astro never embeds content_snapshot directly into card markup (PII discipline)', () => {
  const body = readFileSync(CERT_PAGE, 'utf8');
  // content_snapshot has member_birth_date, member_address, member_pmi_id, etc.
  // It must ONLY flow through downloadCertificatePDF -> hydrateCertData (which calls verify_certificate
  // server-side as the authenticated owner). Embedding raw content_snapshot into innerHTML would
  // bypass the controlled path and risk XSS + privacy leaks.
  const directEmbed = /\bcontent_snapshot\b\s*\)\s*\}/;
  assert.doesNotMatch(body, directEmbed,
    'src/pages/certificates.astro must not embed raw content_snapshot — flow PII strictly through pdf.ts hydrateCertData');
});
