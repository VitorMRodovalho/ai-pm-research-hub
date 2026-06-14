import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, it } from 'node:test';

const ROOT = process.cwd();
const annexPath = join(ROOT, 'docs/legal/641_MANUAL_R3_DATA_PROTECTION_ANNEX_DRAFT.md');
const annex = readFileSync(annexPath, 'utf8');

describe('#641 Manual R3 data protection annex draft', () => {
  it('exists as a G12-gated draft, not final legal language', () => {
    assert.match(annex, /Status:\*\* RASCUNHO operacional/);
    assert.match(annex, /bloqueada por retorno G12/);
    assert.match(annex, /Nao e aconselhamento juridico/);
  });

  it('anchors the gap to the 4 signed bilateral agreements and Manual R3 vehicle', () => {
    assert.match(annex, /PMI-GO ↔ PMI-CE\/DF\/MG\/RS/);
    assert.match(annex, /nao contem clausulas especificas de dados pessoais/);
    assert.match(annex, /Manual de Governanca R3/);
    assert.match(annex, /incorporam por referencia/);
  });

  it('preserves the #628 controller/operator framing', () => {
    assert.match(annex, /PMI-GO e controlador/);
    assert.match(annex, /plataforma `nucleoia\.vitormr\.dev` atua como operadora/);
    assert.match(annex, /agentes autorizados da respectiva controladora, nao como operadores independentes/);
    assert.doesNotMatch(annex, /Welma[\s\S]{0,140}operadora/i);
  });

  it('does not attribute legal personality to Nucleo IA', () => {
    assert.match(annex, /O Nucleo IA nao possui personalidade juridica propria/);
    assert.doesNotMatch(annex, /Nucleo IA, na qualidade de (controlador|controladora|operador|operadora)/i);
  });

  it('keeps partner nominal sharing gated as F2.1 and aggregated-only in v1', () => {
    assert.match(annex, /No v1, o compartilhamento com capitulos parceiros e limitado a agregados/);
    assert.match(annex, /F2\.1 — nominal futuro, gated/);
    assert.match(annex, /Enquanto esses itens nao forem aprovados, a plataforma deve permanecer em agregados-only/);
  });

  it('contains the model clause and operational incorporation checklist', () => {
    assert.match(annex, /## 7\. Clausula-modelo para novos acordos ou aditivos/);
    assert.match(annex, /Protecao de dados pessoais e compartilhamento federado/);
    assert.match(annex, /## 8\. Checklist de incorporacao no Manual R3/);
    assert.match(annex, /Atualizar `\/privacy` se algum compartilhamento nominal deixar de ser agregados-only/);
  });

  it('carries ANPD references for legal review traceability', () => {
    assert.match(annex, /ANPD — Guia Orientativo para Definicoes dos Agentes de Tratamento/);
    assert.match(annex, /ANPD — Comunicacao de Incidente de Seguranca/);
    assert.match(annex, /gov\.br\/anpd/);
  });
});
