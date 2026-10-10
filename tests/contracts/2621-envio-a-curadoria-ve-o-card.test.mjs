/**
 * #2621 (aprovado pelo GP em 09/10/2026): submit_for_curation exige que quem envia VEJA o card e,
 * no caminho do lider de tribo, que lidere a iniciativa do card.
 *
 * Medido em 09/10: a RPC nao tinha o portao de visibilidade (#785, ADR-0105) que as irmas de
 * curadoria tem, e o ramo do lider (ADR-0041 Path Y) testava so operational_role = 'tribe_leader',
 * global. O portao de visibilidade sozinho nao barra lider de outra tribo: card de iniciativa nao
 * confidencial e visivel a todo membro. Por isso o escopo e uma segunda trava.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. card invisivel responde como item ausente, antes de qualquer escrita;
 *   B. sem governanca, so quem lidera (engajamento ativo role = 'leader') a iniciativa do board envia,
 *      antes de qualquer escrita; governanca segue sem escopo;
 *   C. o primeiro portao continua governanca OU tribe_leader (nada se amplia);
 *   D. toda mensagem RAISE da RPC casa um padrao traduzido da tela (REVIEW_ERRORS, #2456).
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const body = maskLineComments(latestFunctionCapture(ROOT, 'submit_for_curation').body);
const card = maskJsComments(readFileSync(resolve(ROOT, 'src/components/board/CardDetail.tsx'), 'utf8'));

const WRITE = body.indexOf('UPDATE board_items');
const LOOKUP = body.indexOf('SELECT * INTO v_item FROM board_items WHERE id = p_item_id;');

test('a RPC escreve e acha o item (ancoras do guard)', () => {
  assert.ok(WRITE !== -1, 'UPDATE board_items ausente');
  assert.ok(LOOKUP !== -1 && LOOKUP < WRITE, 'busca do item ausente ou depois da escrita');
});

test('A. card invisivel responde como item ausente, antes de escrever', () => {
  const m = body.match(/IF NOT public\.rls_can_see_board\(v_item\.board_id\) THEN\s+RAISE EXCEPTION 'Item not found';\s+END IF;/);
  assert.ok(m, 'portao de visibilidade amarrado ao RAISE de item ausente');
  assert.ok(m.index > LOOKUP && m.index < WRITE, 'o portao fica entre a busca do item e a escrita');
  // sem oraculo: card invisivel e card inexistente respondem com a MESMA mensagem
  assert.match(body, /SELECT \* INTO v_item FROM board_items WHERE id = p_item_id;\s+IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;/,
    'item inexistente responde com o mesmo texto do portao de visibilidade');
});

test('B. sem governanca, so o lider da iniciativa do card envia, antes de escrever', () => {
  const m = body.match(/IF NOT v_is_gov AND NOT EXISTS \(\s+SELECT 1\s+FROM project_boards pb\s+JOIN engagements e ON e\.initiative_id = pb\.initiative_id\s+JOIN persons p ON p\.id = e\.person_id\s+WHERE pb\.id = v_item\.board_id\s+AND e\.status = 'active'\s+AND e\.role = 'leader'\s+AND p\.auth_id = auth\.uid\(\)\s+\) THEN\s+RAISE EXCEPTION 'Requires tribe leadership of the card''s initiative or participate_in_governance_review';/);
  assert.ok(m, 'escopo do lider amarrado ao RAISE');
  assert.ok(m.index > LOOKUP && m.index < WRITE, 'o escopo fica entre a busca do item e a escrita');
});

test('C. o primeiro portao continua governanca OU tribe_leader, antes de buscar o item', () => {
  const at = body.indexOf("RAISE EXCEPTION 'Requires participate_in_governance_review or tribe_leader';");
  assert.ok(at !== -1 && at < LOOKUP, 'o portao de papel vem antes da busca do item (nao depende do card)');
  assert.match(body,
    /v_is_gov := public\.can_by_member\(v_caller\.id, 'participate_in_governance_review'\);\s+IF NOT \(\s+v_is_gov\s+OR v_caller\.operational_role = 'tribe_leader'\s+\) THEN\s+RAISE EXCEPTION 'Requires participate_in_governance_review or tribe_leader';/);
});

test('D. toda mensagem da RPC tem traducao na tela', () => {
  const bloco = (card.match(/const REVIEW_ERRORS: Array<\[RegExp, string\]> = \[([\s\S]*?)\n\];/) || [])[1] || '';
  const pads = [...bloco.matchAll(/\[\/(.+?)\/([a-z]*), '([A-Za-z]+)'\]/g)].map((m) => new RegExp(m[1], m[2]));
  assert.ok(pads.length >= 7, `REVIEW_ERRORS veio com ${pads.length} padroes`);
  const msgs = [...body.matchAll(/RAISE EXCEPTION '((?:[^']|'')*)'/g)].map((m) => m[1].replace(/''/g, "'").replace(/%/g, 'x'));
  assert.ok(msgs.length >= 6, `so ${msgs.length} mensagens lidas`);
  const semPadrao = msgs.filter((msg) => !pads.some((re) => re.test(msg)));
  assert.deepEqual(semPadrao, []);
});
