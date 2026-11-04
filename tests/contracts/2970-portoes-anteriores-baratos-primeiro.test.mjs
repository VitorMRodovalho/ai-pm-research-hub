// tests/contracts/2970-portoes-anteriores-baratos-primeiro.test.mjs
/**
 * #2970: _prior_gates_satisfied olha primeiro os portões anteriores baratos e para no primeiro não atingido.
 *
 * "Todos os portões anteriores atingidos" é uma conjunção: a ordem não muda a resposta, só o custo. O limiar 'all' é
 * o único que pode varrer os membros ativos (quando já está atingido), então fica por último. A forma em SQL que esta
 * substitui (NOT EXISTS) não deixava escolher a ordem: o planejador descarta ORDER BY dentro de EXISTS. A forma nova
 * é um laço em plpgsql.
 *
 * O guard afirma, sobre o corpo mais novo de _prior_gates_satisfied:
 *   1. o cabeçalho: mesma assinatura, plpgsql, STABLE SECURITY DEFINER, search_path public, pg_temp;
 *   2. a ordem do portão pedido sai da MESMA cadeia e do tipo pedido;
 *   3. o laço percorre só os portões da mesma cadeia com ordem menor, 'all' por último e, dentro de cada grupo, pela
 *      ordem do portão;
 *   4. o primeiro anterior não atingido devolve false; o true só sai depois do laço inteiro;
 *   5. o leitor recusa as formas que mudam a resposta (amostras no próprio arquivo).
 *
 * A equivalência no banco não é medida aqui: o guard 654 compara, ao vivo no CI, _prior_gates_satisfied com "todos os
 * anteriores atingidos" em todo portão de toda cadeia ativa. A comparação com a forma antiga, portão a portão, é o P1
 * da verificação do apply.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { maskLineComments, latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const espaco = (s) => s.replace(/\s+/g, ' ').trim();

/** Corpo sem comentários e com espaço normalizado. */
export const normal = (body) => espaco(maskLineComments(body));

const ORDEM_DO_PEDIDO =
  "SELECT (g->>'order')::int INTO v_ordem FROM public.approval_chains ac2, jsonb_array_elements(ac2.gates) g " +
  "WHERE ac2.id = p_chain_id AND g->>'kind' = p_gate_kind LIMIT 1;";

const LACO =
  'FOR v_gate IN SELECT gp FROM public.approval_chains ac, jsonb_array_elements(ac.gates) gp ' +
  "WHERE ac.id = p_chain_id AND (gp->>'order')::int < v_ordem " +
  "ORDER BY ((gp->>'threshold') = 'all'), (gp->>'order')::int LOOP " +
  'IF NOT public._gate_threshold_met(p_chain_id, v_gate) THEN RETURN false; END IF; END LOOP;';

/**
 * A forma inteira do corpo, ligada: a ordem do pedido, depois o laço, depois o único RETURN true. Devolve null se o
 * corpo for outro. Comparação exata (sem regex) de propósito: qualquer cláusula a mais ou a menos muda a resposta ou
 * a ordem, e as duas coisas são o que este guard protege.
 */
export function formaDoCorpo(c) {
  const esperado =
    'DECLARE v_ordem int; v_gate jsonb; BEGIN ' + ORDEM_DO_PEDIDO + ' ' + LACO + ' RETURN true; END;';
  return c === esperado ? { ordem: ORDEM_DO_PEDIDO, laco: LACO } : null;
}

const CAP = latestFunctionCapture(ROOT, '_prior_gates_satisfied');
const CORPO = normal(CAP.body);
const CABECALHO = espaco(maskLineComments(CAP.block.slice(0, CAP.block.indexOf('$function$'))));

test('cabeçalho: mesma assinatura, plpgsql, STABLE SECURITY DEFINER, search_path public, pg_temp', () => {
  assert.match(
    CABECALHO,
    /FUNCTION public\._prior_gates_satisfied\(p_chain_id uuid, p_gate_kind text\) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS$/,
    `${CAP.file}: cabeçalho diferente do esperado. Lido:\n${CABECALHO}`,
  );
});

test('a ordem do portão pedido sai da mesma cadeia e do tipo pedido', () => {
  const ini = CORPO.indexOf('INTO v_ordem');
  assert.notEqual(ini, -1, `${CAP.file}: v_ordem não é lido`);
  assert.equal(
    CORPO.split('INTO v_ordem').length - 1, 1,
    `${CAP.file}: v_ordem é atribuído mais de uma vez`,
  );
  assert.ok(
    CORPO.includes(ORDEM_DO_PEDIDO),
    `${CAP.file}: a ordem do pedido não é "(order) do portão com kind = p_gate_kind na cadeia p_chain_id, LIMIT 1". Corpo lido:\n${CORPO}`,
  );
});

test("o laço percorre os anteriores da mesma cadeia, 'all' por último, e o primeiro não atingido devolve false", () => {
  assert.ok(
    CORPO.includes(LACO),
    `${CAP.file}: o laço não é "anteriores da cadeia (ordem < v_ordem), 'all' por último, IF NOT _gate_threshold_met THEN RETURN false". Corpo lido:\n${CORPO}`,
  );
});

test('o true só sai depois do laço inteiro, e o corpo não tem nada além disso', () => {
  assert.ok(
    formaDoCorpo(CORPO),
    `${CAP.file}: o corpo não é "DECLARE; ordem do pedido; laço; RETURN true". Corpo lido:\n${CORPO}`,
  );
});

test('o leitor recusa as formas que mudam a resposta ou a ordem', () => {
  const certo = normal(CAP.body);
  assert.ok(formaDoCorpo(certo), 'controle: o corpo vigente precisa ser aceito');
  const amostras = {
    'EXIT no lugar de RETURN false (cai no RETURN true)': certo.replace('THEN RETURN false;', 'THEN EXIT;'),
    "'all' primeiro": certo.replace("ORDER BY ((gp->>'threshold') = 'all'),", "ORDER BY ((gp->>'threshold') = 'all') DESC,"),
    'sem a ordem por limiar': certo.replace("ORDER BY ((gp->>'threshold') = 'all'), (gp->>'order')::int", "ORDER BY (gp->>'order')::int"),
    'inclui o próprio portão': certo.replace('< v_ordem', '<= v_ordem'),
    'laço sem filtro de cadeia': certo.replace('WHERE ac.id = p_chain_id AND ', 'WHERE '),
    'ordem do pedido em qualquer cadeia': certo.replace('WHERE ac2.id = p_chain_id AND ', 'WHERE '),
    'RETURN false no fim': certo.replace(' RETURN true; END;', ' RETURN false; END;'),
    'portão atingido reprova': certo.replace('IF NOT public._gate_threshold_met', 'IF public._gate_threshold_met'),
    'forma em SQL antiga':
      "SELECT NOT EXISTS ( SELECT 1 FROM approval_chains ac, jsonb_array_elements(ac.gates) gp WHERE ac.id = p_chain_id " +
      "AND (gp->>'order')::int < ( SELECT (g->>'order')::int FROM approval_chains ac2, jsonb_array_elements(ac2.gates) g " +
      "WHERE ac2.id = p_chain_id AND g->>'kind' = p_gate_kind LIMIT 1 ) AND NOT public._gate_threshold_met(p_chain_id, gp) );",
  };
  for (const [nome, corpo] of Object.entries(amostras)) {
    assert.notEqual(corpo, certo, `amostra "${nome}" não mudou o corpo: a amostra está errada`);
    assert.equal(formaDoCorpo(corpo), null, `o leitor aceitou a amostra "${nome}"`);
  }
});
