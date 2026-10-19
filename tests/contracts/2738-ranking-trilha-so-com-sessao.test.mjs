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
 *   A. O item trail-ranking exige sessão e continua no grupo home-anchors (o contrato 1136 segue valendo).
 *   B. O Nav renderiza âncora que exige sessão escondida, no desktop e no celular, e só a mostra com _user.
 *   C. A seção nasce escondida, e a leitura do ranking só parte de dentro do caminho com sessão.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const maskAstro = (src) => maskJsComments(src).replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));

test('A: o item trail-ranking exige sessão e segue no grupo home-anchors', () => {
  const nav = maskJsComments(read('src/lib/navigation.config.ts'));
  const line = nav.match(/^.*key: 'trail-ranking'.*$/m);
  assert.ok(line, 'item trail-ranking presente');
  assert.match(line[0], /requiresAuth: true/);
  assert.match(line[0], /group: 'home-anchors'/);
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

test('C: a seção nasce escondida e o ranking só é lido com sessão', () => {
  const src = maskAstro(read('src/components/sections/TrailRankingSection.astro'));
  assert.match(src, /<section class="[^"]*\bhidden\b[^"]*" id="trail-ranking">/);
  assert.match(src, /function syncTrailRanking\(\) \{\s*const signedIn = !!\(window as any\)\.navGetUser\?\.\(\);\s*document\.getElementById\('trail-ranking'\)\?\.classList\.toggle\('hidden', !signedIn\);\s*if \(signedIn && !trailBooted\) \{ trailBooted = true; bootTrail\(\); \}/);
  assert.match(src, /window\.addEventListener\('nav:member', syncTrailRanking\);/);
  // A única chamada de bootTrail() fora da própria definição é a de dentro do caminho com sessão.
  const calls = src.match(/(?<!function )\bbootTrail\(\)/g) || [];
  assert.equal(calls.length, 1, 'bootTrail() é chamada num lugar só');
  assert.match(src, /async function bootTrail\(\) \{[\s\S]*?sb\.rpc\('get_public_trail_ranking'\)/);
});
