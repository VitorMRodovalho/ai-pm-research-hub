/**
 * #1047 — Volunteer-agreement PDF logo must be embedded (data URI), and both
 * renderers must fail LOUD on an undecoded image instead of freezing a defective PDF.
 *
 * Root cause locked here: the term template referenced the PMI-GO logo via a REMOTE
 * fetch (`<img src="${CANONICAL_ORIGIN}/assets/logos/pmigo.png">`). A transient fetch
 * failure produced a silently-defective frozen PDF because `networkidle`/`networkidle0`
 * do NOT reject on a broken image. 41 signed volunteer terms froze this way (backfill
 * 2026-05-22). The C4 turn (2026-07-09) signs a new wave of terms via the forward path
 * (CF Browser Rendering), which had never rendered the logo template.
 *
 * Invariants:
 *   1. src/lib/certificates/pmigo-logo.ts exports PMIGO_LOGO_DATA_URI as a PNG data URI
 *      that decodes byte-identically to public/assets/logos/pmigo.png (single source of
 *      truth — no drift between the embedded logo and the on-disk asset).
 *   2. pdf.ts references the logo ONLY via the data URI — no remote logo fetch, and
 *      CANONICAL_ORIGIN is no longer imported (its sole use was the logo <img>).
 *   3. pdf.ts exports IMAGES_LOADED_PREDICATE (the shared guard, one source of truth).
 *   4. BOTH renderers import IMAGES_LOADED_PREDICATE and evaluate it via waitForFunction
 *      before page.pdf() — a render that leaves an undecoded image fails (cert keeps
 *      pdf_url NULL, recoverable) rather than persisting a defective legal instrument.
 *
 * Cross-ref: #1047 · #648/#649 (immutability/snapshot — re-render constraint) · ADR-0098
 *   · src/lib/certificates/pdf.ts · scripts/backfill-cert-pdfs.ts
 *   · src/pages/api/internal/cert-pdf-render/[id].ts
 *
 * Scope: static analysis + byte compare. No DB env required.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const LOGO_MODULE = resolve(ROOT, 'src/lib/certificates/pmigo-logo.ts');
const LOGO_ASSET = resolve(ROOT, 'public/assets/logos/pmigo.png');
const PDF = resolve(ROOT, 'src/lib/certificates/pdf.ts');
const BACKFILL = resolve(ROOT, 'scripts/backfill-cert-pdfs.ts');
const FORWARD = resolve(ROOT, 'src/pages/api/internal/cert-pdf-render/[id].ts');

test('pmigo-logo.ts exists and exports PMIGO_LOGO_DATA_URI as a PNG data URI', () => {
  assert.ok(existsSync(LOGO_MODULE), 'src/lib/certificates/pmigo-logo.ts must exist');
  const body = readFileSync(LOGO_MODULE, 'utf8');
  assert.match(body, /export const PMIGO_LOGO_DATA_URI\s*=/,
    'must export PMIGO_LOGO_DATA_URI');
  assert.match(body, /"data:image\/png;base64,[A-Za-z0-9+/=]+"/,
    'PMIGO_LOGO_DATA_URI must be a PNG base64 data URI string literal');
});

test('embedded logo decodes byte-identically to public/assets/logos/pmigo.png', () => {
  const body = readFileSync(LOGO_MODULE, 'utf8');
  const m = body.match(/export const PMIGO_LOGO_DATA_URI\s*=\s*\n?\s*"(data:image\/png;base64,[A-Za-z0-9+/=]+)";/);
  assert.ok(m, 'PMIGO_LOGO_DATA_URI literal must be extractable');
  const b64 = m[1].replace('data:image/png;base64,', '');
  const decoded = Buffer.from(b64, 'base64');
  const asset = readFileSync(LOGO_ASSET);
  assert.equal(Buffer.compare(decoded, asset), 0,
    'embedded data URI must decode to the exact bytes of public/assets/logos/pmigo.png ' +
    '— regenerate the constant if the asset changed (see pmigo-logo.ts header)');
});

test('pdf.ts references the logo ONLY via the data URI (no remote fetch)', () => {
  const body = readFileSync(PDF, 'utf8');
  assert.doesNotMatch(body, /assets\/logos\/pmigo\.png/,
    'pdf.ts must NOT reference the remote logo path — a transient fetch failure freezes ' +
    'a silently-defective PDF (#1047 root cause)');
  assert.match(body, /import\s*\{\s*PMIGO_LOGO_DATA_URI\s*\}\s*from\s*['"]\.\/pmigo-logo['"]/,
    'pdf.ts must import PMIGO_LOGO_DATA_URI from ./pmigo-logo');
  assert.match(body, /<img src="\$\{PMIGO_LOGO_DATA_URI\}"/,
    'the logo <img> must use the inlined data URI');
  assert.doesNotMatch(body, /\bCANONICAL_ORIGIN\b/,
    'CANONICAL_ORIGIN must no longer be imported/used in pdf.ts (its sole use was the logo)');
});

test('pdf.ts exports the shared IMAGES_LOADED_PREDICATE guard', () => {
  const body = readFileSync(PDF, 'utf8');
  assert.match(body, /export const IMAGES_LOADED_PREDICATE\s*=/,
    'pdf.ts must export IMAGES_LOADED_PREDICATE as the single source of truth for the guard');
  assert.match(body, /document\.images/,
    'the predicate must inspect document.images');
  assert.match(body, /naturalWidth/,
    'the predicate must check naturalWidth > 0 (a broken <img> is complete but naturalWidth 0)');
});

for (const [label, file] of [['backfill script', BACKFILL], ['forward endpoint', FORWARD]]) {
  test(`${label} imports and evaluates IMAGES_LOADED_PREDICATE before page.pdf()`, () => {
    const body = readFileSync(file, 'utf8');
    assert.match(body, /IMAGES_LOADED_PREDICATE/,
      `${label} must import the shared guard predicate from pdf.ts (no re-implementation drift)`);
    assert.match(body, /waitForFunction\(\s*IMAGES_LOADED_PREDICATE/,
      `${label} must call waitForFunction(IMAGES_LOADED_PREDICATE, ...) — fail render on an ` +
      `undecoded image instead of freezing a defective PDF`);
    // Guard must run BEFORE the PDF is captured.
    const guardIdx = body.indexOf('waitForFunction(IMAGES_LOADED_PREDICATE');
    const pdfIdx = body.indexOf('.pdf({');
    assert.ok(guardIdx > -1 && pdfIdx > -1 && guardIdx < pdfIdx,
      `${label} must evaluate the guard before page.pdf()`);
  });
}
