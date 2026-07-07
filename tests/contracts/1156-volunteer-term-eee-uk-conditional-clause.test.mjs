/**
 * Contract: #1156 (F3 de #1153) — Clause 14 (Transferência Internacional de Dados) renders
 * CONDITIONALLY by residency (EEA/EEE or UK) in the signed volunteer instrument.
 *
 * Per the .docx V2, Clause 14 is the GDPR/UK-GDPR Art. 49(1)(a) explicit-consent mechanism and
 * applies ONLY to volunteers resident in the European Economic Area or the United Kingdom. The
 * approved body is snapshotted verbatim (single source == .docx, INV-2); the conditional is a
 * RENDER-TIME decision, so the frozen snapshot keeps the full superset while a non-EEE/UK
 * volunteer's rendered instrument omits the clause.
 *
 * Scope: behavioral (imports the real self-contained module) + static (pdf.ts wiring).
 * Cross-ref: src/lib/certificates/conditional-clauses.ts · src/lib/certificates/pdf.ts
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  isEeaOrUkResidence,
  stripEeaUkClause,
  applyResidencyConditionals,
} from '../../src/lib/certificates/conditional-clauses.ts';

const PDF = readFileSync('src/lib/certificates/pdf.ts', 'utf8');

// Fixture mirroring the real v9 body structure around Clause 14 (heading + 14.1/14.2/14.3 with
// its "Cláusulas Contratuais" sub-item text, bounded by Cláusula 13 and Cláusula 15 headings).
const CL13 = '<p><strong>Cláusula 13.</strong> Foro e resolução de disputas.</p><p><strong>13.3</strong> renúncia a foro privilegiado.</p>';
const CL14 =
  '<p><strong>Cláusula 14.</strong> Consentimento e Garantias para Transferência Internacional de Dados (Voluntários Residentes no Espaço Econômico Europeu - EEE - e no Reino Unido)</p>' +
  '<p><strong>14.1</strong> Para residentes no EEE ou no Reino Unido, consente nos termos do Art. 49(1)(a) do GDPR.</p>' +
  '<p><strong>14.2</strong> Complementa Cláusula 9 §2º.</p>' +
  '<p><strong>14.3 Cláusulas Contratuais Padrão e garantias adequadas.</strong> Standard Contractual Clauses da Decisão (UE) 2021/914.</p>';
const CL15 = '<p><strong>Cláusula 15. Integração da Política e Ciclo de Vida de Versionamento</strong> remissão dinâmica.</p>';
const BODY = CL13 + CL14 + CL15;

describe('#1156 isEeaOrUkResidence — jurisdiction classification', () => {
  it('BR / empty / unknown → false (clause omitted)', () => {
    for (const c of [undefined, '', '  ', 'Brasil', 'Brazil', 'BR', 'Argentina', 'United States', 'USA']) {
      assert.equal(isEeaOrUkResidence(c), false, `${JSON.stringify(c)} should NOT be EEE/UK`);
    }
  });
  it('EEA + UK identifiers (EN / PT / ISO) → true (clause kept)', () => {
    for (const c of [
      'France', 'França', 'FR', 'Germany', 'Alemanha', 'DE', 'Portugal', 'PT', 'Ireland', 'IE',
      'Netherlands', 'Países Baixos', 'Holanda', 'Norway', 'Noruega', 'Iceland', 'Liechtenstein',
      'United Kingdom', 'Reino Unido', 'UK', 'GB', 'England', 'Inglaterra', 'Scotland', 'gbr',
    ]) {
      assert.equal(isEeaOrUkResidence(c), true, `${JSON.stringify(c)} SHOULD be EEE/UK`);
    }
  });
});

describe('#1156 stripEeaUkClause — semantic anchor path', () => {
  it('BR volunteer: Clause 14 (all sub-items) removed, neighbours kept', () => {
    const out = stripEeaUkClause(BODY, 'Brasil');
    assert.ok(!out.includes('Cláusula 14.'), 'Clause 14 heading must be gone');
    assert.ok(!out.includes('Transferência Internacional de Dados'), 'clause 14 body must be gone');
    assert.ok(!out.includes('14.1') && !out.includes('14.2') && !out.includes('14.3'),
      'all Clause 14 sub-items must be gone (14.3 "Cláusulas Contratuais" must not end the strip early)');
    assert.ok(out.includes('Cláusula 13.'), 'Clause 13 must remain');
    assert.ok(out.includes('Cláusula 15.'), 'Clause 15 must remain (boundary respected)');
  });
  it('EEE/UK volunteer: Clause 14 kept verbatim', () => {
    for (const c of ['France', 'Reino Unido', 'PT']) {
      const out = stripEeaUkClause(BODY, c);
      assert.equal(out, BODY, `body must be unchanged for ${c}`);
    }
  });
  it('empty/unknown residency omits the clause (documented fail-safe default)', () => {
    assert.ok(!stripEeaUkClause(BODY, undefined).includes('Cláusula 14.'));
    assert.ok(!stripEeaUkClause(BODY, 'Marte').includes('Cláusula 14.'));
  });
  it('no-op on bodies without the clause (BR legacy body)', () => {
    const plain = CL13 + CL15;
    assert.equal(stripEeaUkClause(plain, 'Brasil'), plain);
  });
  it('idempotent', () => {
    const once = stripEeaUkClause(BODY, 'Brasil');
    assert.equal(stripEeaUkClause(once, 'Brasil'), once);
  });
});

describe('#1156 stripEeaUkClause — explicit governance marker path (forward-compat)', () => {
  const marked =
    CL13 +
    '<section data-conditional="eee-uk"><p><strong>Cláusula 14.</strong> Transferência.</p><p>detalhe</p></section>' +
    CL15;
  it('marker removed for BR, whole marked element gone', () => {
    const out = stripEeaUkClause(marked, 'BR');
    assert.ok(!out.includes('data-conditional'), 'marked element removed');
    assert.ok(!out.includes('Cláusula 14.'));
    assert.ok(out.includes('Cláusula 13.') && out.includes('Cláusula 15.'));
  });
  it('marker kept for EEE/UK', () => {
    assert.equal(stripEeaUkClause(marked, 'Germany'), marked);
  });
});

describe('#1156 pdf.ts wiring (static)', () => {
  it('imports and applies the residency conditional to the approved body', () => {
    assert.match(PDF, /import \{ applyResidencyConditionals \} from "\.\/conditional-clauses"/,
      'pdf.ts must import applyResidencyConditionals');
    assert.match(PDF, /applyResidencyConditionals\(approvedBody, certData\.member_country\)/,
      'the approved body must be scoped by member_country before render');
    assert.match(PDF, /scopedBody\.replace\(\/\\\{chapterName\\\}\/g, chapterInline\)/,
      'the scoped body (not the raw approvedBody) must feed the {chapterName} render');
  });
});
