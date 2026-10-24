/**
 * Contract #2738 (parte H): o ranking da trilha da home só aparece, e só é lido, para quem entrou.
 *
 * DECISÃO DO GP (19/10/2026): o painel #trail-ranking expõe nome, foto e % de conclusão de cada
 * participante, muitos em 0/6, a todo visitante anônimo. Para quem não entrou, a seção não aparece, a home
 * não chama get_public_trail_ranking, e o item "Ranking" some do menu de seções. Quem entrou vê como antes.
 * Não há bloqueio de rota no servidor (ADR-0106), então a decisão é no cliente, pela sessão que o Nav
 * resolve (o evento nav:member dispara ao resolvê-la e de novo no logout; o anônimo nunca o recebe).
 *
 * Exercido no servidor local: anônimo, seção invisível, item escondido no desktop e no celular, 0
 * chamadas à RPC; com sessão simulada no navegador (sem login de ninguém, escritas respondidas ali),
 * seção visível com os cards, item à mostra, 1 chamada.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. #2553 PR 2 (home v2): o ranking saiu da home; nenhum item de menu nem página da home o renderiza.
 *   B. O Nav renderiza âncora que exige sessão escondida, no desktop e no celular, e só a mostra com _user.
 *   C. (retirado na #2553 PR-7) A seção nascia escondida e só lia o ranking com sessão. O componente saiu da home
 *      com a v2 e foi apagado; o ranking com nomes vive em /gamification, e get_public_trail_ranking perdeu o EXECUTE
 *      do anon na #2749.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const maskAstro = (src) => maskJsComments(src).replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));

test('A: o ranking da trilha saiu da home: nenhum item de menu e nenhuma página da home o renderiza', () => {
  // #2553 PR 2 (home v2): o ranking com nomes foi para /gamification (D3/D4); a home mostra a trilha em agregado.
  const navNow = readFileSync(join(ROOT, 'src/lib/navigation.config.ts'), 'utf8');
  assert.doesNotMatch(navNow, /key: 'trail-ranking'/);
  for (const page of ['src/pages/index.astro', 'src/pages/en/index.astro', 'src/pages/es/index.astro']) {
    assert.doesNotMatch(readFileSync(join(ROOT, page), 'utf8'), /<TrailRankingSection\b/, page);
  }
});

test('B: o Nav esconde a âncora que exige sessão e só a mostra com _user', () => {
  const src = maskAstro(read('src/components/nav/Nav.astro'));
  const hidden = /data-session-anchor=\{item\.requiresAuth \? '' : undefined\} style=\{item\.requiresAuth \? 'display:none' : undefined\}/g;
  const dropdown = src.match(/<div id="sections-dropdown"[\s\S]*?<\/div>/);
  assert.ok(dropdown, 'dropdown de seções encontrado');
  assert.match(dropdown[0], hidden, 'desktop');
  const mobile = src.match(/<div id="mobile-menu"[\s\S]*?\{homeAnchorItems\.map\(item => \([\s\S]*?<\/a>/);
  assert.ok(mobile, 'menu do celular encontrado');
  assert.match(mobile[0], hidden, 'celular');
  assert.match(src, /function syncSessionAnchors\(\) \{\s*document\.querySelectorAll<HTMLElement>\('\[data-session-anchor\]'\)\.forEach\(\(el\) => \{\s*el\.style\.display = _user \? '' : 'none';/);
  assert.match(src, /window\.addEventListener\('nav:member', syncSessionAnchors\);/);
});
