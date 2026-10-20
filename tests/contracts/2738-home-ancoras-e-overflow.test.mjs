/**
 * Contract #2738: a home pública não pode ter âncora morta nem empurrar a largura no celular.
 *
 * DEFEITOS, medidos em 19/10/2026 como visitante anônimo (Playwright, 390x844 em contexto mobile):
 *   1. o CTA "Learn More ↓" do hero apontava para #nucleo; a NucleoSection continua IMPORTADA nas três
 *      index.astro, mas não é mais RENDERIZADA, então o clique não rolava nada (scrollY 0 → 0);
 *   2. a home rolava 78px na horizontal (scrollWidth 468 contra 390), só por causa da linha filtro + KPI
 *      do ranking de trilha: o <select> fica largo como a opção mais longa e a linha não quebrava;
 *   3. toda carga registrava um 406 no console: site_config lido com .single(), e o anônimo lê 0 linhas.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. Toda âncora interna (href="#x") de um componente que a página RENDERIZA tem um id="x" em algum
 *      componente que a mesma página renderiza. Ler os imports em vez das tags deixaria o defeito 1 verde,
 *      porque a seção que tinha o id ainda é importada. A leitura desce pelos .astro renderizados, porque
 *      parte da home é renderizada por uma seção e não pela página (o VerticalsSection, pelo ModelSection).
 *   B. A linha que contém o filtro do ranking quebra e se limita à largura do pai, e o select também.
 *      É conteúdo, não efeito: a prova de efeito foi a medição no navegador descrita na PR.
 *   C. A leitura de whatsapp_gp em site_config usa maybeSingle.
 *   D. A agenda pública (acima de Team, Research Streams, Rules, KPIs e Ranking) hidrata no carregamento.
 *      Com client:visible ela crescia 1084px durante a rolagem até a âncora, e o menu parava antes do
 *      alvo: medido em produção, Research Streams a 1335px do topo; com client:load, 80px (a margem).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
// Astro: comentário JS no frontmatter/script, {/* */} no template e <!-- --> no HTML.
const maskAstro = (src) => maskJsComments(src).replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));

/** Componentes que um .astro RENDERIZA: import resolvido E tag usada no template. */
function renderedBy(astroPath) {
  const src = maskAstro(readFileSync(astroPath, 'utf8'));
  const [, frontmatter = '', template = ''] = src.split(/^---$/m);
  const rendered = [];
  for (const m of frontmatter.matchAll(/^import\s+(\w+)\s+from\s+'([^']+)'/gm)) {
    const [, name, spec] = m;
    if (!new RegExp(`<${name}[\\s/>]`).test(template)) continue;
    const file = resolve(dirname(astroPath), spec);
    const withExt = [file, `${file}.astro`, `${file}.tsx`].find((f) => existsSync(f) && /\.(astro|tsx)$/.test(f));
    if (withExt) rendered.push({ name, file: withExt });
  }
  return rendered;
}

/** A árvore renderizada pela página: desce pelos .astro (um .tsx é folha). */
function renderedTree(pagePath) {
  const out = [];
  const seen = new Set();
  const walk = (file) => {
    for (const c of renderedBy(file)) {
      if (seen.has(c.file)) continue;
      seen.add(c.file);
      out.push(c);
      if (c.file.endsWith('.astro')) walk(c.file);
    }
  };
  walk(join(ROOT, pagePath));
  return out;
}

for (const page of ['src/pages/index.astro', 'src/pages/en/index.astro', 'src/pages/es/index.astro']) {
  test(`A: ${page}: toda âncora interna dos componentes renderizados tem alvo renderizado`, () => {
    const rendered = renderedTree(page);
    assert.ok(rendered.some((c) => c.name === 'HomepageHero'), 'o hero está entre os renderizados');
    assert.ok(rendered.some((c) => c.name === 'VerticalsSection'), 'a descida alcança o que o ModelSection renderiza');

    const ids = new Set([...maskAstro(read(page)).matchAll(/\bid="([\w-]+)"/g)].map((m) => m[1]));
    const anchors = [];
    for (const c of rendered) {
      const body = maskAstro(readFileSync(c.file, 'utf8'));
      for (const m of body.matchAll(/\bid="([\w-]+)"/g)) ids.add(m[1]);
      for (const m of body.matchAll(/\bhref="#([\w-]+)"/g)) anchors.push({ from: c.name, target: m[1] });
    }
    assert.ok(anchors.some((a) => a.from === 'HomepageHero'), 'o CTA do hero é uma âncora interna medida');

    const dead = anchors.filter((a) => !ids.has(a.target)).map((a) => `${a.from} → #${a.target}`);
    assert.deepEqual(dead, [], `âncora sem alvo renderizado: ${dead.join(', ')}`);
  });
}

test('B: a linha do filtro do ranking quebra e o select se limita à largura do pai', () => {
  const src = maskAstro(read('src/components/sections/TrailRankingSection.astro'));
  const row = src.match(/<div class="([^"]*)">\s*<select id="trailTribeFilter" class="([^"]*)"/);
  assert.ok(row, 'a div que contém o select do filtro foi encontrada');
  const rowClasses = row[1].split(/\s+/);
  const selectClasses = row[2].split(/\s+/);
  assert.ok(rowClasses.includes('flex-wrap'), 'a linha do filtro quebra');
  assert.ok(rowClasses.includes('max-w-full'), 'a linha do filtro não passa da largura do pai');
  assert.ok(selectClasses.includes('max-w-full'), 'o select não passa da largura da linha');
});

test('D: a agenda da home hidrata no carregamento, não ao ficar visível', () => {
  // Medido em 19/10/2026: com client:visible a agenda crescia 1084px no meio da rolagem até uma âncora,
  // e o menu parava antes do alvo (Research Streams a 1335px do topo em vez de 80).
  const src = maskAstro(read('src/components/sections/WeeklyScheduleSection.astro'));
  assert.match(src, /<AgendaVivaPublic client:load\b/);
  assert.doesNotMatch(src, /<AgendaVivaPublic client:visible\b/);
});

test('C: a leitura de whatsapp_gp não usa .single() (406 para o anônimo)', () => {
  const src = maskAstro(read('src/components/sections/ChaptersSection.astro'));
  assert.match(src, /from\('site_config'\)\.select\('value'\)\.eq\('key', 'whatsapp_gp'\)\.maybeSingle\(\)/);
});
