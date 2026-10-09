/**
 * complete_leader_review: paridade de visibilidade com as demais RPCs da curadoria (#785, ADR-0105).
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. o portao de visibilidade responde com a mesma mensagem do item inexistente;
 *   B. o portao vem logo depois da busca, colado a ela, antes da etapa, da autoridade e da escrita.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const body = maskLineComments(latestFunctionCapture(process.cwd(), 'complete_leader_review').body);
const LOOKUP = /SELECT \* INTO v_item FROM public\.board_items WHERE id = p_item_id;\s+IF NOT FOUND THEN RAISE EXCEPTION 'Item not found: %', p_item_id; END IF;/;
const GATE = /IF NOT public\.rls_can_see_board\(v_item\.board_id\) THEN\s+RAISE EXCEPTION 'Item not found: %', p_item_id;\s+END IF;/;

test('A. o portao de visibilidade responde com a mesma mensagem do inexistente', () => {
  const nf = body.match(/IF NOT FOUND THEN RAISE EXCEPTION '([^']+)', p_item_id; END IF;/);
  const vis = body.match(/IF NOT public\.rls_can_see_board\(v_item\.board_id\) THEN\s+RAISE EXCEPTION '([^']+)', p_item_id;\s+END IF;/);
  assert.ok(nf && vis, 'os dois RAISE existem');
  assert.equal(vis[1], nf[1], 'mensagens identicas');
});

test('B. o portao vem colado a busca, antes da etapa, da autoridade e da escrita', () => {
  // busca, portao e checagem de etapa em sequencia contigua: o portao nao pode estar num ramo morto
  assert.match(body,
    /SELECT \* INTO v_item FROM public\.board_items WHERE id = p_item_id;\s+IF NOT FOUND THEN RAISE EXCEPTION 'Item not found: %', p_item_id; END IF;\s+IF NOT public\.rls_can_see_board\(v_item\.board_id\) THEN\s+RAISE EXCEPTION 'Item not found: %', p_item_id;\s+END IF;\s+IF v_item\.curation_status NOT IN \('leader_review', 'draft'\) THEN/);
  const gate = body.search(/IF NOT public\.rls_can_see_board\(v_item\.board_id\) THEN/);
  const authority = body.indexOf("RAISE EXCEPTION 'Leader review requires tribe leadership");
  const write = body.search(/\bUPDATE public\.board_items\b/);
  assert.ok(gate >= 0 && authority >= 0 && write >= 0, 'ancoras ausentes');
  assert.ok(gate < authority && gate < write);
});
