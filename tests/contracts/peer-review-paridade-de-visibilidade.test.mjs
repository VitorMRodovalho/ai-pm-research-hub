/**
 * complete_peer_review: paridade com as demais RPCs da curadoria (#785, ADR-0105).
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. o portao de visibilidade responde com a mesma mensagem do item inexistente;
 *   B. o portao vem colado a busca, antes da etapa, da trava de artefato, da autoridade e da escrita.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const body = maskLineComments(latestFunctionCapture(process.cwd(), 'complete_peer_review').body);

test('A. o portao de visibilidade responde com a mesma mensagem do inexistente', () => {
  const nf = body.match(/IF NOT FOUND THEN RAISE EXCEPTION '([^']+)', p_item_id; END IF;/);
  const vis = body.match(/IF NOT public\.rls_can_see_board\(v_item\.board_id\) THEN\s+RAISE EXCEPTION '([^']+)', p_item_id;\s+END IF;/);
  assert.ok(nf && vis, 'os dois RAISE existem');
  assert.equal(vis[1], nf[1], 'mensagens identicas');
});

test('B. o portao vem colado a busca, antes do resto e da escrita', () => {
  assert.match(body,
    /SELECT \* INTO v_item FROM public\.board_items WHERE id = p_item_id;\s+IF NOT FOUND THEN RAISE EXCEPTION 'Item not found: %', p_item_id; END IF;\s+IF NOT public\.rls_can_see_board\(v_item\.board_id\) THEN\s+RAISE EXCEPTION 'Item not found: %', p_item_id;\s+END IF;\s+IF v_item\.curation_status NOT IN \('draft', 'peer_review'\) THEN/);
  const gate = body.search(/IF NOT public\.rls_can_see_board\(v_item\.board_id\) THEN/);
  const artifact = body.search(/IF NOT public\._board_item_needs_curation\(p_item_id\) THEN/);
  const authority = body.indexOf("RAISE EXCEPTION 'Requires authorship");
  const write = body.search(/\bUPDATE public\.board_items\b/);
  assert.ok([gate, artifact, authority, write].every((i) => i >= 0), 'ancoras ausentes');
  assert.ok(gate < artifact && gate < authority && gate < write);
});
