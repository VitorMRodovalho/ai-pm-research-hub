/**
 * #2395 - um `.select()` que pede coluna inexistente nao falha alto: o PostgREST devolve erro,
 * quem le faz `data ?? null`, e a resposta sai como AUSENCIA com `ok:true`.
 *
 * O caso que originou: `get_board_or_initiative_context` pedia `project_boards.select("id, title")`
 * numa tabela cuja coluna e `board_name`. Exercido em producao em 2026-09-20 contra uma iniciativa
 * com board ativo: a ferramenta respondeu `"board": null` e `"sem board"`, com zero warnings. E
 * como `board?.id` governa a busca de cards, o `detail_level:'standard'` devolvia 0 card para as
 * 33 iniciativas que tem board.
 *
 * O catalogo de colunas NAO e lista escrita a mao: sai de `src/lib/database.gen.ts`, que o gate
 * `gen-types-drift` mantem colado no schema vivo. Lista a mao apodrece na primeira coluna nova.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const RAIZ = new URL('../../', import.meta.url).pathname;
const GEN = join(RAIZ, 'src/lib/database.gen.ts');

/**
 * Divida conhecida em 2026-09-20, confirmada contra `information_schema` (tabela existe, coluna
 * nao). O baseline NOMEIA cada ocupante: contagem sozinha tem ponto cego do proprio tamanho, e um
 * defeito novo que entra no mesmo instante que um antigo sai passaria batido.
 * Ao consertar um destes, REMOVA a linha daqui - o teste reprova se a divida some sem baixa.
 */
const BASELINE = [
  'src/pages/admin/governance/ip-ratification.astro :: approval_chains.title',
  'supabase/functions/send-allocation-notify/index.ts :: members.selected_tribe_id',
  'supabase/functions/send-allocation-notify/index.ts :: members.fixed_tribe_id',
  'supabase/functions/send-campaign/index.ts :: tribes.chapter',
  'supabase/functions/sync-knowledge-insights/index.ts :: knowledge_chunks.source',
  'supabase/functions/sync-knowledge-insights/index.ts :: knowledge_chunks.title',
  'supabase/functions/sync-knowledge-insights/index.ts :: knowledge_chunks.source_url',
  'supabase/functions/sync-knowledge-insights/index.ts :: knowledge_chunks.tags',
  'supabase/functions/sync-knowledge-insights/index.ts :: knowledge_chunks.is_active',
];

function catalogo() {
  const gen = readFileSync(GEN, 'utf8');
  const mapa = new Map();
  const re = /^ {6}([a-z0-9_]+): \{\n {8}Row: \{\n([\s\S]*?)\n {8}\}/gm;
  let m;
  while ((m = re.exec(gen))) {
    const cols = new Set([...m[2].matchAll(/^ {10}([a-z0-9_]+)\??:/gm)].map((x) => x[1]));
    if (cols.size) mapa.set(m[1], cols);
  }
  return mapa;
}

function varrer(dir, out = []) {
  for (const e of readdirSync(join(RAIZ, dir))) {
    if (e === 'node_modules' || e === '.git' || e === 'dist') continue;
    const rel = `${dir}/${e}`;
    if (statSync(join(RAIZ, rel)).isDirectory()) varrer(rel, out);
    else if (/\.(ts|tsx|astro|mjs)$/.test(e) && !rel.endsWith('database.gen.ts')) out.push(rel);
  }
  return out;
}

function violacoes() {
  const cat = catalogo();
  const arquivos = [...varrer('src'), ...varrer('supabase/functions')];
  const achados = [];
  let selects = 0;
  for (const rel of arquivos) {
    const src = maskJsComments(readFileSync(join(RAIZ, rel), 'utf8'));
    const re = /\.from\(\s*["'`]([a-z0-9_]+)["'`]\s*\)\s*\n?\s*\.select\(\s*["'`]([^"'`]*)["'`]/g;
    let s;
    while ((s = re.exec(src))) {
      const [, tabela, campos] = s;
      const cols = cat.get(tabela);
      if (!cols) continue;
      selects++;
      for (const bruto of campos.split(',')) {
        const t = bruto.trim();
        // embutidos (`a:b(c)`), `*`, modificadores e caminhos ficam fora: o catalogo nao os descreve
        if (!t || t === '*' || /[():!.]/.test(t)) continue;
        if (!/^[a-z0-9_]+$/.test(t)) continue;
        if (!cols.has(t)) achados.push(`${rel} :: ${tabela}.${t}`);
      }
    }
  }
  return { achados, selects, arquivos: arquivos.length, tabelas: cat.size };
}

test('#2395 A - denominador nao e vazio: o catalogo e a varredura enxergam o repositorio', () => {
  const { selects, arquivos, tabelas } = violacoes();
  assert.ok(tabelas > 100, `catalogo com ${tabelas} tabelas: parser do database.gen.ts quebrou`);
  assert.ok(arquivos > 300, `so ${arquivos} arquivos varridos: a varredura encolheu`);
  assert.ok(selects > 100, `so ${selects} selects validaveis: o regex deixou de casar`);
});

test('#2395 B - nenhum `.select()` NOVO pede coluna fora do catalogo', () => {
  const { achados } = violacoes();
  const base = new Set(BASELINE);
  const novos = achados.filter((a) => !base.has(a));
  assert.deepEqual(novos, [], `select(s) pedindo coluna inexistente:\n  ${novos.join('\n  ')}`);
});

test('#2395 C - a divida do baseline nao some sem baixa (diferenca simetrica, nao contagem)', () => {
  const { achados } = violacoes();
  const vivos = new Set(achados);
  const sumiram = BASELINE.filter((b) => !vivos.has(b));
  assert.deepEqual(sumiram, [], `consertado(s) mas ainda no BASELINE - remova a(s) linha(s):\n  ${sumiram.join('\n  ')}`);
});

test('#2395 D - `project_boards` nao aparece em nenhuma violacao (o caso da issue)', () => {
  const { achados } = violacoes();
  const pb = achados.filter((a) => a.includes('project_boards.'));
  assert.deepEqual(pb, [], `project_boards voltou a pedir coluna inexistente:\n  ${pb.join('\n  ')}`);
});

test('#2395 E - o erro do board TEM leitor, e o leitor RETORNA antes de publicar ausencia', () => {
  const src = maskJsComments(
    readFileSync(join(RAIZ, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8'),
  );
  const ini = src.indexOf('const [initRes, boardRes] = await Promise.all([');
  assert.notEqual(ini, -1, 'bloco de get_board_or_initiative_context nao encontrado');
  const fim = src.indexOf('const board = boardRes.data ?? null;', ini);
  assert.notEqual(fim, -1, '`const board = boardRes.data ?? null` sumiu: reveja este guard');
  const bloco = src.slice(ini, fim);
  // condicao AMARRADA ao resultado: nao basta a string `boardRes.error` existir no corpo
  assert.match(
    bloco,
    /if\s*\(\s*boardRes\.error\s*\)\s*\{[\s\S]*?return ok\(buildSemanticError\(/,
    '`boardRes.error` precisa decidir um retorno ANTES de `const board = ... ?? null`, senao o erro vira "sem board"',
  );
});
