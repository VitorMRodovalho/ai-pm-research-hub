/**
 * #2621 (decisao do GP de 09/10/2026): o parecer da curadoria mora no registro dela, e o card mostra a
 * linha do tempo do envio.
 *
 * Medido em 09/10: devolucao e rejeicao colavam o parecer ao fim da descricao do artefato, e a tela so
 * carregava o historico da curadoria fora do rascunho, que e o estado depois de uma devolucao.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. devolucao e rejeicao nao alteram a descricao do card (o parecer segue no curation_review_log);
 *   B. o historico traz a rodada de cada parecer, os envios (com prazo) e a aprovacao, com os portoes
 *      de leitura antes de qualquer consulta;
 *   C. a tela carrega o historico tambem em rascunho para card de portfolio, desenha a linha do tempo com
 *      a etapa atual e as proximas, e aponta o reenvio so para artefato publicavel;
 *   D. todo texto novo existe nas 3 linguas.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const review = maskLineComments(latestFunctionCapture(ROOT, 'submit_curation_review').body);
const hist = maskLineComments(latestFunctionCapture(ROOT, 'get_item_curation_history').body);
const card = maskJsComments(readFileSync(resolve(ROOT, 'src/components/board/CardDetail.tsx'), 'utf8'));
const engine = readFileSync(resolve(ROOT, 'src/components/islands/BoardEngine.tsx'), 'utf8');
const DICTS = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => readFileSync(resolve(ROOT, `src/i18n/${l}.ts`), 'utf8'));
const KEYS = ['curationTimelineTitle', 'tlSubmitted', 'tlDeadline', 'tlRound', 'tlReturned', 'tlRejected', 'tlFavorable',
  'tlApproved', 'tlNow', 'tlAdjust', 'tlResubmit', 'tlCuration', 'tlDecision', 'tlPublication', 'tlResubmitHint'];

function branch(decision) {
  const m = review.match(new RegExp(`ELSIF p_decision = '${decision}' THEN([\\s\\S]*?)(?=ELSIF p_decision|END IF;\\s+RETURN v_log_id)`));
  assert.ok(m, `ramo ${decision} ausente`);
  return m[1];
}

test('A. devolucao e rejeicao nao alteram a descricao do card', () => {
  for (const d of ['returned_for_revision', 'rejected']) {
    const b = branch(d);
    assert.match(b, /UPDATE board_items SET\s+curation_status = 'draft',\s+status = '(review|archived)',\s+updated_at = now\(\)\s+WHERE id = p_item_id;/, `${d}: so estado e coluna`);
    assert.doesNotMatch(b, /description/, `${d}: descricao intocada`);
  }
  // o parecer continua gravado no registro da curadoria
  assert.match(review, /INSERT INTO curation_review_log \([^)]*feedback_notes[^)]*review_round[^)]*\)/);
});

test('B. o historico traz rodada, envios e aprovacao, depois dos portoes', () => {
  assert.match(hist, /'completed_at', crl\.completed_at,\s+'review_round', crl\.review_round\s+\) ORDER BY crl\.completed_at DESC\)/);
  assert.match(hist, /'submissions', coalesce\(\(\s+SELECT jsonb_agg\(jsonb_build_object\(\s+'at', ble\.created_at,\s+'sla_deadline', ble\.sla_deadline\s+\) ORDER BY ble\.created_at\)\s+FROM board_lifecycle_events ble\s+WHERE ble\.item_id = p_item_id AND ble\.action = 'submitted_for_curation'/);
  assert.match(hist, /'approved_at', \(\s+SELECT max\(ble\.created_at\) FROM board_lifecycle_events ble\s+WHERE ble\.item_id = p_item_id AND ble\.action = 'curation_approved'\s+\)/);
  const gate = hist.indexOf('IF NOT public.rls_can_see_item(p_item_id) THEN');
  const query = hist.indexOf('FROM curation_review_log crl');
  assert.ok(gate !== -1 && query !== -1 && gate < query, 'portao de visibilidade antes da consulta');
  assert.equal((hist.match(/'submissions', '\[\]'::jsonb, 'approved_at', NULL\)/g) || []).length, 2, 'as duas saidas vazias tem o mesmo formato');
});

test('C. a tela carrega o historico em rascunho de portfolio e desenha a linha do tempo', () => {
  assert.match(card, /if \(item\.curation_status && \(item\.curation_status !== 'draft' \|\| item\.is_portfolio_item\)\) \{\s+const ch = await safe\(sb\.rpc\('get_item_curation_history'/);
  assert.match(card, /for \(const s of curationHistory\.submissions \?\? \[\]\) \{/, 'envios entram na linha do tempo');
  assert.match(card, /for \(const r of curationHistory\.reviews\) \{/, 'pareceres entram na linha do tempo');
  assert.match(card, /: st === 'draft' && lastReturned && item\.status !== 'archived' \? \(i18n\.tlAdjust/, 'ajuste do autor e a etapa depois da devolucao (rejeitado arquiva)');
  assert.match(card, /aria-current="step"/, 'etapa atual marcada');
  assert.match(card, /\{current === \(i18n\.tlAdjust \|\| 'Ajuste do autor'\) && needsCuration && \(\s+<p[^>]*>\{i18n\.tlResubmitHint/, 'reenvio so para artefato publicavel');
});

test('D. todo texto novo existe nas 3 linguas', () => {
  for (const k of KEYS) {
    for (const d of DICTS) assert.match(d, new RegExp(`'comp\\.board\\.${k}': '`), `${k} em todos os dicionarios`);
    assert.match(engine, new RegExp(`${k}: t\\('comp\\.board\\.${k}', DEFAULT_I18N\\.${k}\\),`), `${k} no BoardEngine`);
  }
});
