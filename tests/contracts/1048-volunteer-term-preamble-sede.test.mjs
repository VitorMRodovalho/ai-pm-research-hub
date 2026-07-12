/**
 * #1048 — the volunteer term preamble must name the SEDE (PMI Goiás) as the contracting
 * party, NEVER the volunteer's PMI affiliation chapter.
 *
 * Root cause: the preamble in buildVolunteerAgreementHTML used the data-driven
 * `certData.chapter_name`/`chapter_cnpj` (which carry the member's affiliation) as the
 * contracting party. For a non-GO affiliate the instrument named another chapter + CNPJ as
 * party, while title/clauses/signature correctly bound to PMI Goiás. Fix: the party is a
 * policy constant (SEDE_CHAPTER), hardcoded like the rest of the instrument.
 *
 * Static-source assertions (pdf.ts uses extensionless relative imports → not node-importable
 * without a bundler, so we lock the source, mirroring the repo's other cert contract tests).
 *
 * Register in BOTH the "test" and "test:contracts" whitelists in package.json (#1109).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const PDF = readFileSync(resolve(ROOT, 'src/lib/certificates/pdf.ts'), 'utf8');
const CHAPTERS = readFileSync(resolve(ROOT, 'src/lib/chapters.ts'), 'utf8');

const GO_CNPJ = '06.065.645/0001-99';

test('#1048: SEDE_CHAPTER constant defines PMI Goiás as the fixed contracting party', () => {
  assert.match(PDF, /const SEDE_CHAPTER = \{/, 'SEDE_CHAPTER constant declared');
  assert.match(PDF, /cnpj:\s*'06\.065\.645\/0001-99'/, 'sede CNPJ is the PMI-GO CNPJ');
  assert.match(PDF, /inline:\s*'PMI Goiás'/, 'sede inline short form');
  assert.match(PDF, /legalName:\s*'Seção Goiânia, Goiás — Brasil do Project Management Institute \(PMI Goiás\)'/,
    'sede legal name');
});

test('#1048: the preamble uses SEDE_CHAPTER as the party, not certData.chapter_name/cnpj', () => {
  // The contracting-party sentence must be driven by the sede constant.
  assert.match(PDF, /fazem entre si a <b>\$\{SEDE_CHAPTER\.legalName\}<\/b>, inscrito no CNPJ\/MF sob o nº \$\{SEDE_CHAPTER\.cnpj\}/,
    'preamble party = SEDE_CHAPTER.legalName + SEDE_CHAPTER.cnpj');
  // Regression guard: the buggy data-driven party must NOT resurface anywhere.
  assert.doesNotMatch(PDF, /fazem entre si a <b>\$\{certData\.chapter_name/,
    'preamble party must not read certData.chapter_name');
  assert.doesNotMatch(PDF, /CNPJ\/MF sob o nº \$\{certData\.chapter_cnpj/,
    'preamble CNPJ must not read certData.chapter_cnpj');
});

test('#1048: chapterInline is the sede, not derived from the member affiliation', () => {
  assert.match(PDF, /const chapterInline = SEDE_CHAPTER\.inline/, 'chapterInline = sede inline');
  assert.doesNotMatch(PDF, /const cn = certData\.chapter_name \|\| 'PMI Goiás'/,
    'old affiliation-derived chapterInline must be gone');
});

test('#1048: hydrate no longer restores the affiliation chapter as a render input', () => {
  assert.doesNotMatch(PDF, /certData\.chapter_cnpj = certData\.chapter_cnpj \|\| snap\.chapter_cnpj/,
    'dead snapshot->party restore removed');
  assert.doesNotMatch(PDF, /certData\.chapter_name = certData\.chapter_name \|\| snap\.chapter_name/,
    'dead snapshot->party restore removed');
});

test('#1048: sede legal name + CNPJ stay consistent with the is_contracting chapter (chapters.ts SSOT)', () => {
  // chapters.ts is the SSOT for chapter legal names; GO carries is_contracting: true.
  assert.match(CHAPTERS,
    /chapter_code: 'GO'[\s\S]*?legal_name: 'Seção Goiânia, Goiás — Brasil do Project Management Institute \(PMI Goiás\)'[\s\S]*?is_contracting: true/,
    'GO in chapters.ts is the is_contracting chapter with the same legal name as SEDE_CHAPTER');
  // The GO CNPJ appears exactly once as the sede constant (no scattered fallbacks left).
  const cnpjMatches = PDF.split(GO_CNPJ).length - 1;
  assert.equal(cnpjMatches, 1, `GO CNPJ should appear once (in SEDE_CHAPTER), found ${cnpjMatches}`);
});
