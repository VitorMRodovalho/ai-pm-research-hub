// tests/contracts/2444-lider-e-autores-avisados-na-hora.test.mjs
// Registrar em "test:behavioural" + "test:contracts" (#1109). NAO em test:structural: le o banco,
// e o guard #1908 exige DB-gated na faixa SERIALIZADA (#1509).
/**
 * O lider e avisado na hora de que ha card para a revisao dele, e a devolucao avisa todos os autores.
 *
 * O CASO (#2444): notify_leader_on_review achava o lider por members.tribe_id + operational_role
 * (modelo legado) e o tipo caia no digest semanal: 0 notificacoes leader_review_requested na
 * historia, 16 cards parados em leader_review desde 27/05 (medido 24/09/2026). A devolucao avisava
 * so assignee_id, a coluna legada e singular (mesma classe do #1903), tambem pelo digest.
 *
 * Exercido em transacao desfeita (24/09/2026) sobre um card real: entrar em leader_review = 1 aviso
 * imediato ao lider da iniciativa, com link para o quadro; devolucao = 1 aviso a cada autor (quem
 * tinha dois papeis recebeu 1), quem devolveu nao recebe.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

function sql(body) {
  return body.split('\n').map((l) => { const i = l.indexOf('--'); return i >= 0 ? l.slice(0, i) : l; })
    .join('\n').replace(/\s+/g, ' ');
}

/** O lider vem do vinculo com a iniciativa do quadro, nunca do modelo legado. */
export function liderPeloVinculo(body) {
  const c = sql(body);
  return {
    vinculo: /JOIN public\.engagements e ON e\.initiative_id = pb\.initiative_id AND e\.status = 'active' AND e\.role = 'leader'/.test(c),
    semLegado: !/tribe_id/.test(c) && !/operational_role/.test(c),
    avisaCadaLider: /LOOP PERFORM public\.create_notification\( v_leader\.id, 'leader_review_requested'/.test(c),
    naoAvisaQuemFez: /m\.id IS DISTINCT FROM v_actor_id/.test(c),
  };
}

/** A devolucao percorre os autores do card (tabela de atribuicoes), menos quem devolveu. */
export function devolucaoAvisaAutores(body) {
  const c = sql(body);
  const ramo = (c.match(/ELSIF p_decision = 'returned' THEN(.*)END IF; END;/) || [])[1] || '';
  return {
    leAtribuicoes: /FROM public\.board_item_assignments bia WHERE bia\.item_id = p_item_id AND bia\.role IN \('author', 'contributor'\)/.test(ramo),
    excluiQuemDevolveu: /x\.mid IS DISTINCT FROM v_caller\.id/.test(ramo),
    tipoProprio: /create_notification\( v_author\.mid, 'leader_review_returned'/.test(ramo),
  };
}

const allTrue = (o) => Object.fromEntries(Object.keys(o).map((k) => [k, true]));

async function corpo(proname) {
  const { data, error } = await sb().rpc('_audit_function_source', { p_proname: proname });
  assert.equal(error, null, `_audit_function_source(${proname}) falhou: ${error?.message ?? ''}`);
  assert.ok(Array.isArray(data) && data.length === 1, `${proname}: esperava 1 sobrecarga, veio ${data?.length}`);
  return data[0].prosrc;
}

test(dbGated ? '#2444: lider pelo vinculo e devolucao a todos os autores, no corpo vivo' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const l = liderPeloVinculo(await corpo('notify_leader_on_review'));
    assert.deepEqual(l, allTrue(l), 'o aviso ao lider voltou ao modelo legado ou perdeu uma regra');
    const d = devolucaoAvisaAutores(await corpo('complete_leader_review'));
    assert.deepEqual(d, allTrue(d), 'a devolucao deixou de avisar os autores do card');
  });

test(dbGated ? '#2444: os dois avisos saem na hora, nao no digest semanal' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    for (const t of ['leader_review_requested', 'leader_review_returned']) {
      const { data, error } = await sb().rpc('_delivery_mode_for', { p_type: t });
      assert.equal(error, null);
      assert.equal(data, 'transactional_immediate', `${t} cairia em ${data}`);
    }
  });

test('#2444 mutacao: cada detector reprova a forma do defeito, pela MESMA funcao', () => {
  const m = (src, a, b) => { const out = src.replace(a, b); assert.notEqual(out, src, `mutacao nao aplicou: ${a}`); return out; };
  const L = `FOR v_leader IN SELECT DISTINCT m.id FROM public.project_boards pb
    JOIN public.engagements e ON e.initiative_id = pb.initiative_id AND e.status = 'active' AND e.role = 'leader'
    JOIN public.members m ON m.person_id = e.person_id WHERE pb.id = NEW.board_id AND m.id IS DISTINCT FROM v_actor_id
    LOOP PERFORM public.create_notification( v_leader.id, 'leader_review_requested', 'x')`;
  assert.deepEqual(liderPeloVinculo(L), allTrue(liderPeloVinculo(L)));
  // 1: volta ao modelo legado (o defeito original)
  assert.equal(liderPeloVinculo(m(L, 'WHERE pb.id = NEW.board_id', "WHERE m.operational_role = 'tribe_leader'")).semLegado, false);
  // 2: avisa quem acabou de agir
  assert.equal(liderPeloVinculo(m(L, ' AND m.id IS DISTINCT FROM v_actor_id', '')).naoAvisaQuemFez, false);

  const D = `ELSIF p_decision = 'returned' THEN UPDATE x;
    FOR v_author IN SELECT DISTINCT x.mid FROM ( SELECT v_item.assignee_id AS mid UNION
      SELECT bia.member_id FROM public.board_item_assignments bia WHERE bia.item_id = p_item_id AND bia.role IN ('author', 'contributor') ) x
      WHERE x.mid IS NOT NULL AND x.mid IS DISTINCT FROM v_caller.id
    LOOP PERFORM public.create_notification( v_author.mid, 'leader_review_returned', 'x'); END LOOP; END IF; END;`;
  assert.deepEqual(devolucaoAvisaAutores(D), allTrue(devolucaoAvisaAutores(D)));
  // 3: so o assignee legado (o defeito original)
  assert.equal(devolucaoAvisaAutores(m(D, "SELECT bia.member_id FROM public.board_item_assignments bia WHERE bia.item_id = p_item_id AND bia.role IN ('author', 'contributor')", 'SELECT NULL')).leAtribuicoes, false);
  // 4: volta ao tipo que cai no digest
  assert.equal(devolucaoAvisaAutores(m(D, "'leader_review_returned'", "'card_moved'")).tipoProprio, false);
  // 5: avisa tambem quem devolveu
  assert.equal(devolucaoAvisaAutores(m(D, ' AND x.mid IS DISTINCT FROM v_caller.id', '')).excluiQuemDevolveu, false);
});
