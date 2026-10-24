/**
 * Contract #2738 (parte F): aviso "Em breve" do Grupo de Estudos PMI-CPMAI na home, até 05/11/2026.
 *
 * DECISÃO DO GP (19/10/2026): perto da escada (#trail), um aviso só de texto (a iniciativa é confidencial,
 * nada dela é lido do banco), com o grupo abrindo em 05/11. O aviso some depois desse dia, no fim do dia pelo
 * horário de Brasília (UTC−3), e a data mora numa constante só.
 * CORREÇÃO DO GP (20/10/2026): o grupo é pago, com preço diferenciado para filiados ao PMI (não para membros
 * do Núcleo; TAP M05: ingresso de filiado, não filiado e voluntário do PMI-GO). O texto não diz mais "para
 * membros do Núcleo", e o link "Ainda não é membro? Entre numa linha" saiu, porque sugeria que entrar no
 * Núcleo dava acesso ao grupo.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. A regra de saída, exercida nos dois lados do limite: aparece em 05/11 às 23:59:59 de Brasília e
 *      some às 00:00:00 de 06/11 (03:00:00Z).
 *   B. O componente só renderiza quando a regra diz que sim, e a home o renderiza dentro da escada; o botão
 *      leva às Reuniões Gerais na língua da página, e não há link para entrar no Núcleo.
 *   C. O texto é o aprovado, palavra por palavra, nas três línguas; a chave do link de entrada não existe.
 *   D. A data de saída aparece uma vez só no código.
 *   E. O anúncio antigo do CPMAI perdeu a frase "grupo de estudos em formação — anúncio em breve", que o
 *      aviso deixou repetida (pedido do GP); o resto do anúncio continua.
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
  assert.doesNotMatch(body, /href="#join"|cpmaiStudyGroup\.join/, 'o aviso não leva a entrar no Núcleo (correção de 20/10)');
  assert.equal((body.match(/<a\b/g) || []).length, 1, 'um link só: o botão das Reuniões Gerais');
  const ladder = maskAstro(read('src/components/sections/LadderSection.astro'));
  assert.match(ladder, /import CpmaiStudyGroupNotice from '\.\/CpmaiStudyGroupNotice\.astro';/);
  assert.match(ladder, /<section class="[^"]*" id="trail">[\s\S]*?<CpmaiStudyGroupNotice lang=\{lang\} \/>/);
});

test('C: o texto é o aprovado nas três línguas, não promete abertura, e o link de entrada não existe', () => {
  const approved = {
    'pt-BR': {
      badge: 'Em breve',
      title: 'Grupo de Estudos PMI-CPMAI',
      body: 'Estudo crítico e aplicado da metodologia CPMAI, à luz dos padrões do PMI e de casos reais. Não é curso preparatório para a prova. O grupo é pago, com valor diferenciado para filiados ao PMI. Pré-lançamento na Reunião Geral de 05/11, aberta ao público.',
      cta: 'Saiba mais',
    },
    'en-US': {
      body: 'A critical, applied study of the CPMAI methodology, in light of PMI standards and real cases. It is not an exam prep course. The group is paid, with a special price for PMI members. Pre-launch at the November 5 General Meeting, open to the public.',
    },
    'es-LATAM': {
      body: 'Estudio crítico y aplicado de la metodología CPMAI, a la luz de los estándares del PMI y de casos reales. No es un curso preparatorio para el examen. El grupo es de pago, con un valor diferenciado para miembros del PMI. Prelanzamiento en la Reunión General del 5 de noviembre, abierta al público.',
    },
  };
  for (const [dict, keys] of Object.entries(approved)) {
    const src = read(`src/i18n/${dict}.ts`);
    for (const [k, v] of Object.entries(keys)) {
      assert.ok(src.includes(`  'cpmaiStudyGroup.${k}': '${v}',\n`), `${dict} cpmaiStudyGroup.${k}`);
    }
    for (const k of ['badge', 'title', 'body', 'cta']) assert.match(src, new RegExp(`'cpmaiStudyGroup\\.${k}': '[^']+',`), `${dict} ${k}`);
    // #2553 (GP 22/10/2026): a inscrição não está aberta e o site nunca anuncia antes da coordenação do grupo.
    // Nenhuma das línguas pode dizer que o grupo "abre" ou que a inscrição está aberta ("aberta ao público" é a
    // Reunião Geral, e continua).
    const notice = [...src.matchAll(/'cpmaiStudyGroup\.\w+': '([^']+)',/g)].map((m) => m[1]).join(' ');
    assert.doesNotMatch(notice, /\babre\b|\bopens\b|inscri[çc][õo](?:es|n)\s+abiert|inscri[çc][õo]es\s+abertas|enrol+ment\s+(?:is\s+)?open|registration\s+(?:is\s+)?open/i, `${dict}: o aviso promete abertura`);
    assert.doesNotMatch(src, /'cpmaiStudyGroup\.join'/, `${dict}: a chave do link de entrada saiu`);
  }
});

test('E: o anúncio antigo do CPMAI não promete mais "anúncio em breve" do grupo', () => {
  // Pedido do GP (19/10/2026): com o aviso próprio do grupo, a frase do anúncio antigo ficou repetida.
  const gone = {
    'pt-BR': /em formação\s*—\s*anúncio em breve/i,
    'en-US': /study group forming\s*—\s*announcement coming soon/i,
    'es-LATAM': /en formación\s*—\s*anuncio próximamente/i,
  };
  for (const [dict, re] of Object.entries(gone)) {
    const src = read(`src/i18n/${dict}.ts`);
    assert.doesNotMatch(src, re, dict);
    assert.match(src, /'cpmai\.announce\.body': '[^']+\.',/, `${dict}: o resto do anúncio continua`);
  }
  assert.match(maskAstro(read('src/components/sections/LadderSection.astro')), /\{t\('cpmai\.announce\.body', lang\)\}/);
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
