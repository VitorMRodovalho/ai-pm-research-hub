/**
 * #3028: editar um webinar pela tela não apaga o vínculo com o card do board.
 *
 * No ramo de edição, `upsert_webinar` grava `board_item_id = p_board_item_id`, sem `COALESCE`, e o parâmetro tem
 * `DEFAULT NULL`. A tela de `/admin/webinars` montava os parâmetros sem `p_board_item_id`, então toda edição gravava
 * `NULL`. A correção é na tela: o modal guarda o `board_item_id` do webinar aberto, que vem de `list_webinars_v2`, e o
 * salvar da edição o reenvia.
 *
 * O guard lê os corpos VIGENTES (`latestFunctionCapture`) das duas funções e amarra os três lados:
 * - o ramo de edição de `upsert_webinar` grava o vínculo direto do parâmetro (é por isso que a tela precisa reenviar);
 * - `list_webinars_v2` devolve `w.board_item_id` a todo leitor, fora do `CASE` que esconde o título do card;
 * - o modal toma o vínculo do webinar a cada abertura, e o ramo de edição do salvar o manda junto com o `p_id`.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const PAGINA = 'src/pages/admin/webinars.astro';
const pagina = () => maskJsComments(readFileSync(resolve(ROOT, PAGINA), 'utf8'));

function corpoDe(fonte, assinatura) {
  const i = fonte.indexOf(assinatura);
  assert.ok(i >= 0, `${PAGINA}: não tem ${assinatura}`);
  const fim = fonte.indexOf('\n  }\n', i);
  assert.ok(fim > i, `${PAGINA}: ${assinatura} sem fechamento`);
  return fonte.slice(i + assinatura.length, fim);
}

function vigente(nome) {
  const { file, block, body } = latestFunctionCapture(ROOT, nome);
  return { file, cabecalho: maskLineComments(block.slice(0, block.indexOf(body))), sql: maskLineComments(body) };
}

test('upsert_webinar: o ramo de edição grava board_item_id direto do parâmetro, que vale NULL quando omitido', () => {
  const { file, cabecalho, sql } = vigente('upsert_webinar');
  assert.match(cabecalho, /\bp_board_item_id uuid DEFAULT NULL::uuid\b/, `upsert_webinar (${file}): p_board_item_id não tem DEFAULT NULL`);
  const ini = sql.indexOf('IF p_id IS NOT NULL THEN');
  const fim = sql.indexOf('\n  ELSE\n', ini);
  assert.ok(ini >= 0 && fim > ini, `upsert_webinar (${file}): o ramo de edição não tem a forma que o guard lê`);
  const update = sql.slice(ini, fim).match(/\bUPDATE public\.webinars SET\b([\s\S]*?)\bWHERE id = p_id;/);
  assert.ok(update, `upsert_webinar (${file}): o ramo de edição não tem o UPDATE de webinars`);
  assert.match(update[1], /^\s*board_item_id = p_board_item_id\s*$/m,
    `upsert_webinar (${file}): a edição não grava mais board_item_id direto do parâmetro. ` +
      'Se o servidor passou a preservar o vínculo, reveja se a tela ainda precisa reenviá-lo (#3028).');
});

test('list_webinars_v2: devolve w.board_item_id a todo leitor, e a página carrega a lista dela', () => {
  const { file, sql } = vigente('list_webinars_v2');
  const colunas = sql.match(/\(\s*SELECT\b([\s\S]*?)\bFROM public\.webinars w\b/);
  assert.ok(colunas, `list_webinars_v2 (${file}): a lista de colunas não tem a forma que o guard lê`);
  assert.match(colunas[1], /(?:^|,)\s*w\.board_item_id\s*,/m,
    `list_webinars_v2 (${file}): w.board_item_id não sai como coluna própria, fora de CASE`);
  const reload = corpoDe(pagina(), 'async function reload() {');
  assert.match(reload, /const \{ data, error \} = await sb\.rpc\('list_webinars_v2', params\);[\s\S]*?\bALL_WEBINARS = Array\.isArray\(data\) \? data : /,
    'a página não carrega ALL_WEBINARS de list_webinars_v2');
});

test('webinars: o modal toma o board_item_id do webinar a cada abertura, e a edição o reenvia', () => {
  const src = pagina();
  assert.match(src, /^\s*let editingBoardItemId: string \| null = null;$/m, 'a página não declara editingBoardItemId');

  const abrir = corpoDe(src, 'function openModal(w?: any) {');
  const toma = abrir.search(/^ {4}editingBoardItemId = w\?\.board_item_id \?\? null;$/m);
  assert.ok(toma >= 0, 'openModal não toma editingBoardItemId de w.board_item_id, fora de condição');
  const ramo = abrir.search(/^ {4}if \(w\) \{$/m);
  assert.ok(ramo > toma, 'openModal toma o vínculo depois de decidir entre editar e criar');

  const salvar = corpoDe(src, 'async function saveWebinar() {');
  assert.match(salvar, /^\s*const id = \(document\.getElementById\('modal-id'\) as HTMLInputElement\)\.value \|\| undefined;$/m,
    'saveWebinar não lê o id do modal');
  assert.match(salvar, /\bif \(id\) \{\s*params\.p_id = id;\s*params\.p_board_item_id = editingBoardItemId;\s*\}/,
    'o ramo de edição de saveWebinar não reenvia o vínculo com o card');
  assert.match(salvar, /const \{ error \} = await sb\.rpc\('upsert_webinar', params\);/,
    'saveWebinar não chama upsert_webinar com os params que montou');
});
