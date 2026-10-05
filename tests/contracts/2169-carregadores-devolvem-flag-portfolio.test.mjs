/**
 * Contract #2169: a marcação de entregável de portfólio sobrevive ao recarregar a página.
 *
 * DEFEITO: a caixa "Entregável reportável" do card (CardDetail) e o selo do kanban (BoardKanban)
 * leem `is_portfolio_item` da resposta do carregador do quadro. Os três carregadores
 * (get_board, list_board_items, list_legacy_board_items_for_tribe) não devolviam o campo, então a
 * marcação sumia da tela depois do recarregamento, com o valor certo gravado no banco. Relatado
 * por duas tribos na reunião de liderança de 20/08/2026. Medido em 05/10/2026: get_board devolvia
 * 39 cards de um quadro de tribo, nenhum com a chave is_portfolio_item.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. Banco (estático): a captura VIGENTE de cada carregador (latestFunctionCapture, #1932) devolve
 *      o campo ligado à coluna do mesmo nome, e o portão de cada um continua no lugar.
 *      get_board_by_domain delega para get_board, então recebe o campo junto.
 *   B. Tela (estático): a caixa e o selo leem a mesma chave, e a ilha do kanban da tribo repassa a
 *      linha inteira, sem montar o card campo a campo.
 *
 * O guard não exerce a tela nem a função viva: o corpo vivo é conferido contra a captura pelo
 * Phase C (rpc-body-drift), e a resposta foi exercida na sessão que aplicou a migration.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const cap = (name) => maskLineComments(latestFunctionCapture(ROOT, name).block);
const read = (p) => maskJsComments(readFileSync(join(ROOT, p), 'utf8'));

/** A lista de colunas devolvida por um carregador row_to_json, até o FROM principal. */
function selectList(block) {
  const i = block.indexOf('SELECT row_to_json(r)');
  const j = block.indexOf('FROM public.board_items bi') >= 0 ? block.indexOf('FROM public.board_items bi') : block.indexOf('FROM board_items bi');
  assert.ok(i >= 0 && j > i, 'o carregador monta a resposta com row_to_json sobre board_items bi');
  return block.slice(i, j);
}

// ── A. Banco ─────────────────────────────────────────────────────────────────────

test('A1: get_board devolve is_portfolio_item ligado à coluna, dentro do objeto de cada card', () => {
  const b = cap('get_board');
  const items = b.slice(b.indexOf("'items', ("));
  assert.match(items, /'is_portfolio_item', i\.is_portfolio_item,/, 'a chave vem de i.is_portfolio_item');
  assert.match(b, /IF NOT public\.rls_can_see_board\(p_board_id\) THEN\s+RETURN NULL;\s+END IF;/, 'o portão de quadro confidencial segue no topo');
});

test('A2: list_board_items devolve bi.is_portfolio_item', () => {
  const b = cap('list_board_items');
  assert.match(selectList(b), /\bbi\.is_portfolio_item,/, 'a coluna está na lista devolvida');
  assert.match(b, /IF NOT public\.rls_can_see_board\(p_board_id\) THEN RETURN; END IF;/, 'o portão de quadro confidencial segue no topo');
});

test('A3: list_legacy_board_items_for_tribe devolve bi.is_portfolio_item, com os portões intactos', () => {
  const b = cap('list_legacy_board_items_for_tribe');
  assert.match(selectList(b), /\bbi\.is_portfolio_item,/, 'a coluna está na lista devolvida');
  assert.match(b, /IF NOT \(\s*v_caller_id = v_leader_id\s+OR public\.can_by_member\(v_caller_id, 'manage_member'\)\s*\) THEN\s+RETURN;/, 'só o líder ou quem gere membros lê');
  assert.match(b, /AND public\.rls_can_see_board\(bi\.board_id\)/, 'cada card passa pelo portão de quadro confidencial');
});

test('A4: get_board_by_domain delega para get_board', () => {
  const b = cap('get_board_by_domain');
  assert.match(b, /RETURN public\.get_board\(v_board_id\);/, 'o quadro por domínio é o mesmo get_board');
});

// ── B. Tela ──────────────────────────────────────────────────────────────────────

test('B1: a caixa do card e o selo do kanban leem a mesma chave', () => {
  const card = read('src/components/board/CardDetail.tsx');
  assert.match(card, /checked=\{!!item\.is_portfolio_item\}/, 'a caixa lê item.is_portfolio_item');
  assert.match(card, /onUpdate\(\{ is_portfolio_item: e\.target\.checked \}\)/, 'e grava a mesma chave');
  const kanban = read('src/components/board/BoardKanban.tsx');
  assert.match(kanban, /\{item\.is_portfolio_item && \(/, 'o selo lê item.is_portfolio_item');
});

test('B2: o kanban da tribo repassa a linha inteira de list_board_items', () => {
  const src = read('src/components/boards/TribeKanbanIsland.tsx');
  assert.match(src, /sb\.rpc\('list_board_items', \{ p_board_id: activeBoard\.id, p_status: null \}\)/, 'a ilha lê list_board_items');
  assert.match(src, /raw\.map\(\(row: any\) => \(\{ \.\.\.row, curation_status:/, 'cada card é a linha inteira, sem descartar campo');
});
