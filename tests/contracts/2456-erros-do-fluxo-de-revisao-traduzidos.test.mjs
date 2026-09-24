// tests/contracts/2456-erros-do-fluxo-de-revisao-traduzidos.test.mjs
// Registrar em "test:behavioural" + "test:contracts" (#1109). NAO em test:structural: le o banco,
// e o guard #1908 exige DB-gated na faixa SERIALIZADA (#1509).
/**
 * Toda mensagem que as RPCs do fluxo de revisao levantam chega a tela como mensagem de acao traduzida.
 *
 * O CASO (#2456): o CardDetail mostrava err.message cru; varias mensagens eram tecnicas e em ingles
 * ("Peer review can only be completed from draft or peer_review status (current: leader_review)").
 * Medido em 24/09/2026: 23 mensagens em 4 RPCs.
 *
 * O guard e DERIVADO: le do banco toda mensagem RAISE EXCEPTION das RPCs do fluxo e exige que cada uma
 * caia num padrao de REVIEW_ERRORS, e que a chave do padrao exista nas 3 linguas. Uma mensagem nova
 * numa RPC reprova aqui ate ganhar traducao.
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
const DICTS = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => readFileSync(`src/i18n/${l}.ts`, 'utf8'));
const RPCS = ['complete_peer_review', 'complete_leader_review', 'submit_for_curation', 'set_board_item_artifact_type'];

/** Os padroes de REVIEW_ERRORS, lidos do fonte (sem comentarios), como [RegExp, chave]. */
export function padroes(src) {
  const c = maskJsComments(src);
  const bloco = (c.match(/const REVIEW_ERRORS: Array<\[RegExp, string\]> = \[([\s\S]*?)\n\];/) || [])[1] || '';
  return [...bloco.matchAll(/\[\/(.+?)\/([a-z]*), '([A-Za-z]+)'\]/g)].map((m) => [new RegExp(m[1], m[2]), m[3]]);
}

/** As mensagens RAISE EXCEPTION de um corpo plpgsql (o % do formato vira texto de exemplo). */
export function mensagens(body) {
  return [...body.matchAll(/RAISE EXCEPTION '((?:[^']|'')*)'/g)].map((m) => m[1].replace(/''/g, "'").replace(/%/g, 'x'));
}

/** Mensagens sem padrao, e chaves sem traducao em alguma lingua. */
export function lacunas(msgs, pads, dicts) {
  const semPadrao = msgs.filter((msg) => !pads.some(([re]) => re.test(msg)));
  const chaves = [...new Set(pads.map(([, k]) => k))];
  const semTraducao = chaves.filter((k) => !dicts.every((d) => d.includes(`'comp.board.${k}'`)));
  return { semPadrao, semTraducao };
}

/** Os 4 pontos da tela que mostram erro de RPC do fluxo passam pela traducao. */
export function telaTraduz(src) {
  const c = maskJsComments(src);
  return ['Erro ao salvar o tipo', 'Erro ao submeter', 'Erro no peer review', 'Erro no leader review']
    .every((fb) => c.includes(`toast?.(friendlyReviewError(err?.message, '${fb}'), 'error')`));
}

async function corpo(proname) {
  const { data, error } = await sb().rpc('_audit_function_source', { p_proname: proname });
  assert.equal(error, null, `_audit_function_source(${proname}) falhou: ${error?.message ?? ''}`);
  assert.ok(Array.isArray(data) && data.length === 1, `${proname}: esperava 1 sobrecarga, veio ${data?.length}`);
  return data[0].prosrc;
}

test(dbGated ? '#2456: toda mensagem das RPCs do fluxo tem traducao nas 3 linguas' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const msgs = [];
    for (const fn of RPCS) msgs.push(...mensagens(await corpo(fn)));
    // controle: sem mensagens lidas, "nenhuma sem padrao" passaria por vacuidade
    assert.ok(msgs.length >= 20, `so ${msgs.length} mensagens lidas das RPCs`);
    const pads = padroes(CARD);
    assert.ok(pads.length >= 7, `REVIEW_ERRORS veio com ${pads.length} padroes`);
    assert.deepEqual(lacunas(msgs, pads, DICTS), { semPadrao: [], semTraducao: [] });
  });

test('#2456: a tela mostra o erro traduzido nos 4 pontos do fluxo', () => {
  assert.equal(telaTraduz(CARD), true);
});

test('#2456 mutacao: cada detector reprova a forma do defeito, pela MESMA funcao', () => {
  const m = (src, a, b) => { const out = src.replace(a, b); assert.notEqual(out, src, `mutacao nao aplicou: ${a}`); return out; };
  const pads = padroes(CARD);
  const amostra = ['Peer review can only be completed from draft or peer_review status (current: x)', 'Not authenticated', 'Item not found: x'];
  assert.deepEqual(lacunas(amostra, pads, DICTS).semPadrao, []);
  // 1: mensagem nova numa RPC, sem padrao
  assert.deepEqual(lacunas([...amostra, 'Something new happened'], pads, DICTS).semPadrao, ['Something new happened']);
  // 2: um padrao removido deixa sua mensagem sem traducao
  const semStale = padroes(m(CARD, "  [/can only be completed from|must be in leader_review or draft/i, 'reviewErrStale'],\n", ''));
  assert.equal(lacunas(amostra, semStale, DICTS).semPadrao.length, 1);
  // 3: chave sem traducao numa lingua
  const semEs = [DICTS[0], DICTS[1], DICTS[2].replace("'comp.board.reviewErrStale'", "'comp.board.removida'")];
  assert.deepEqual(lacunas(amostra, pads, semEs).semTraducao, ['reviewErrStale']);
  // 4: um ponto da tela volta a mostrar o erro cru
  assert.equal(telaTraduz(m(CARD, "toast?.(friendlyReviewError(err?.message, 'Erro no peer review'), 'error')", "toast?.(err.message || 'Erro no peer review', 'error')")), false);
});
