/**
 * trg_auto_submit_curation_on_reviewer_assign: paridade com as demais entradas na curadoria (#2447).
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. o envio automatico so acontece para artefato publicavel, na MESMA condicao que decide o UPDATE.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const body = maskLineComments(latestFunctionCapture(process.cwd(), 'trg_auto_submit_curation_on_reviewer_assign').body);

test('A. so artefato publicavel e enviado automaticamente', () => {
  assert.match(body,
    /IF v_item\.status = 'done' AND v_item\.curation_status = 'draft'\s+AND public\._board_item_needs_curation\(NEW\.item_id\) THEN\s+UPDATE public\.board_items\s+SET curation_status = 'curation_pending',/);
  // nenhum outro caminho no corpo leva a curation_pending
  assert.equal((body.match(/curation_status = 'curation_pending'/g) || []).length, 1);
});
