/**
 * Contract #2738 (parte B): o visitante acha Publicações e Podcast pelo rodapé, e a data sai na língua da página.
 *
 * DEFEITOS, medidos em 19/10/2026 como visitante anônimo:
 *   1. o primeiro link de "Recursos públicos" no rodapé era a Biblioteca, que o anônimo vê vazia
 *      ("0 resource(s) found") desde que a #2555 a tirou do menu do visitante; e /podcast não tinha
 *      caminho nenhum a partir da home (só o ícone do Spotify, externo);
 *   2. /en/publications mostrava a data do trabalho em pt-BR ("out. de 2026"), porque formatDateOnly
 *      recebia o locale padrão.
 *
 * O QUE ESTE GUARD AFIRMA (conteúdo; o efeito foi medido no navegador, descrito na PR)
 *   A. Dentro do <nav> de recursos públicos do rodapé há link para /publications e /podcast, e nenhum
 *      para /library.
 *   B. As duas chaves novas existem nos três dicionários.
 *   C. A data da publicação é formatada com o locale do documento.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const maskAstro = (src) => maskJsComments(src).replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));

test('A: o nav de recursos públicos do rodapé leva a Publicações e Podcast, não à Biblioteca', () => {
  const src = maskAstro(read('src/layouts/BaseLayout.astro'));
  const nav = src.match(/<nav aria-label=\{t\('footer\.resourcesTitle', lang\)\}[\s\S]*?<\/nav>/);
  assert.ok(nav, 'o nav de recursos públicos do rodapé foi encontrado');
  assert.match(nav[0], /<a href=\{localePath\('\/publications', lang\)\}[^>]*>\{t\('footer\.publications', lang\)\}<\/a>/);
  assert.match(nav[0], /<a href=\{localePath\('\/podcast', lang\)\}[^>]*>\{t\('footer\.podcast', lang\)\}<\/a>/);
  assert.doesNotMatch(nav[0], /localePath\('\/library'/, 'a Biblioteca, vazia para o anônimo, saiu do rodapé');
});

for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
  test(`B: ${dict} tem as chaves do rodapé novas`, () => {
    const src = read(`src/i18n/${dict}.ts`);
    assert.match(src, /'footer\.publications': '[^']+'/);
    assert.match(src, /'footer\.podcast': '[^']+'/);
  });
}

test('C: a data da publicação é formatada com o locale do documento', () => {
  const src = maskJsComments(read('src/pages/publications.astro'));
  assert.match(src, /const dateStr = formatDateOnly\(p\.publication_date, \{[^}]*\}, document\.documentElement\.lang \|\| 'pt-BR'\)/);
});
