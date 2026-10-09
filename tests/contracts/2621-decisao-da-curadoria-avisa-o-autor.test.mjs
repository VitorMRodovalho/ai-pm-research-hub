/**
 * #2621 item 0 (decisao do GP de 09/10/2026): toda decisao da curadoria avisa autor, coautores e
 * lideranca ativa da iniciativa, na hora.
 *
 * Medido em 09/10: o primeiro parecer real da plataforma (devolucao, rodada 1) nao gerou aviso para
 * ninguem. `submit_curation_review` nao chama `create_notification`, devolucao e rejeicao voltam
 * `curation_status` para 'draft', e `notify_on_curation_status_change` excluia 'draft' por construcao.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. toda SAIDA de curation_pending que a RPC produz (devolucao, rejeicao, aprovacao) e classificada
 *      no gatilho, e cada classe vira um tipo proprio, enviado no laco da audiencia;
 *   B. a classificacao casa com o que `submit_curation_review` e `publish_board_item_from_curation`
 *      gravam (so a rejeicao arquiva; a aprovacao vai para 'published');
 *   C. cada decisao aceita pela RPC tem o parecer lido do registro daquela decisao NESTA transacao
 *      (decisao nova na RPC sem par no gatilho reprova: e a transicao muda que originou a issue), e
 *      saida sem registro (caminho manual) nao vira aviso de decisao;
 *   D. audiencia = participantes do card UNION lideranca ativa da iniciativa, so pessoas ativas;
 *   E. o aviso generico deixa de mandar o "published" cru da aprovacao registrada;
 *   F. os 3 tipos sao transactional_immediate no helper e no catalogo ADR-0022.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const notify = maskLineComments(latestFunctionCapture(ROOT, 'notify_on_curation_status_change').body);
const review = maskLineComments(latestFunctionCapture(ROOT, 'submit_curation_review').body);
const publish = maskLineComments(latestFunctionCapture(ROOT, 'publish_board_item_from_curation').body);
const delivery = maskLineComments(latestFunctionCapture(ROOT, '_delivery_mode_for').body);
const catalog = JSON.parse(readFileSync(resolve(ROOT, 'docs/adr/ADR-0022-notification-types-catalog.json'), 'utf8'));

const TYPES = {
  devolvido: 'curation_decision_returned',
  rejeitado: 'curation_decision_rejected',
  aprovado: 'curation_decision_approved',
};

/** A classificacao da transicao: do `v_kind := CASE` ao `END;` dele. */
function classBlock() {
  const start = notify.indexOf('v_kind := CASE');
  const end = notify.indexOf('END;', start);
  assert.ok(start !== -1 && end > start, 'classificacao v_kind ausente do corpo vigente');
  return notify.slice(start, end + 'END;'.length);
}

/** A leitura do parecer: do `IF v_kind IN (...)` ate o aviso generico, que vem logo depois. */
function readBlock() {
  const start = notify.indexOf("IF v_kind IN ('aprovado', 'rejeitado', 'devolvido') THEN");
  const end = notify.indexOf('IF NEW.curation_status IS DISTINCT FROM OLD.curation_status', start);
  assert.ok(start !== -1 && end > start, 'leitura do parecer ausente (ou depois do aviso generico)');
  return notify.slice(start, end);
}

/** Do `IF v_kind IS NOT NULL THEN` ao `RETURN NEW;`: o aviso a tribo (entrada e decisoes). */
function tribeBlock() {
  const start = notify.indexOf('IF v_kind IS NOT NULL THEN');
  const end = notify.lastIndexOf('RETURN NEW;');
  assert.ok(start !== -1 && end > start, 'bloco do aviso a tribo ausente do corpo vigente');
  return notify.slice(start, end);
}

/** O `IF ... END IF;` do aviso generico card_moved. */
function genericBlock() {
  const at = notify.indexOf("'card_moved'");
  assert.ok(at !== -1, 'aviso generico card_moved ausente');
  const start = notify.lastIndexOf('IF NEW.curation_status IS DISTINCT FROM OLD.curation_status', at);
  const end = notify.indexOf('END IF;', at);
  assert.ok(start !== -1 && end !== -1, 'bloco IF do card_moved nao encontrado');
  return notify.slice(start, end);
}

/** O ramo `ELSIF p_decision = '<d>' THEN ...` (ou o `IF` do primeiro) de submit_curation_review. */
function decisionBranch(decision) {
  const re = new RegExp(`(?:ELS)?IF p_decision = '${decision}' THEN([\\s\\S]*?)(?=ELSIF p_decision|END IF;\\s+RETURN v_log_id)`);
  const m = review.match(re);
  assert.ok(m, `ramo da decisao ${decision} ausente de submit_curation_review`);
  return m[1];
}

test('A. cada saida de curation_pending e classificada no gatilho', () => {
  const b = classBlock();
  assert.match(b,
    /WHEN NEW\.curation_status = 'curation_pending'\s+AND OLD\.curation_status IS DISTINCT FROM 'curation_pending'\s+THEN 'entrada'/,
    'entrada (aviso #2496) segue na transicao');
  assert.match(b,
    /WHEN OLD\.curation_status = 'curation_pending'\s+AND NEW\.curation_status = 'published'\s+THEN 'aprovado'/,
    'aprovacao = saida para published');
  assert.match(b,
    /WHEN OLD\.curation_status = 'curation_pending'\s+AND NEW\.curation_status = 'draft' AND NEW\.status = 'archived'\s+THEN 'rejeitado'/,
    'rejeicao = saida para draft com o card arquivado');
  assert.match(b,
    /WHEN OLD\.curation_status = 'curation_pending'\s+AND NEW\.curation_status = 'draft'\s+THEN 'devolvido'/,
    'devolucao = demais saidas para draft');
  // a ordem decide: a rejeicao tem de ser testada antes da devolucao, senao vira devolucao
  assert.ok(b.indexOf("THEN 'rejeitado'") < b.indexOf("THEN 'devolvido'"),
    'rejeitado vem antes de devolvido no CASE');
});

test('A. cada classe vira um tipo proprio, e o laco da audiencia envia esse tipo', () => {
  const b = tribeBlock();
  assert.match(b, /WHEN 'entrada'\s+THEN 'curation_submitted_to_tribe'/);
  for (const [kind, type] of Object.entries(TYPES)) {
    assert.match(b, new RegExp(`v_type := CASE v_kind[\\s\\S]*?WHEN '${kind}'\\s+THEN '${type}'[\\s\\S]*?END;`),
      `${kind} => ${type}`);
  }
  assert.match(b,
    /^IF v_kind IS NOT NULL THEN[\s\S]*FOR v_recipient IN[\s\S]*?LOOP\s+PERFORM create_notification\(\s*v_recipient\.member_id,\s*v_type,\s*v_titulo,\s*v_corpo,\s*v_link,\s*'board_item',\s*NEW\.id\s*\);\s+END LOOP;\s+END IF;\s*$/,
    'toda classe nao nula chega ao laco, que envia o tipo, o titulo e o corpo da classe');
});

test('A. cada classe tem o seu titulo', () => {
  const t = tribeBlock().match(/v_titulo := CASE v_kind([\s\S]*?)END;/);
  assert.ok(t, 'titulos por classe ausentes');
  assert.match(t[1], /WHEN 'devolvido' THEN 'A curadoria pediu ajustes no seu trabalho'/);
  assert.match(t[1], /WHEN 'rejeitado' THEN 'A curadoria não aprovou seu trabalho'/);
  assert.match(t[1], /WHEN 'aprovado'\s+THEN 'Seu trabalho foi aprovado pela curadoria'/);
});

test('B. a classificacao casa com o que a RPC e a publicacao gravam', () => {
  assert.match(decisionBranch('rejected'),
    /UPDATE board_items SET\s+curation_status = 'draft',\s+status = 'archived',/,
    'so a rejeicao arquiva: e o discriminador do gatilho');
  const ret = decisionBranch('returned_for_revision');
  assert.match(ret, /UPDATE board_items SET\s+curation_status = 'draft',\s+status = 'review',/,
    'a devolucao volta para draft sem arquivar');
  assert.match(decisionBranch('approved'),
    /IF v_approved_count >= v_required THEN\s+v_pub_id := public\.publish_board_item_from_curation\(p_item_id\);/,
    'a aprovacao final passa pela publicacao');
  assert.match(publish,
    /UPDATE public\.board_items\s+SET curation_status = 'published', updated_at = now\(\)\s+WHERE id = p_item_id;/,
    'a publicacao tira o item de curation_pending para published');
});

test('C. toda decisao aceita pela RPC tem o parecer lido do registro daquela decisao', () => {
  const list = review.match(/IF p_decision NOT IN \(([^)]*)\) THEN/);
  assert.ok(list, 'lista de decisoes aceitas ausente de submit_curation_review');
  const decisions = [...list[1].matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
  assert.ok(decisions.length >= 3, `esperava ao menos 3 decisoes, achei ${decisions.length}`);

  const read = readBlock().match(/^IF v_kind IN \('aprovado', 'rejeitado', 'devolvido'\) THEN\s+SELECT crl\.review_round,\s+nullif\(btrim\(regexp_replace\(crl\.feedback_notes, '\\s\+', ' ', 'g'\)\), ''\)\s+INTO v_rodada, v_parecer\s+FROM curation_review_log crl\s+WHERE crl\.board_item_id = NEW\.id\s+AND crl\.completed_at = now\(\)\s+AND crl\.decision = CASE v_kind([\s\S]*?)END\s+ORDER BY crl\.completed_at DESC, crl\.id\s+LIMIT 1;\s+IF NOT FOUND THEN\s+v_kind := NULL;\s+END IF;/);
  assert.ok(read, 'leitura do parecer DESTA transacao (completed_at = now()), e sem registro a decisao nao e afirmada');
  const mapped = [...read[1].matchAll(/THEN '([a-z_]+)'|ELSE '([a-z_]+)'/g)].map((m) => m[1] || m[2]);
  for (const d of decisions) {
    assert.ok(mapped.includes(d), `decisao '${d}' aceita pela RPC nao tem par no gatilho (transicao muda)`);
  }
  assert.match(read[1], /WHEN 'rejeitado' THEN 'rejected'/, 'rejeitado le o registro de rejeicao');
  assert.match(read[1], /WHEN 'aprovado'\s+THEN 'approved'/, 'aprovado le o registro de aprovacao');
  assert.match(read[1], /ELSE 'returned_for_revision'\s*$/, 'devolvido le o registro de devolucao');
});

test('C. o parecer e cortado em 400 caracteres', () => {
  assert.match(readBlock(), /IF length\(v_parecer\) > 400 THEN\s+v_parecer := left\(v_parecer, 400\) \|\| '…';\s+END IF;/);
});

test('C. o corpo da devolucao leva o parecer e o da rejeicao leva o motivo', () => {
  const b = tribeBlock();
  assert.match(b,
    /WHEN 'devolvido' THEN\s+'"' \|\| NEW\.title \|\| '" voltou da curadoria com pedido de ajuste'[\s\S]*?CASE WHEN v_parecer IS NOT NULL THEN ' Parecer: ' \|\| v_parecer ELSE '' END[\s\S]*?envie de novo para a curadoria/,
    'devolucao: parecer e o proximo passo');
  assert.match(b,
    /WHEN 'rejeitado' THEN\s+'"' \|\| NEW\.title \|\| '" não foi aprovado pela curadoria'[\s\S]*?CASE WHEN v_parecer IS NOT NULL THEN ' Motivo: ' \|\| v_parecer ELSE '' END/,
    'rejeicao: motivo');
  assert.match(b, /WHEN 'aprovado' THEN\s+'"' \|\| NEW\.title \|\| '" foi aprovado pela curadoria/,
    'aprovacao em linguagem humana');
});

test('D. audiencia = participantes UNION lideranca ativa da iniciativa, so pessoas ativas', () => {
  assert.match(tribeBlock(),
    /FOR v_recipient IN\s+SELECT r\.member_id\s+FROM \(\s*SELECT bia\.member_id FROM board_item_assignments bia WHERE bia\.item_id = NEW\.id\s+UNION\s+SELECT m\.id FROM engagements e JOIN members m ON m\.person_id = e\.person_id[\s\S]*?e\.initiative_id = v_initiative_id\s+AND e\.status = 'active'\s+AND e\.role = 'leader'\s*\) r\s+JOIN members mr ON mr\.id = r\.member_id\s+WHERE mr\.member_status = 'active'\s+LOOP/);
});

test('E. o aviso generico deixa a aprovacao para o tipo proprio', () => {
  assert.match(genericBlock(),
    /AND NEW\.curation_status != 'draft'\s+AND v_kind IS DISTINCT FROM 'aprovado'\s+AND NEW\.curation_status != 'curation_pending' THEN\s+FOR v_assignee IN/);
});

test('F. os 3 tipos sao imediatos no helper e no catalogo', () => {
  for (const type of Object.values(TYPES)) {
    assert.match(delivery, new RegExp(`WHEN '${type}'\\s+THEN 'transactional_immediate'`), `${type} no helper`);
    assert.equal(catalog.types[type]?.delivery_mode, 'transactional_immediate', `${type} no catalogo`);
  }
});
