/**
 * Ativacao de cadeia promove o documento que circulou direto de rascunho (09/10/2026).
 *
 * trg_sync_ratification_cache roda quando a cadeia vira 'active' e so promovia 'under_review'.
 * O TAP do Grupo de Estudos CPMAI, primeira cadeia aprovada pelo fluxo normal de assinaturas,
 * tinha o documento em 'draft' e ficaria assim mesmo depois de ativado. Afirma, no bloco do UPDATE
 * de governance_documents da captura mais nova, que 'draft' e 'under_review' viram 'active' e que
 * nada mais muda de status; e que o bloco so roda na transicao para 'active'.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const cap = latestFunctionCapture(process.cwd(), 'trg_sync_ratification_cache');
const corpo = maskLineComments(cap.body);

test('ativacao: rascunho e revisao viram active, so na transicao para active', () => {
  assert.match(corpo, /IF NEW\.status = 'active' AND \(TG_OP = 'INSERT' OR OLD\.status IS DISTINCT FROM 'active'\) THEN/);
  const upd = corpo.match(/UPDATE public\.governance_documents([\s\S]*?)WHERE id = NEW\.document_id;/);
  assert.ok(upd, 'o UPDATE do documento sumiu');
  assert.match(upd[1], /status = CASE WHEN status IN \('draft', 'under_review'\) THEN 'active' ELSE status END,/);
  assert.match(upd[1], /current_ratified_chain_id\s+= NEW\.id,/);
});
