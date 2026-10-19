/**
 * Contract #2738 (parte G): os botões "Apply" da home abrem o formulário de interesse, não o VEP.
 *
 * DEFEITO, lido em 19/10/2026 no volunteer.pmi.org: os botões "Apply as researcher" e "Apply as leader" dos
 * cinco cards de vertical e os dois "Apply" da seção de recursos levavam a duas vagas do VEP só em pt-BR,
 * com prazo vencido (64966: 31/07/2026; 64967: 13/09/2026). Decisão do GP: os botões passam a abrir o
 * formulário de interesse que já existia (capture_visitor_lead), com o papel do botão.
 *
 * Exercido como anônimo no servidor local, com a RPC interceptada no navegador (nada gravado): o botão de
 * pesquisador abre o formulário com researcher, o de líder com leader; sem consentimento, 0 chamadas; o card
 * de Construction manda o id da vertical Construção; a seção de recursos manda apply-resources sem vertical.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. O payload leva o papel, a origem e a vertical que o botão passou (função pura, exercida).
 *   B. Cada botão do card liga o papel certo ao formulário, e o formulário manda esse papel à RPC.
 *   C. Os dois cards de candidatura da seção de recursos abrem o mesmo formulário, com o papel certo.
 *   D. Nenhum desses botões aponta para uma vaga do volunteer.pmi.org.
 *   E. A mensagem de sucesso é o texto aprovado pelo GP (pt-BR), e existe nas três línguas.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import { buildInterestPayload } from '../../src/lib/interestPayload.ts';

const ROOT = process.cwd();
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const maskAstro = (src) => maskJsComments(src).replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));
const VERT = maskJsComments(read('src/components/sections/VerticalsSection.tsx'));
const FORM = maskJsComments(read('src/components/sections/InterestForm.tsx'));
const RES = maskAstro(read('src/components/sections/ResourcesSection.astro'));
const input = { name: 'Fulano', email: 'fulano@example.com', message: '' };

test('A: o payload leva o papel, a origem e a vertical que o botão passou', () => {
  for (const role of ['researcher', 'leader']) {
    const p = buildInterestPayload(input, { roleInterest: role, source: 'apply-vertical', targetVertical: 'abc' }, '?utm_source=summit');
    assert.equal(p.role_interest, role);
    assert.equal(p.source, 'apply-vertical', 'a UTM não troca a origem; ela vai em utm_data');
    assert.equal(p.target_vertical, 'abc');
    assert.equal(p.lgpd_consent, true);
    assert.deepEqual(p.utm_data, { utm_source: 'summit' });
  }
  const r = buildInterestPayload(input, { roleInterest: 'leader', source: 'apply-resources' }, '');
  assert.equal(r.role_interest, 'leader');
  assert.equal(r.source, 'apply-resources');
  assert.equal('target_vertical' in r, false);
});

test('B: cada botão do card liga o papel certo ao formulário, que o manda à RPC', () => {
  for (const [role, label] of [['researcher', 'ctaResearcher'], ['leader', 'ctaLeader']]) {
    assert.match(VERT, new RegExp(`<button type="button" onClick=\\{\\(\\) => setApplyRole\\('${role}'\\)\\}[^>]*data-apply-role="${role}"[^>]*>\\s*\\{l\\.${label}\\} →\\s*</button>`), `${role}`);
  }
  assert.match(VERT, /\{applyRole && \(\s*<InterestForm key=\{applyRole\} roleInterest=\{applyRole\} source="apply-vertical" targetVertical=\{v\.id\}/);
  assert.match(FORM, /const payload = buildInterestPayload\(form, \{ roleInterest, source, targetVertical \}, window\.location\.search\);\s*const \{ data, error \} = await sb\.rpc\('capture_visitor_lead', \{ p_payload: payload \}\);/);
});

test('C: os cards de candidatura da seção de recursos abrem o mesmo formulário', () => {
  assert.match(RES, /import ApplyInterest from '\.\/InterestForm\.tsx';/);
  assert.match(RES, /t\('resources\.volunteerResearcher\.text', lang\),\s*applyRole: 'researcher' as const,/);
  assert.match(RES, /t\('resources\.volunteerLeader\.text', lang\),\s*applyRole: 'leader' as const,/);
  assert.match(RES, /\{r\.applyRole \? \(\s*<ApplyInterest client:visible roleInterest=\{r\.applyRole\} source="apply-resources"/);
  assert.match(FORM, /export default function ApplyInterest\([\s\S]*?onClick=\{\(\) => setOpen\(true\)\}[\s\S]*?\{open && <InterestForm roleInterest=\{roleInterest\} source=\{source\}/);
});

test('D: nenhum desses botões aponta para uma vaga do volunteer.pmi.org', () => {
  for (const [name, src] of [['VerticalsSection', VERT], ['InterestForm', FORM], ['ResourcesSection', RES]]) {
    assert.doesNotMatch(src, /volunteer\.pmi\.org\/opportunities/, name);
  }
});

test('E: a mensagem de sucesso é o texto aprovado e existe nas três línguas', () => {
  assert.match(read('src/i18n/pt-BR.ts'), /'comp\.interestForm\.success': 'Recebemos o seu interesse\. Respondemos em até 5 dias úteis, pelo e-mail que você informou\.',/);
  for (const dict of ['en-US', 'es-LATAM']) {
    assert.match(read(`src/i18n/${dict}.ts`), /'comp\.interestForm\.success': '[^']*5[^']*',/, dict);
  }
  assert.match(FORM, /<p className="[^"]*">\{l\('success'\)\}<\/p>/);
});
