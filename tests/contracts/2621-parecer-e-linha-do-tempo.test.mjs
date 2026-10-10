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
 *   C. a tela carrega o historico tambem em rascunho de portfolio; a linha do tempo data cada evento no fuso
 *      de Brasilia, em ordem estavel; a etapa atual sai do estado e do ultimo parecer (publicado e encerrado
 *      sem "agora"); o reenvio so e oferecido a quem tem o botao; falar com a curadoria leva ao comentario;
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
  'tlApproved', 'tlNow', 'tlAdjust', 'tlResubmit', 'tlCuration', 'tlDecision', 'tlPublication', 'tlResubmitHint',
  'tlResubmitted', 'tlNoDeadline', 'tlPublished', 'tlClosed', 'tlReadReview', 'tlAskLeader', 'tlContact', 'tlSrDone', 'tlSrNext',
  'reviewDecApproved', 'reviewDecRejected', 'reviewDecReturned'];

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

function timeline() {
  // comentarios JSX sao mascarados: as ancoras sao codigo
  const i = card.indexOf("const loc = pageLang() === 'en'");
  const j = card.indexOf('})()}', i);
  assert.ok(i !== -1 && j > i, 'bloco da linha do tempo ausente');
  return card.slice(i, j);
}

test('C. a tela carrega o historico em rascunho de portfolio', () => {
  assert.match(card, /if \(item\.curation_status && \(item\.curation_status !== 'draft' \|\| item\.is_portfolio_item\)\) \{\s+const ch = await safe\(sb\.rpc\('get_item_curation_history'/);
});

test('C. eventos datados no fuso de Brasilia, em ordem estavel', () => {
  const t = timeline();
  assert.match(t, /toLocaleDateString\(loc, \{ day: '2-digit', month: '2-digit', timeZone: 'America\/Sao_Paulo' \}\)/);
  assert.match(t, /\(curationHistory\.submissions \?\? \[\]\)\.forEach\(\(s, i\) => \{[\s\S]*?evs\.push\(\{ at: s\.at, rank: 0,/, 'cada envio vira evento');
  assert.match(t, /for \(const r of curationHistory\.reviews\) \{[\s\S]*?evs\.push\(\{ at: r\.completed_at, rank: 1,/, 'cada parecer vira evento');
  assert.match(t, /evs\.sort\(\(x, y\) => \(new Date\(x\.at\)\.getTime\(\) - new Date\(y\.at\)\.getTime\(\)\) \|\| \(x\.rank - y\.rank\)\);/, 'empate: envio, parecer, aprovacao');
});

test('C. a etapa atual decide pelo estado e pelo ultimo parecer', () => {
  const t = timeline();
  assert.match(t,
    /st === 'curation_pending' \? 'curation'\s+: st === 'published' \? 'published'\s+: st === 'draft' && lastReview\?\.decision === 'rejected' && item\.status === 'archived' \? 'closed'\s+: st === 'draft' && lastReview && lastReview\.decision !== 'approved' \? 'adjust'\s+: null;/);
  assert.match(t, /\{\(stage === 'curation' \|\| stage === 'adjust'\) && \(\s+<li[^>]*aria-current="step"/, 'so etapa em andamento e "agora"');
  assert.match(t, /\{stage === 'published' && \(\s+<li className="[^"]*">[\s\S]*?i18n\.tlPublished/, 'publicado como etapa concluida');
  assert.doesNotMatch(t.slice(t.indexOf("{stage === 'published' && ("), t.indexOf("{stage === 'closed' && (")), /aria-current/, 'publicado sem "agora"');
  assert.match(t, /\{stage === 'closed' && \(\s+<li[\s\S]*?i18n\.tlClosed/, 'rejeitado encerra com linha propria');
});

test('C. o reenvio so e oferecido a quem tem o botao; os demais pedem a lideranca', () => {
  const t = timeline();
  assert.match(t, /const canResubmit = needsCuration && \(isLeader \|\| isCardAssignee\);/, 'mesma condicao do botao');
  assert.match(t, /\{needsCuration && \(canResubmit\s+\? `\$\{i18n\.tlResubmitHint[^`]*`\s+: \(i18n\.tlAskLeader/);
  assert.match(card, /\{item\.curation_status === 'draft' && needsCuration && \(isLeader \|\| isCardAssignee\) && \(/, 'o botao segue com a mesma condicao');
});

test('C. falar com a curadoria leva ao comentario do card', () => {
  const t = timeline();
  assert.match(t, /const box = document\.getElementById\(`card-comments-\$\{item\.id\}`\);[\s\S]*?querySelector\('textarea'\)[\s\S]*?\.focus\(\);/);
  assert.match(t, /\{\(stage === 'curation' \|\| stage === 'adjust' \|\| stage === 'closed'\) && \(\s+<button type="button" onClick=\{goToComments\}/);
  assert.match(card, /<div id=\{`card-comments-\$\{item\.id\}`\}>\s+<CardComments/, 'o destino existe');
});

test('D. todo texto novo existe nas 3 linguas', () => {
  for (const k of KEYS) {
    for (const d of DICTS) assert.match(d, new RegExp(`'comp\\.board\\.${k}': '`), `${k} em todos os dicionarios`);
    assert.match(engine, new RegExp(`${k}: t\\('comp\\.board\\.${k}', DEFAULT_I18N\\.${k}\\),`), `${k} no BoardEngine`);
  }
});
