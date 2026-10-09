/**
 * update_board_item: alinhamento ao fluxo da curadoria.
 *
 * O estado e o prazo da curadoria seguem as regras de cada etapa do fluxo da curadoria. Na edicao
 * de card fica so o reparo administrativo (manage_platform), registrado no historico do card.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. alteracao de estado ou prazo da curadoria exige manage_platform;
 *   B. o portao fica entre o portao de escrita e a primeira escrita;
 *   C. as duas colunas so sao escritas no ramo permitido (o reenvio do valor atual nao regrava);
 *   D. o reparo deixa evento no historico do card.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const body = maskLineComments(latestFunctionCapture(process.cwd(), 'update_board_item').body);
const GATE = /v_curation_repair := \(p_fields->>'curation_status' IS NOT NULL\s+AND p_fields->>'curation_status' IS DISTINCT FROM v_old\.curation_status\)\s+OR \(p_fields->>'curation_due_at' IS NOT NULL\s+AND \(p_fields->>'curation_due_at'\)::timestamptz IS DISTINCT FROM v_old\.curation_due_at\);\s+IF v_curation_repair AND NOT public\.can_by_member\(v_caller\.id, 'manage_platform'\) THEN\s+RAISE EXCEPTION 'Insufficient permissions to edit this field';/;

test('A. estado ou prazo da curadoria exige manage_platform', () => {
  assert.match(body, GATE);
});

test('B. o portao fica entre o portao de escrita e a primeira escrita', () => {
  const at = body.search(GATE);
  const gate = body.indexOf("RAISE EXCEPTION 'Insufficient permissions to edit this card';");
  const firstWrite = body.search(/\bUPDATE board_items SET\b/);
  assert.ok(gate !== -1 && firstWrite !== -1, 'ancoras ausentes');
  assert.ok(at > gate && at < firstWrite, 'depois do portao de escrita, antes de escrever');
});

test('C. as colunas da curadoria so sao escritas no ramo permitido', () => {
  assert.match(body,
    /curation_status = CASE WHEN v_curation_repair\s+THEN coalesce\(p_fields->>'curation_status', curation_status\) ELSE curation_status END,/);
  assert.match(body,
    /curation_due_at = CASE WHEN v_curation_repair AND p_fields->>'curation_due_at' IS NOT NULL\s+THEN \(p_fields->>'curation_due_at'\)::timestamptz ELSE curation_due_at END,/);
  assert.doesNotMatch(body, /curation_status = coalesce\(p_fields->>'curation_status', curation_status\)/,
    'nenhuma escrita livre da coluna');
});

test('D. o reparo deixa evento no historico do card', () => {
  assert.match(body,
    /IF v_curation_repair THEN\s+INSERT INTO board_lifecycle_events \(board_id, item_id, action, reason, actor_member_id\)\s+VALUES \(v_board_id, p_item_id, 'status_change',\s+'Reparo administrativo da curadoria: '/);
});
