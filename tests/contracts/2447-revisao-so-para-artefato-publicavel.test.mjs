// tests/contracts/2447-revisao-so-para-artefato-publicavel.test.mjs
// Registrar em "test:behavioural" + "test:contracts" (#1109). NAO em test:structural: le o banco,
// e o guard #1908 exige DB-gated na faixa SERIALIZADA (#1509).
/**
 * Peer review, revisao do lider e curadoria valem so para artefato publicavel, e o tipo do
 * artefato tem caminho de escrita pela tela.
 *
 * O CASO (#2447): a secao de revisao aparecia em todo card em draft, e as tres RPCs do fluxo nao
 * olhavam se o card era artefato: 5 dos 16 cards parados em leader_review (24/09/2026) eram
 * tarefas comuns. E o tipo do artefato, que o painel de portfolio le da taxonomia, nao tinha
 * escrita em tela nenhuma.
 *
 * Exercido como lider real, em transacao desfeita (24/09/2026): aprovar card de portfolio sem tipo
 * = recusado; classificar como publicacao e aprovar = passou; aprovar webinar = recusado; devolver
 * webinar = passou; classificar card de outra iniciativa = recusado; subtipo fora de publicacao =
 * recusado; dispensa do lider sobre artigo academico = passou e o rodizio designou 2 pareceristas.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

const CARD = readFileSync('src/components/board/CardDetail.tsx', 'utf8');
const TIPOS_DE_CURADORIA = ['artigo_academico', 'artigo_linkedin', 'ebook', 'estudo_caso', 'infografico', 'publicacao', 'report'];

/** Remove comentarios de linha SQL e normaliza espacos. */
function sql(body) {
  return body.split('\n').map((l) => { const i = l.indexOf('--'); return i >= 0 ? l.slice(0, i) : l; })
    .join('\n').replace(/\s+/g, ' ');
}

/** A trava existe, recusa (RAISE ligado a condicao) e vem ANTES da escrita que ela protege. */
export function travaAntesDaEscrita(body, condicao, escrita) {
  const c = sql(body);
  const m = c.match(new RegExp(`IF ${condicao} THEN RAISE EXCEPTION`));
  const w = c.indexOf(escrita);
  return !!m && w > 0 && m.index < w;
}

/** O predicado: portfolio E tipo marcado como de curadoria na propria taxonomia. */
export function predicado(body) {
  const c = sql(body);
  return /bi\.is_portfolio_item IS TRUE/.test(c) && /g\.requires_curation IS TRUE/.test(c);
}

/** A tela: secao so para artefato ou card ja no fluxo; lider fora de artefato so devolve. */
export function tela(src) {
  const c = maskJsComments(src);
  return {
    secaoCondicionada: /const showPreCuration = inReviewFlow \|\| \(\(item\.curation_status \|\| 'draft'\) === 'draft' && needsCuration\);/.test(c)
      && /\{showPreCuration && \(\['draft', 'peer_review', 'leader_review'\]/.test(c),
    liderSoDevolve: /const leaderOptions: Array<'approved' \| 'returned' \| 'waived'> = needsCuration \? \['approved', 'returned', 'waived'\] : \['returned'\];/.test(c)
      && /\{leaderOptions\.map\(\(d\) =>/.test(c),
    atalhoSoArtefato: /item\.curation_status === 'draft' && needsCuration && \(isLeader \|\| isCardAssignee\)/.test(c),
    escreveTaxonomia: /sb\.rpc\('set_board_item_artifact_type', \{ p_item_id: item\.id, p_type: type, p_subtype: subtype \}\)/.test(c),
    rotuloTraduzido: /\{i18n\.portfolioFlagLabel \|\|/.test(c),
  };
}

async function corpo(proname) {
  const { data, error } = await sb().rpc('_audit_function_source', { p_proname: proname });
  assert.equal(error, null, `_audit_function_source(${proname}) falhou: ${error?.message ?? ''}`);
  assert.ok(Array.isArray(data) && data.length === 1, `${proname}: esperava 1 sobrecarga, veio ${data?.length}`);
  return data[0].prosrc;
}

test(dbGated ? '#2447: as tres portas do fluxo recusam card que nao e artefato publicavel' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    assert.ok(travaAntesDaEscrita(await corpo('complete_peer_review'),
      'NOT public\\._board_item_needs_curation\\(p_item_id\\)', "SET curation_status = 'leader_review'"),
      'complete_peer_review perdeu a trava de artefato');
    assert.ok(travaAntesDaEscrita(await corpo('complete_leader_review'),
      "p_decision IN \\('approved', 'waived'\\) AND NOT public\\._board_item_needs_curation\\(p_item_id\\)",
      "SET curation_status = 'curation_pending'"),
      'complete_leader_review deixou aprovar/dispensar card que nao e artefato');
    assert.ok(travaAntesDaEscrita(await corpo('submit_for_curation'),
      'NOT public\\._board_item_needs_curation\\(p_item_id\\)', "SET curation_status = 'curation_pending'"),
      'submit_for_curation perdeu a trava de artefato');
    assert.ok(predicado(await corpo('_board_item_needs_curation')), 'o predicado deixou de exigir portfolio + tipo de curadoria');
  });

test(dbGated ? '#2447: os tipos que passam por curadoria sao exatamente os decididos' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const { data, error } = await sb().from('tags').select('name').eq('domain', 'board_item').eq('requires_curation', true);
    assert.equal(error, null);
    assert.deepEqual(data.map((r) => r.name).sort(), TIPOS_DE_CURADORIA,
      'o conjunto de tipos de curadoria mudou sem decisao registrada (#2447)');
  });

test('#2447: a tela so oferece revisao para artefato publicavel e grava o tipo na taxonomia', () => {
  const t = tela(CARD);
  assert.deepEqual(t, Object.fromEntries(Object.keys(t).map((k) => [k, true])));
});

test('#2447 mutacao: cada detector reprova a forma do defeito, pela MESMA funcao', () => {
  const m = (src, a, b) => { const out = src.replace(a, b); assert.notEqual(out, src, `mutacao nao aplicou: ${a}`); return out; };
  const PEER = `IF NOT public._board_item_needs_curation(p_item_id) THEN
      RAISE EXCEPTION 'x';
    END IF;
    UPDATE public.board_items SET curation_status = 'leader_review'`;
  const C = 'NOT public\\._board_item_needs_curation\\(p_item_id\\)';
  assert.equal(travaAntesDaEscrita(PEER, C, "SET curation_status = 'leader_review'"), true);
  // 1: trava removida
  assert.equal(travaAntesDaEscrita(m(PEER, 'IF NOT public._board_item_needs_curation(p_item_id) THEN', 'IF false THEN'), C, "SET curation_status = 'leader_review'"), false);
  // 2: trava so em comentario
  assert.equal(travaAntesDaEscrita(m(PEER, 'IF NOT public._board_item_needs_curation', '-- IF NOT public._board_item_needs_curation'), C, "SET curation_status = 'leader_review'"), false);
  // 3: trava DEPOIS da escrita nao protege
  const tarde = `UPDATE public.board_items SET curation_status = 'leader_review';
    IF NOT public._board_item_needs_curation(p_item_id) THEN RAISE EXCEPTION 'x'; END IF;`;
  assert.equal(travaAntesDaEscrita(tarde, C, "SET curation_status = 'leader_review'"), false);

  const PRED = `WHERE bi.id = p_item_id AND bi.is_portfolio_item IS TRUE AND g.domain = 'board_item' AND g.requires_curation IS TRUE`;
  assert.equal(predicado(PRED), true);
  // 4: qualquer tag de board_item passaria
  assert.equal(predicado(m(PRED, ' AND g.requires_curation IS TRUE', '')), false);
  // 5: card fora do portfolio passaria
  assert.equal(predicado(m(PRED, 'bi.is_portfolio_item IS TRUE AND ', '')), false);

  // Tela
  // 6: secao volta a aparecer em todo draft
  assert.equal(tela(m(CARD, "{showPreCuration && (['draft'", "{(['draft'")).secaoCondicionada, false);
  // 7: lider volta a ver aprovar em card que nao e artefato
  assert.equal(tela(m(CARD, "needsCuration ? ['approved', 'returned', 'waived'] : ['returned']", "['approved', 'returned', 'waived']")).liderSoDevolve, false);
  // 8: atalho de submissao direta sem a trava
  assert.equal(tela(m(CARD, "item.curation_status === 'draft' && needsCuration && (isLeader", "item.curation_status === 'draft' && (isLeader")).atalhoSoArtefato, false);
  // 9: seletor sem escrita na taxonomia
  assert.equal(tela(m(CARD, "sb.rpc('set_board_item_artifact_type'", "sb.rpc('noop'")).escreveTaxonomia, false);
});
