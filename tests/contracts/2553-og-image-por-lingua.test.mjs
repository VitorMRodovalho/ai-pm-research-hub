// tests/contracts/2553-og-image-por-lingua.test.mjs
/**
 * Contract: #2553 — a prévia de link (og:image / twitter:image) da página em inglês usa a imagem em
 * inglês; pt-BR e es-LATAM seguem com a original.
 *
 * POR QUE: medido em 20/10/2026, véspera do PMI Global Summit: as três línguas serviam a mesma
 * imagem, com o texto em português, e a descrição em inglês dizia "50+ researchers" com 84 membros
 * ativos no ar. Quem compartilhasse o link em inglês mostrava um cartão em português.
 *
 * O guard amarra a CONDIÇÃO (lang === 'en-US') ao RESULTADO (o caminho da imagem), com comentários
 * mascarados, e confere que as duas imagens existem com o tamanho que as meta tags declaram.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const LAYOUT = maskJsComments(readFileSync(resolve(ROOT, 'src/layouts/BaseLayout.astro'), 'utf8'));
const EN = readFileSync(resolve(ROOT, 'src/i18n/en-US.ts'), 'utf8');

function pngSize(rel) {
  const buf = readFileSync(resolve(ROOT, 'public', rel));
  assert.equal(buf.toString('ascii', 1, 4), 'PNG', `${rel} não é PNG`);
  return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
}

test('#2553: inglês => og-image-en.png; as outras línguas => og-image.png', () => {
  assert.match(
    LAYOUT,
    /const ogImage = new URL\(lang === 'en-US' \? '\/assets\/og-image-en\.png' : '\/assets\/og-image\.png', Astro\.url\)\.href;/,
    'a escolha da imagem da prévia pela língua mudou ou saiu',
  );
});

test('#2553: og:image e twitter:image leem a mesma escolha', () => {
  assert.match(LAYOUT, /<meta property="og:image" content=\{ogImage\} \/>/);
  assert.match(LAYOUT, /<meta name="twitter:image" content=\{ogImage\} \/>/);
});

test('#2553: as duas imagens existem com 1200x630, o tamanho que as meta tags declaram', () => {
  assert.match(LAYOUT, /<meta property="og:image:width" content="1200" \/>/);
  assert.match(LAYOUT, /<meta property="og:image:height" content="630" \/>/);
  for (const rel of ['assets/og-image.png', 'assets/og-image-en.png']) {
    assert.ok(existsSync(resolve(ROOT, 'public', rel)), `public/${rel} ausente`);
    assert.deepEqual(pngSize(rel), { w: 1200, h: 630 }, `public/${rel} fora de 1200x630`);
  }
});

test('#2553: a descrição em inglês não carrega contagem fixa de pesquisadores', () => {
  const m = EN.match(/'meta\.description':\s*'([^']+)'/);
  assert.ok(m, 'meta.description ausente em en-US');
  assert.doesNotMatch(m[1], /\d+\+?\s*researchers/i, `contagem fixa na descrição: "${m[1]}"`);
});
