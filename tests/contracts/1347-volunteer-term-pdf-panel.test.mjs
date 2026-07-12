// #1347 — VolunteerAgreementPanel: view/download the signed volunteer term per volunteer,
// batch-download the signed terms in view, and preview the active template per pending
// volunteer. This is a UI-wiring change over the existing PDF helpers; the panel keeps a
// SELF-CONTAINED inline `L` dictionary (NOT the 3 shared i18n dicts), which lint:i18n does
// NOT cover — so this static guard locks:
//   P1 — the panel imports the shared PDF helpers (no re-implementation);
//   P2 — the inline `L` dict has key parity across pt-BR / en-US / es-LATAM;
//   P3 — the new #1347 labels exist (in all 3 locales, via P2);
//   P4 — the action gates are correct (download only for a signed term with a code; preview
//        only for a pending row) and the batch runs over the FILTERED view.
//
// Pure source scan (runs under both `test` and `test:contracts`).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SRC = readFileSync(join(root, 'src/components/admin/VolunteerAgreementPanel.tsx'), 'utf8');

const LOCALES = ['pt-BR', 'en-US', 'es-LATAM'];

// Extract the key set of each locale block inside the inline `const L = { ... }` table.
// Locale headers are 2-space indented (`  'pt-BR': {`); keys are 4-space indented.
function keysByLocale() {
  const out = {};
  let current = null;
  for (const line of SRC.split('\n')) {
    const head = line.match(/^ {2}'(pt-BR|en-US|es-LATAM)':\s*\{/);
    if (head) { current = head[1]; out[current] = new Set(); continue; }
    if (current && /^ {2}\},?\s*$/.test(line)) { current = null; continue; }
    if (current) {
      const k = line.match(/^ {4}([a-zA-Z_][\w]*):/);
      if (k) out[current].add(k[1]);
    }
  }
  return out;
}

test('P1: panel imports the shared PDF helpers (reuse, not re-implementation)', () => {
  assert.match(
    SRC,
    /import\s*\{[^}]*downloadCertificatePDF[^}]*downloadBulkCertificatesPDF[^}]*\}\s*from\s*'\.\.\/\.\.\/lib\/certificates\/pdf'/,
    'must import downloadCertificatePDF + downloadBulkCertificatesPDF from lib/certificates/pdf',
  );
});

test('P2: inline L dictionary has key parity across the 3 locales', () => {
  const byLocale = keysByLocale();
  for (const loc of LOCALES) {
    assert.ok(byLocale[loc] && byLocale[loc].size > 0, `locale block ${loc} not found or empty`);
  }
  const pt = byLocale['pt-BR'];
  for (const loc of LOCALES) {
    const missing = [...pt].filter((k) => !byLocale[loc].has(k));
    const extra = [...byLocale[loc]].filter((k) => !pt.has(k));
    assert.equal(missing.length, 0, `${loc} missing keys vs pt-BR: ${missing.join(', ')}`);
    assert.equal(extra.length, 0, `${loc} has extra keys not in pt-BR: ${extra.join(', ')}`);
  }
});

test('P3: the #1347 labels exist in every locale', () => {
  const byLocale = keysByLocale();
  const NEW_KEYS = ['downloadPdf', 'previewTerm', 'bulkDownloadTerms', 'bulkNoTerms', 'previewPendingTitle', 'previewMemberNote'];
  for (const loc of LOCALES) {
    for (const k of NEW_KEYS) {
      assert.ok(byLocale[loc].has(k), `${loc} missing #1347 key: ${k}`);
    }
  }
});

test('P4: action gates and batch scope are correct', () => {
  // Download button is gated on a SIGNED term with a verification_code (a frozen instrument).
  assert.match(SRC, /m\.signed && m\.verification_code && \(/, 'download button must gate on m.signed && m.verification_code');
  assert.match(SRC, /downloadTermPdf\(m\)/, 'download button must call downloadTermPdf');
  // Preview is offered ONLY for pending rows (no signed instrument yet).
  assert.match(SRC, /\{!m\.signed && \(/, 'preview button must gate on !m.signed');
  assert.match(SRC, /setPreviewMember\(m\); setShowTemplate\(true\)/, 'preview must open the template modal scoped to the member');
  // Batch runs over the filtered view (signedInView derives from `filtered`), not all members.
  assert.match(SRC, /const signedInView = filtered\.filter\(m => m\.signed && !!m\.verification_code\)/,
    'batch must operate over the FILTERED view (signedInView)');
  assert.match(SRC, /downloadBulkCertificatesPDF\(signedInView\.map\(certToData\)/, 'batch must map signedInView through certToData');
  // certToData must NOT leak member PII into the payload (hydrateCertData reads the snapshot).
  assert.doesNotMatch(SRC, /certToData[\s\S]{0,400}member_email:/, 'certToData must not pass member_email');
});
