/**
 * #2974: a lista de ações que abre o admin existe uma vez só, em `src/lib/permissions.ts`.
 *
 * Antes, `Nav.astro` mantinha uma cópia literal (`ADMIN_TIER_ACTIONS_INLINE`) com 10 das 13 ações. As páginas que
 * usam `window.__nucleoCanForAdminEntry` liam a cópia, e as ilhas que usam `canForAdminEntry()` liam a lista de
 * `permissions.ts`; em `/admin/vep-reconciliation` a casca da página e a ilha davam respostas diferentes para a mesma
 * pessoa. Decisão do GP (2026-11-04): valem as 13.
 *
 * O guard afirma, com comentários mascarados:
 *   1. em `Nav.astro`, o corpo de `__nucleoCanForAdminEntry` devolve `ADMIN_TIER_ACTIONS.some(...)`, e
 *      `ADMIN_TIER_ACTIONS` vem do import de `../../lib/permissions`;
 *   2. `Nav.astro` não tem array literal com ações de entrada (a cópia não volta com outro nome);
 *   3. em `permissions.ts`, `canForAdminEntry` devolve `ADMIN_TIER_ACTIONS.some(...)`, e a lista tem as 13, inclusive
 *      `view_finance`, `view_partner` e `view_aggregate_analytics`.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const read = (p) => maskJsComments(readFileSync(resolve(ROOT, p), 'utf8'));

/** O bloco `{ ... }` que começa no primeiro `{` depois de `marker`, por contagem de chaves. */
function blockAfter(src, marker) {
  const at = src.indexOf(marker);
  if (at < 0) return null;
  const open = src.indexOf('{', at + marker.length);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}' && --depth === 0) return src.slice(open, i + 1);
  }
  return null;
}

const nav = read('src/components/nav/Nav.astro');
const perms = read('src/lib/permissions.ts');

const LISTA = perms.match(/export const ADMIN_TIER_ACTIONS\s*=\s*\[([^\]]*)\]/);
const ACOES = LISTA ? [...LISTA[1].matchAll(/'([a-z_]+)'/g)].map((m) => m[1]) : [];

test('permissions.ts: a lista de entrada tem as 13 ações decididas', () => {
  assert.ok(LISTA, 'export const ADMIN_TIER_ACTIONS não encontrado');
  assert.equal(new Set(ACOES).size, 13, `esperadas 13 ações distintas, achadas ${JSON.stringify(ACOES)}`);
  for (const a of ['view_finance', 'view_partner', 'view_aggregate_analytics']) {
    assert.ok(ACOES.includes(a), `${a} saiu da lista de entrada`);
  }
});

test('permissions.ts: canForAdminEntry decide pela lista', () => {
  const body = blockAfter(perms, 'export function canForAdminEntry(');
  assert.ok(body, 'canForAdminEntry não encontrada');
  assert.match(body, /return ADMIN_TIER_ACTIONS\.some\(/);
});

test('Nav.astro: __nucleoCanForAdminEntry decide pela lista importada de permissions.ts', () => {
  assert.match(nav, /import\s*\{[^}]*\bADMIN_TIER_ACTIONS\b[^}]*\}\s*from\s*'\.\.\/\.\.\/lib\/permissions'/);
  const body = blockAfter(nav, '__nucleoCanForAdminEntry = () =>');
  assert.ok(body, '__nucleoCanForAdminEntry não encontrada');
  assert.match(body, /return ADMIN_TIER_ACTIONS\.some\(/);
});

test('Nav.astro: nenhum array literal com ações de entrada', () => {
  for (const m of nav.matchAll(/\[([^\[\]]*)\]/g)) {
    const itens = [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]).filter((x) => ACOES.includes(x));
    assert.ok(itens.length < 3, `cópia literal de ações de entrada em Nav.astro: ${JSON.stringify(itens)}`);
  }
  assert.ok(ACOES.length === 13, 'controle: a lista de referência foi lida');
});
