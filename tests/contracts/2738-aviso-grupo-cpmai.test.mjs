/**
 * Contract #2738 (parte F): aviso "Em breve" do Grupo de Estudos PMI-CPMAI na home, até 05/11/2026.
 *
 * DECISÃO DO GP (19/10/2026): perto da escada (#trail), um aviso só de texto (a iniciativa é confidencial,
 * nada dela é lido do banco), para membros, com o grupo abrindo em 05/11. O aviso some depois desse dia,
 * no fim do dia pelo horário de Brasília (UTC−3), e a data mora numa constante só.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. A regra de saída, exercida nos dois lados do limite: aparece em 05/11 às 23:59:59 de Brasília e
 *      some às 00:00:00 de 06/11 (03:00:00Z).
 *   B. O componente só renderiza quando a regra diz que sim, e a home o renderiza dentro da escada; o botão
 *      leva às Reuniões Gerais na língua da página, o link leva a #join.
 *   C. O texto pt-BR é o aprovado, palavra por palavra; as cinco chaves existem nas três línguas.
 *   D. A data de saída aparece uma vez só no código.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import { isCpmaiStudyGroupNoticeVisible, CPMAI_STUDY_GROUP_NOTICE_UNTIL } from '../../src/lib/cpmaiStudyGroupNotice.ts';

const ROOT = process.cwd();
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const maskAstro = (src) => maskJsComments(src).replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));

test('A: o aviso aparece até o fim de 05/11 em Brasília e some depois', () => {
  const visible = (iso) => isCpmaiStudyGroupNoticeVisible(new Date(iso));
  assert.equal(visible('2026-10-19T12:00:00-03:00'), true, 'hoje');
  assert.equal(visible('2026-11-05T09:00:00-03:00'), true, 'no dia da abertura');
  assert.equal(visible('2026-11-05T23:59:59-03:00'), true, 'último segundo de 05/11 em Brasília');
  assert.equal(visible('2026-11-06T02:59:59Z'), true, 'o mesmo instante, em UTC');
  assert.equal(visible('2026-11-06T00:00:00-03:00'), false, 'meia-noite de 06/11 em Brasília');
  assert.equal(visible('2026-11-06T03:00:00Z'), false, 'o mesmo instante, em UTC');
  assert.equal(visible('2027-01-01T00:00:00-03:00'), false, 'depois');
  assert.equal(CPMAI_STUDY_GROUP_NOTICE_UNTIL.toISOString(), '2026-11-06T03:00:00.000Z');
});

test('B: o componente só renderiza quando a regra deixa, e a escada o renderiza', () => {
  const src = maskAstro(read('src/components/sections/CpmaiStudyGroupNotice.astro'));
  assert.match(src, /import \{ isCpmaiStudyGroupNoticeVisible \} from '\.\.\/\.\.\/lib\/cpmaiStudyGroupNotice';/);
  assert.match(src, /const visible = isCpmaiStudyGroupNoticeVisible\(new Date\(\)\);/);
  const body = src.split(/^---$/m)[2] || '';
  assert.match(body, /^\s*\{visible && \(\s*<aside id="cpmai-study-group-notice"[\s\S]*<\/aside>\s*\)\}\s*$/, 'todo o markup fica dentro de {visible && (...)}');
  assert.match(body, /<a href=\{`\$\{langPrefix\}\/reunioes-gerais`\}[^>]*>\s*\{t\('cpmaiStudyGroup\.cta', lang\)\} →\s*<\/a>/);
  assert.match(body, /<a href="#join"[^>]*>\s*\{t\('cpmaiStudyGroup\.join', lang\)\} →\s*<\/a>/);
  const ladder = maskAstro(read('src/components/sections/LadderSection.astro'));
  assert.match(ladder, /import CpmaiStudyGroupNotice from '\.\/CpmaiStudyGroupNotice\.astro';/);
  assert.match(ladder, /<section class="[^"]*" id="trail">[\s\S]*?<CpmaiStudyGroupNotice lang=\{lang\} \/>/);
});

test('C: o texto pt-BR é o aprovado e as chaves existem nas três línguas', () => {
  const pt = read('src/i18n/pt-BR.ts');
  const approved = {
    badge: 'Em breve',
    title: 'Grupo de Estudos PMI-CPMAI',
    body: 'Estudo crítico e aplicado da metodologia CPMAI, à luz dos padrões do PMI e de casos reais, para membros do Núcleo. Não é curso preparatório para a prova. Abre em 05/11, com pré-lançamento na Reunião Geral, aberta ao público.',
    cta: 'Saiba mais',
    join: 'Ainda não é membro? Entre numa linha',
  };
  for (const [k, v] of Object.entries(approved)) {
    assert.ok(pt.includes(`  'cpmaiStudyGroup.${k}': '${v}',\n`), `pt-BR cpmaiStudyGroup.${k}`);
  }
  for (const dict of ['en-US', 'es-LATAM']) {
    const src = read(`src/i18n/${dict}.ts`);
    for (const k of Object.keys(approved)) assert.match(src, new RegExp(`'cpmaiStudyGroup\\.${k}': '[^']+',`), `${dict} ${k}`);
  }
});

test('D: entre os arquivos do aviso, só o módulo da regra tem data', () => {
  const related = [];
  const dated = [];
  const walk = (dir) => {
    for (const name of readdirSync(join(ROOT, dir))) {
      const rel = `${dir}/${name}`;
      if (statSync(join(ROOT, rel)).isDirectory()) { walk(rel); continue; }
      if (!/\.(ts|tsx|astro|mjs|js)$/.test(name) || rel.startsWith('src/i18n/')) continue;
      const src = maskAstro(read(rel));
      if (!/cpmaiStudyGroup/i.test(src)) continue;
      related.push(rel);
      if (/\b20\d\d-\d\d-\d\d|new Date\(\s*\d/.test(src)) dated.push(rel);
    }
  };
  walk('src');
  assert.ok(related.includes('src/components/sections/CpmaiStudyGroupNotice.astro'), 'a varredura acha o componente');
  assert.deepEqual(dated, ['src/lib/cpmaiStudyGroupNotice.ts']);
});
