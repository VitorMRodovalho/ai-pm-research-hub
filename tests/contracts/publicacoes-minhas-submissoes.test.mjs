/**
 * "Minhas submissões" em /publications: o modal do pesquisador e a lista do que ele criou.
 *
 * Defeito medido em 17/11/2026: o modal "+ Nova Submissão" mostrava chaves cruas (t() devolve a
 * própria chave quando ela falta), salvava sem retorno (a página não montava o Toast, então
 * window.toast era undefined) e a lista "Minhas submissões" nunca mostrava o que a pessoa criou,
 * porque o filtro lia primary_author_id e get_publication_submissions não devolvia esse campo.
 * Efeito: o mesmo rascunho salvo três vezes por quem achou que tinha falhado.
 *
 * O QUE ESTE GUARD AFIRMA:
 *   A. cada tipo de alvo do modal é valor do enum submission_target_type com rótulo
 *      publications.target.<valor> nos 3 dicionários (as chaves literais da página estão no guard geral
 *      i18n-chave-de-astro-existe-nos-3-dicionarios);
 *   B. a página roda dentro do BaseLayout, que monta o Toast que o envio chama;
 *   C. todo campo que os filtros "minhas" leem da lista sai de get_publication_submissions (captura
 *      VIGENTE), e a coluna primary_author_id do RETURNS TABLE recebe ps.primary_author_id na mesma
 *      posição do SELECT;
 *   D. o envio não sai duas vezes: a trava é conferida antes da chamada, o botão é desabilitado antes
 *      dela, e os dois voltam no finally.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const PAGE = read('src/pages/publications.astro');
const WORKSPACE = read('src/pages/workspace.astro');
const DICTS = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => [l, read(`src/i18n/${l}.ts`)]);
const hasKey = (dict, key) => dict.includes(`'${key}':`);

/** Corpo de uma função/handler, do marcador até a chave que fecha o bloco aberto nele. */
function blockFrom(src, marker) {
  const start = src.indexOf(marker);
  assert.ok(start >= 0, `marcador não encontrado: ${marker}`);
  const open = src.indexOf('{', start + marker.length - 1);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}' && --depth === 0) return src.slice(start, i + 1);
  }
  throw new Error(`bloco sem fechamento: ${marker}`);
}

test('A. tipos de alvo do modal: valores do enum, rótulo nos 3 dicionários, sem texto fixo', () => {
  const arr = PAGE.match(/const TARGET_TYPES = \[([^\]]+)\] as const;/);
  assert.ok(arr, 'TARGET_TYPES declarado no frontmatter');
  const values = [...arr[1].matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
  assert.ok(values.length > 0);

  // O <select> do modal gera as opções a partir de TARGET_TYPES com a chave publications.target.<valor>.
  const select = PAGE.slice(PAGE.indexOf('<select name="target_type"'), PAGE.indexOf('</select>', PAGE.indexOf('<select name="target_type"')));
  assert.match(select, /\{TARGET_TYPES\.map\(\(v\) => <option value=\{v\}>\{t\(`publications\.target\.\$\{v\}`, lang\)\}<\/option>\)\}/);
  assert.doesNotMatch(select, /<option value="[a-z_]+">[^{<]/, 'nenhuma opção com rótulo fixo');

  const enumSql = read('supabase/migrations/20260319100043_w139_publication_submissions.sql');
  const created = enumSql.match(/CREATE TYPE public\.submission_target_type AS ENUM \(([^)]+)\)/);
  assert.ok(created, 'definição do enum encontrada');
  const enumValues = new Set([...created[1].matchAll(/'([a-z_]+)'/g)].map((m) => m[1]));
  enumValues.add('linkedin_newsletter'); // 20260516910000 ADD VALUE
  const faltam = [];
  for (const v of values) {
    if (!enumValues.has(v)) faltam.push(`fora do enum: ${v}`);
    for (const [l, d] of DICTS) if (!hasKey(d, `publications.target.${v}`)) faltam.push(`${l}: publications.target.${v}`);
  }
  assert.deepEqual(faltam, []);
});

test('B. a página roda dentro do BaseLayout, que monta o Toast que o envio chama', () => {
  // O Toast é montado só no BaseLayout desde 17/11/2026; a regra geral (todo chamador coberto por um
  // layout que o garante) está em 1973-o-aviso-chega-a-tela. Aqui, o caso desta página.
  assert.match(PAGE, /^import BaseLayout from '\.\.\/layouts\/BaseLayout\.astro';$/m, 'import do BaseLayout');
  assert.match(PAGE, /^<BaseLayout [^>]*>[\s\S]*^<\/BaseLayout>$/m, 'a página renderiza o BaseLayout');
  const layout = read('src/layouts/BaseLayout.astro');
  const body = layout.slice(layout.indexOf('<body'), layout.indexOf('</body>'));
  assert.match(body, /^\s*<Toast \/>\s*$/m, 'o BaseLayout monta o Toast numa linha própria');
});

const RPC = maskLineComments(latestFunctionCapture(ROOT, 'get_publication_submissions').block);

function rpcColumns() {
  const m = RPC.match(/RETURNS TABLE\(([^)]*)\)/);
  assert.ok(m, 'RETURNS TABLE');
  return m[1].split(',').map((c) => c.trim().split(/\s+/)[0]);
}

function rpcSelectItems() {
  const m = RPC.match(/RETURN QUERY\s+SELECT\s+([\s\S]*?)\s+FROM public\.publication_submissions ps/);
  assert.ok(m, 'SELECT da RETURN QUERY');
  return m[1].split(',').map((c) => c.trim().replace(/\s+AS\s+\w+$/i, ''));
}

test('C. primary_author_id do retorno recebe ps.primary_author_id na mesma posição', () => {
  const cols = rpcColumns();
  const items = rpcSelectItems();
  assert.equal(items.length, cols.length, 'SELECT e RETURNS TABLE com o mesmo número de colunas');
  const i = cols.indexOf('primary_author_id');
  assert.ok(i >= 0, 'RETURNS TABLE devolve primary_author_id');
  assert.equal(items[i], 'ps.primary_author_id', 'a posição de primary_author_id lê ps.primary_author_id');
});

for (const [nome, src, marker] of [
  ['publications.astro loadMySubmissions', PAGE, 'const mySubs = (data || []).filter('],
  ['workspace.astro Minhas publicações', WORKSPACE, 'const mySubs = (allSubs || []).filter('],
]) {
  test(`C. ${nome}: o filtro só lê campos que a lista devolve, e compara o autor com quem está logado`, () => {
    const js = maskJsComments(src);
    const start = js.indexOf(marker);
    assert.ok(start >= 0, 'filtro encontrado');
    const filtro = js.slice(start, js.indexOf(';', start) + 1);
    assert.match(filtro, /\(s: any\) => s\.primary_author_id === (myId|member\.id)\)/, 'filtro compara primary_author_id com o membro logado');
    const cols = new Set(rpcColumns());
    const lidos = [...filtro.matchAll(/\bs\.(\w+)/g)].map((m) => m[1]);
    assert.deepEqual(lidos.filter((f) => !cols.has(f)), [], 'campo lido pelo filtro e não devolvido pela função');
  });
}

test('D. envio único: trava antes da chamada, botão desabilitado antes, os dois voltam no finally', () => {
  const js = maskJsComments(PAGE);
  const h = blockFrom(js, "document.getElementById('my-new-form')?.addEventListener('submit', async (e) => {");
  const pos = (re, what) => { const m = h.match(re); assert.ok(m, what); return m.index; };
  const guard = pos(/if \(creatingSubmission\) return;/, 'retorna se já há envio em voo');
  const lock = pos(/creatingSubmission = true;/, 'liga a trava');
  const disable = pos(/if \(submitBtn\) submitBtn\.disabled = true;/, 'desabilita o botão');
  const call = pos(/sb\.rpc\('create_publication_submission'/, 'chamada de criação');
  const fin = pos(/\}\s*finally\s*\{\s*creatingSubmission = false;\s*if \(submitBtn\) submitBtn\.disabled = false;\s*\}/, 'finally solta trava e botão');
  assert.ok(guard < lock && lock < call && disable < call && call < fin, 'ordem: trava, botão, chamada, finally');
  assert.match(js, /id="my-new-submit"/, 'o botão do formulário tem o id que o handler desabilita');
});
