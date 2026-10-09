/**
 * advance_board_item_curation: paridade com as demais RPCs da curadoria (#785, ADR-0105; #2447).
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. o portao de visibilidade responde com a mesma mensagem do item inexistente;
 *   B. toda acao aceita pelo corpo passa pela trava de artefato publicavel;
 *   C. os dois portoes vem antes de qualquer acao e de qualquer escrita.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const body = maskLineComments(latestFunctionCapture(process.cwd(), 'advance_board_item_curation').body);
const NOTFOUND = /IF NOT FOUND THEN\s+RAISE EXCEPTION '([^']+)';\s+END IF;/;
const VIS = /IF NOT public\.rls_can_see_board\(v_board_id\) THEN\s+RAISE EXCEPTION '([^']+)';\s+END IF;/;
const PUB = /IF p_action IN \(([^)]*)\)\s+AND NOT public\._board_item_needs_curation\(p_item_id\) THEN\s+RAISE EXCEPTION 'Revisão e curadoria valem só para artefato publicável/;

function at(re, label) {
  const i = body.search(re);
  assert.ok(i >= 0, `${label} ausente do corpo vigente`);
  return i;
}

test('A. o portao de visibilidade responde com a mesma mensagem do inexistente', () => {
  const nf = body.match(NOTFOUND);
  const vis = body.match(VIS);
  assert.ok(nf && vis, 'os dois RAISE existem');
  assert.equal(vis[1], nf[1], 'mensagens identicas');
  assert.match(body, /bi\.board_id\s+INTO v_curation, v_assignee, v_reviewer, v_tribe_id, v_board_id/, 'o board e o do proprio card');
});

test('B. toda acao aceita pelo corpo passa pela trava de artefato publicavel', () => {
  const pub = body.match(PUB);
  assert.ok(pub, 'trava de artefato presente');
  const listed = [...pub[1].matchAll(/'([a-z_]+)'/g)].map((m) => m[1]).sort();
  // toda comparacao de p_action no corpo, em qualquer forma (IF/ELSIF/CASE/IN)
  const used = new Set();
  for (const m of body.matchAll(/p_action\s*=\s*'([a-z_]+)'/g)) used.add(m[1]);
  for (const m of body.matchAll(/WHEN\s+'([a-z_]+)'/g)) used.add(m[1]);
  assert.ok(used.size >= 3, `so ${used.size} acoes lidas`);
  assert.deepEqual(listed, [...used].sort(), 'a trava cobre exatamente as acoes do corpo');
});

test('C. os portoes vem antes de qualquer acao e escrita', () => {
  const nf = at(NOTFOUND, 'NOT FOUND');
  const vis = at(VIS, 'visibilidade');
  const pub = at(PUB, 'trava de artefato');
  const firstAction = at(/IF p_action = '[a-z_]+' THEN/, 'primeira acao');
  const firstWrite = at(/\bUPDATE public\.board_items\b/, 'primeira escrita');
  assert.ok(nf < vis && vis < pub && pub < firstAction && pub < firstWrite);
});
