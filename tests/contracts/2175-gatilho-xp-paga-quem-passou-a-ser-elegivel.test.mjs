// tests/contracts/2175-gatilho-xp-paga-quem-passou-a-ser-elegivel.test.mjs
// Register in BOTH the "test:behavioural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2175 — o gatilho de XP de entregável passa a pagar quem PASSOU A SER elegível.
 *
 * MECANISMO: a #1880 alargou o `AFTER UPDATE OF` para vigiar as três colunas do predicado que
 * podem virar depois do status, e declarou no cabeçalho que não mexeria no corpo. O corpo exigia
 * `OLD.status IS DISTINCT FROM 'done'`, então num card que JÁ está `done` a guarda barrava tudo:
 * o gatilho disparava e não pagava. A classe que a migration dizia fechar continuou aberta.
 *
 * ⚠️ POR QUE ESTE GUARD MEDE O CORPO SEM COMENTÁRIOS. A própria migration da #2175 cita o defeito
 * verbatim no cabeçalho, para explicá-lo. Um guard que procurasse a string `OLD.status IS DISTINCT
 * FROM 'done'` no texto cru casaria o comentário que existe para descrever o anti-padrão, e
 * reprovaria a correção. É a classe do #1910, e já mordeu três guards em 03/09.
 *
 * ⚠️ O CASO DE NULL É O QUE ERRARIA EM SILÊNCIO. `OLD.status = 'done'` devolve NULL quando o status
 * anterior é nulo, e `NOT (NULL AND ...)` é NULL, o que faz o IF não disparar sem erro nenhum. Por
 * isso a comparação usa `IS NOT DISTINCT FROM`, e este arquivo afirma isso explicitamente: trocar
 * de volta por `=` compila, passa em qualquer teste de "o card certo paga", e cega o caso da borda.
 *
 * Cross-ref: #2175, #1880 (a migration que alargou o gatilho e não mexeu no corpo), #1147 (o
 * contrato que ficou verde por ausência de casos e por isso não pegou nada).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

const FN = latestFunctionCapture(ROOT, 'trg_board_item_deliverable_xp');

/** Tira comentários de linha SQL. Sem isto o guard casa o próprio texto que explica o defeito. */
const semComentarios = (sql) => sql.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

test('#2175 estático: o corpo EXECUTÁVEL não exige mais transição de status', () => {
  const b = semComentarios(FN.body);
  assert.ok(
    !/OLD\.status\s+IS\s+DISTINCT\s+FROM\s+'done'/i.test(b),
    'a guarda antiga voltou: exigir transição de status cega o gatilho para a virada das outras colunas',
  );
});

test('#2175 estático: a comparação de status anterior é NULL-safe', () => {
  const b = semComentarios(FN.body);
  assert.ok(
    /OLD\.status\s+IS\s+NOT\s+DISTINCT\s+FROM\s+'done'/i.test(b),
    'a comparação de OLD.status precisa ser IS NOT DISTINCT FROM: com `=` ela vira NULL e o IF não dispara',
  );
});

test('#2175 estático: a guarda avalia o PREDICADO INTEIRO em OLD, não uma coluna dele', () => {
  // Se alguém "simplificar" olhando só a flag de portfólio, o card que ganha assignee volta a não pagar.
  const b = semComentarios(FN.body);
  const olds = b.match(/OLD\.[a-z_]+/gi) || [];
  for (const col of ['OLD.status', 'OLD.is_portfolio_item', 'OLD.is_mirror', 'OLD.assignee_id']) {
    assert.ok(olds.some((o) => o.toLowerCase() === col.toLowerCase()),
      `${col} sumiu da guarda: o predicado de elegibilidade tem quatro colunas, não uma`);
  }
});

test('#2175 estático: o guard REPROVA se o defeito for reintroduzido (injeção)', () => {
  // Sem esta injeção, os testes acima passariam por acidente numa refatoração que apagasse a guarda
  // inteira. O que se afirma aqui é que eles conseguem falhar.
  const comDefeito = semComentarios(FN.body).replace(
    /OLD\.status\s+IS\s+NOT\s+DISTINCT\s+FROM\s+'done'/i,
    "OLD.status IS DISTINCT FROM 'done'",
  );
  assert.ok(/OLD\.status\s+IS\s+DISTINCT\s+FROM\s+'done'/i.test(comDefeito),
    'a injeção não produziu o defeito — o teste acima estaria afirmando sobre nada');
  assert.ok(!/OLD\.status\s+IS\s+NOT\s+DISTINCT\s+FROM\s+'done'/i.test(comDefeito),
    'a injeção deixou a forma correta no corpo: o guard não distinguiria os dois estados');
});

test('#2175 vivo: nenhum card elegível ficou sem pagar (ratchet em 0)',
  { skip: dbGated ? false : skipMsg }, async () => {
  const s = sb();
  const { data: boards, error: eb } = await s.from('project_boards').select('id').eq('board_scope', 'tribe');
  assert.ifError(eb);
  const ids = (boards ?? []).map((b) => b.id);
  assert.ok(ids.length > 0, 'nenhum quadro de tribo — o guard passaria por vacuidade');

  const { data: cards, error: ec } = await s.from('board_items')
    .select('id, assignee_id')
    .eq('status', 'done').eq('is_portfolio_item', true)
    .not('assignee_id', 'is', null).in('board_id', ids);
  assert.ifError(ec);
  const elegiveis = (cards ?? []).filter((c) => c.assignee_id);
  assert.ok(elegiveis.length > 0, 'nenhum card elegível — o guard não mediria nada');

  const { data: pagos, error: ep } = await s.from('gamification_points')
    .select('ref_id').eq('ref_kind', 'board_item').in('ref_id', elegiveis.map((c) => c.id));
  assert.ifError(ep);
  const pagosSet = new Set((pagos ?? []).map((p) => p.ref_id));
  const naoPagos = elegiveis.filter((c) => !pagosSet.has(c.id));

  // CONTROLE POSITIVO: sem ele, "0 não pagos" seria indistinguível de "a junção não enxerga nada".
  assert.ok(pagosSet.size > 0,
    'nenhum card elegível aparece como pago — a junção por ref_kind/ref_id não está enxergando');
  assert.equal(naoPagos.length, 0,
    `${naoPagos.length} cards elegíveis sem XP de entregável (esperado 0). ` +
    'Se subiu, algum caminho está tornando card elegível sem o gatilho pagar.');
});
