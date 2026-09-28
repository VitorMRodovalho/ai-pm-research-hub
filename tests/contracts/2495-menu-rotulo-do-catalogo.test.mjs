/**
 * #2495: todo item da gaveta tem texto no mapa do Nav, lido do catálogo INTEIRO.
 *
 * O Nav monta o rótulo da gaveta por `i18n[toCamelKey(item.key)]`, e esse mapa (`jsI18n` em
 * Nav.astro) é escrito à mão. Item sem entrada renderiza a chave crua. Aconteceu no p195, na #1591
 * e de novo em 27/09/2026 ("nav.wiki" e "nav.myPoints"): o guard da #1591 afirmava um item só, pelo
 * nome, e ficava verde para todo o resto. Este lê src/lib/navigation.config.ts e cobre todo item,
 * presente e futuro. O texto pode ser outra chave que não o labelKey (attendance e admin usam
 * variantes de propósito); o que se exige é que exista e esteja nos 3 dicionários.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const CFG = readFileSync(resolve(ROOT, 'src/lib/navigation.config.ts'), 'utf8');
const NAV = readFileSync(resolve(ROOT, 'src/components/nav/Nav.astro'), 'utf8');
const DICTS = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => [l, readFileSync(resolve(ROOT, `src/i18n/${l}.ts`), 'utf8')]);

const start = NAV.indexOf('const jsI18n = JSON.stringify({');
const MAP = start >= 0 ? NAV.slice(start, NAV.indexOf('});', start)) : '';
const ITEMS = [...CFG.matchAll(/\{\s*key:\s*'([^']+)',\s*labelKey:\s*'([^']+)'([^\n]*)\}/g)]
  .map((m) => ({ key: m[1], labelKey: m[2], rest: m[3] }));
const camel = (k) => k.replace(/-([a-z])/g, (_, c) => c.toUpperCase());
const NA_GAVETA = ITEMS.filter((i) => /drawerSection:\s*'/.test(i.rest) && /section:\s*'(drawer|both)'/.test(i.rest));
const entrada = (k) => MAP.match(new RegExp(`\\b${camel(k)}:\\s*t\\('([^']+)'`))?.[1];

test('#2495 menu: o leitor enxerga o catálogo inteiro (item em várias linhas não escapa calado)', () => {
  assert.ok(start >= 0, 'achou o mapa jsI18n no Nav');
  const declarados = (CFG.match(/^\s*\{\s*key:/gm) || []).length;
  assert.equal(ITEMS.length, declarados, 'cada `{ key:` do catálogo foi lido como item');
  assert.ok(NA_GAVETA.length >= 30, `esperava 30 ou mais itens na gaveta, achou ${NA_GAVETA.length}`);
});

test('#2495 menu: todo item da gaveta tem texto no mapa do Nav, e a chave existe nos 3 dicionários', () => {
  const sem = NA_GAVETA.filter((i) => !entrada(i.key)).map((i) => i.key);
  assert.deepEqual(sem, [], `sem entrada no jsI18n, a gaveta mostraria a chave crua: ${sem.join(', ')}`);
  for (const i of NA_GAVETA) {
    const chave = entrada(i.key);
    for (const [lang, dict] of DICTS) assert.ok(dict.includes(`'${chave}':`), `${lang} sem '${chave}' (item ${i.key})`);
  }
});

test('#2495 menu: o Wiki está na barra principal, só para membro, com o próprio rótulo', () => {
  const wiki = ITEMS.find((i) => i.key === 'wiki');
  assert.ok(wiki, 'item wiki no catálogo');
  assert.match(wiki.rest, /navSlot:\s*'primary'/, 'na barra principal');
  assert.match(wiki.rest, /minTier:\s*'member'/, 'só para membro');
  assert.equal(entrada('wiki'), 'nav.wiki');
  assert.equal(entrada('my-points'), 'nav.myPoints');
});
