// tests/contracts/2455-revisor-de-governanca-ve-o-botao.test.mjs
// Registrar em "test:behavioural" + "test:contracts" (#1109). NAO em test:structural: le o banco,
// e o guard #1908 exige DB-gated na faixa SERIALIZADA (#1509).
/**
 * Quem pode avaliar como lider na tela e quem a RPC aceita.
 *
 * O CASO (#2455): complete_leader_review aceita o lider da iniciativa OU quem tem
 * participate_in_governance_review; a tela so mostrava "Avaliar como Lider" a quem tem
 * manage_board_admin. Um revisor de governanca que o banco autoriza nao via o botao.
 *
 * Correcao: get_artifact_classification devolve `can_leader_review` pela MESMA regra da RPC, e a
 * tela usa isso. Exercido com impersonacao (24/09/2026), num card real: revisor de governanca sem
 * manage_board_admin = true; membro comum = false; lider da iniciativa = true.
 *
 * O guard afirma PARIDADE: os dois ramos da regra aparecem na RPC que decide e no campo que a tela
 * le. E a ordem de declaracao na tela, porque `const` usado antes de declarado quebra o card inteiro.
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

function sql(body) {
  return body.split('\n').map((l) => { const i = l.indexOf('--'); return i >= 0 ? l.slice(0, i) : l; })
    .join('\n').replace(/\s+/g, ' ');
}

/** Os dois ramos da regra: lider por vinculo ativo, e revisor de governanca. */
export function ramos(body) {
  const c = sql(body);
  return {
    liderPorVinculo: /e\.status = 'active' AND e\.role = 'leader' AND p\.auth_id = auth\.uid\(\)/.test(c),
    revisorDeGovernanca: /can_by_member\(v_caller(\.id)?, 'participate_in_governance_review'\)/.test(c),
  };
}

/** O campo que a tela le carrega os dois ramos. */
export function campoDaTela(body) {
  const c = sql(body);
  const m = c.match(/'can_leader_review', (.*?), 'types'/);
  return m ? ramos(m[1]) : { liderPorVinculo: false, revisorDeGovernanca: false };
}

/** A tela: usa o campo do servidor, nos dois ramos do bloco, declarado DEPOIS de isLeader. */
export function tela(src) {
  const c = maskJsComments(src);
  const iLeader = c.indexOf('const isLeader =');
  const iCan = c.indexOf('const canLeaderReview =');
  return {
    usaOServidor: /const canLeaderReview = isLeader \|\| !!classif\?\.can_leader_review;/.test(c),
    nosDoisRamos: (c.match(/rv\.peer_review_completed_at && canLeaderReview && (?:!)?showLeaderReviewForm/g) || []).length === 2,
    declaradoDepois: iLeader > 0 && iCan > iLeader,
  };
}

const allTrue = (o) => Object.fromEntries(Object.keys(o).map((k) => [k, true]));

async function corpo(proname) {
  const { data, error } = await sb().rpc('_audit_function_source', { p_proname: proname });
  assert.equal(error, null, `_audit_function_source(${proname}) falhou: ${error?.message ?? ''}`);
  assert.ok(Array.isArray(data) && data.length === 1, `${proname}: esperava 1 sobrecarga, veio ${data?.length}`);
  return data[0].prosrc;
}

test(dbGated ? '#2455: a RPC que decide e o campo que a tela le usam a mesma regra' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const rpc = ramos(await corpo('complete_leader_review'));
    assert.deepEqual(rpc, allTrue(rpc), 'complete_leader_review mudou de regra: atualize o campo da tela junto');
    const campo = campoDaTela(await corpo('get_artifact_classification'));
    assert.deepEqual(campo, allTrue(campo), 'can_leader_review divergiu da regra da RPC');
  });

test('#2455: a tela usa o campo do servidor, nos dois ramos, declarado depois de isLeader', () => {
  const t = tela(CARD);
  assert.deepEqual(t, allTrue(t));
});

test('#2455 mutacao: cada detector reprova a forma do defeito, pela MESMA funcao', () => {
  const m = (src, a, b) => { const out = src.replace(a, b); assert.notEqual(out, src, `mutacao nao aplicou: ${a}`); return out; };
  // 1: tela volta a so isLeader (o defeito original)
  assert.equal(tela(m(CARD, 'const canLeaderReview = isLeader || !!classif?.can_leader_review;', 'const canLeaderReview = isLeader;')).usaOServidor, false);
  // 2: um dos ramos do bloco volta a usar isLeader
  assert.equal(tela(m(CARD, 'rv.peer_review_completed_at && canLeaderReview && !showLeaderReviewForm', 'rv.peer_review_completed_at && isLeader && !showLeaderReviewForm')).nosDoisRamos, false);
  // 3: usado antes de declarado (quebraria o card): mover a declaracao para antes de isLeader
  const decl = CARD.match(/ {2}const canLeaderReview = [^\n]*\n/)[0];
  const antes = m(m(CARD, decl, ''), '  const isLeader =', decl + '  const isLeader =');
  assert.equal(tela(antes).declaradoDepois, false);

  const C = "'can_edit', x, 'can_leader_review', (v_init IS NOT NULL AND EXISTS ( SELECT 1 FROM public.engagements e JOIN public.persons p ON p.id = e.person_id WHERE e.initiative_id = v_init AND e.status = 'active' AND e.role = 'leader' AND p.auth_id = auth.uid())) OR public.can_by_member(v_caller, 'participate_in_governance_review'), 'types', y";
  assert.deepEqual(campoDaTela(C), allTrue(campoDaTela(C)));
  // 4: o campo perde o ramo da governanca
  assert.equal(campoDaTela(m(C, " OR public.can_by_member(v_caller, 'participate_in_governance_review')", '')).revisorDeGovernanca, false);
});
