/**
 * Contract #2738 (parte C): quem chega à home por uma área de atuação descobre que já há linha de pesquisa
 * ativa e que outras verticais podem abrir.
 *
 * DEFEITO, medido em 19/10/2026 como visitante anônimo em EN: o card de Construction ou de PMO dizia
 * "Forming" e levava à vaga no VEP, mas não levava às linhas de pesquisa que já existem para essas áreas
 * (ficam mais abaixo, em Research Streams), e nada dizia que uma área nova pode ser proposta.
 *
 * #2553 PR-7: os cards de vertical (VerticalsSection) saíram da home com a v2, e com eles a frase aprovada em
 * 19/10/2026. Na v2 a mesma promessa mora na seção de linhas: o filtro por campo leva às linhas que já existem, e a
 * frase "novos campos e novas linhas podem abrir" com a porta "Propor uma linha" fica sempre visível.
 *
 * O QUE ESTE GUARD AFIRMA
 *   B. A seção de linhas termina, fora do bloco que depende da lista carregar, com a frase de novas linhas e a porta
 *      para propor uma linha (#join-institutions); o campo sem linha ativa leva à mesma porta.
 *   C. #tribes é um id da seção de linhas, e as três home pages renderizam essa seção.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const LINES = maskJsComments(read('src/components/sections/ResearchLinesSection.astro'));

test('B: a frase de novas linhas e a porta para propor ficam fora do bloco da lista, e o campo vazio leva à mesma porta', () => {
  // a lista fecha com `)}`; o parágrafo vem depois, e só ele fecha a seção
  assert.match(
    LINES,
    /\)\}\s*<p [^>]*>\s*\{t\('homeV2\.lines\.newLines', lang\)\}\s*<a href="#join-institutions"[^>]*>\{t\('homeV2\.lines\.proposeLine', lang\)\} →<\/a>\s*<\/p>\s*<\/div>\s*<\/section>/,
  );
  assert.match(
    LINES,
    /<p id="lines-empty-field"[^>]*>[\s\S]*?\{t\('homeV2\.lines\.emptyField', lang\)\}\s*<a href="#join-institutions"[^>]*>\{t\('homeV2\.lines\.proposeLine', lang\)\} →<\/a>\s*<\/p>/,
  );
});

test('C: #tribes existe e as três home pages renderizam a seção de linhas (#2553 PR 2: ResearchLinesSection)', () => {
  assert.match(maskJsComments(read('src/components/sections/ResearchLinesSection.astro')), /<section [^>]*id="tribes"/);
  for (const page of ['src/pages/index.astro', 'src/pages/en/index.astro', 'src/pages/es/index.astro']) {
    assert.match(maskJsComments(read(page)), /^\s*<ResearchLinesSection [^>]*\/>/m, `${page} renderiza a ResearchLinesSection`);
  }
});
