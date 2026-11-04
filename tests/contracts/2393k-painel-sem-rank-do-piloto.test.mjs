/**
 * Contract: #2393, fatia A5 (ADR-0134) — o painel da gestão não mostra ranking que o piloto não tem.
 *
 *   G5: a coluna de rank objetivo não mostra posição na candidatura piloto. O painel numera o piloto na sua
 *       própria partição, ordenada por nota nula, e isso parecia ranking sem avaliação nenhuma.
 *   G6: o aviso "Rankings vazios" conta só a candidatura da avaliação geral, porque o recálculo exclui o piloto
 *       e o aviso mandaria recalcular algo que nunca terá rank.
 * Camada S (estática): cada asserção casa a condição com o resultado no trecho que decide.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const S = maskJsComments(readFileSync(resolve(process.cwd(), 'src/pages/admin/selection.astro'), 'utf8')).replace(/\s+/g, ' ');

test('#2393k G5: a candidatura piloto não ganha posição na coluna de rank objetivo', () => {
  assert.match(S,
    /title="\$\{esc\(isPilotRow\(r\) \? T\.pilotBadgeHint : \(T\.colObjectiveRankHint \|\| ''\)\)\}">\$\{r\.objective_rank != null && !isPilotRow\(r\) \? `#\$\{r\.objective_rank\}` : '<span class="text-\[var\(--text-muted\)\]">—<\/span>'\}<\/td>/,
    'a coluna de rank voltou a numerar a candidatura piloto');
});

test('#2393k G6: o aviso de rankings vazios conta só a avaliação geral', () => {
  const ini = S.indexOf('function renderRankEmptyAlert() {');
  assert.ok(ini >= 0, 'a função do aviso sumiu');
  const corpo = S.slice(ini, S.indexOf('function ', ini + 10));
  assert.match(corpo,
    /const comRank = filteredRows\.filter\(\(r: any\) => !isPilotRow\(r\)\); if \(comRank\.length < 5\) \{ alertEl\.classList\.add\('hidden'\); return; \} const noRank = comRank\.filter\(/,
    'o aviso voltou a contar a candidatura piloto');
  assert.match(corpo, /const pct = \(noRank \/ comRank\.length\) \* 100;/, 'a porcentagem voltou a usar a base com o piloto');
  assert.doesNotMatch(corpo, /filteredRows\.length/, 'o aviso ainda usa o total com o piloto em algum ponto');
});
