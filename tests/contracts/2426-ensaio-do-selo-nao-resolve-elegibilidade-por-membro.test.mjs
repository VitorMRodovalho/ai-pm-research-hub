// tests/contracts/2426-ensaio-do-selo-nao-resolve-elegibilidade-por-membro.test.mjs
// Registrar em "test:behavioural" + "test:contracts" (#1109). Le o corpo VIVO pelo banco, entao
// e DB-gated e vai na faixa SERIALIZADA (#1509 / guard #1908).
/**
 * O selo resolve elegibilidade UMA vez por evento, nunca uma vez por membro.
 *
 * O CASO (#2426): `_seal_event_attendance_apply` chamava `_attendance_eligible_events(m.id, NULL)`
 * DENTRO da coorte — por membro. Cada chamada varre os eventos da janela do ciclo e avalia
 * `_event_end_instant` em cada um, so para perguntar se ESTE evento esta na lista.
 *
 * Medido em 23/09/2026: 1009 ms por evento, dos quais **981 ms (97%)** nas 76 chamadas.
 * 76 membros x 198 eventos = 15.048 avaliacoes por evento selado. O laco de
 * `seal_attendance_window_cron` fazia isso 9 vezes: ~9081 ms, contra teto de **8000 ms** do role
 * `authenticator`/`authenticated`. Nao era flake — era degrau: ate 21/09 o laco tinha 5 eventos
 * (~5,0 s) e passava; em 22 e 23/09 quatro eventos cruzaram a carencia de 14 dias quase juntos.
 *
 * ⚠️ AS TRES ASSERCOES, E POR QUE CADA UMA EXISTE
 *
 * 1. A funcao nao pode voltar a chamar `_attendance_eligible_events`. E a causa direta do custo,
 *    e ela volta facil: e a funcao "certa" de perguntar elegibilidade, so que pelo eixo errado.
 *
 * 2. A GUARDA DE JANELA tem de existir. `_attendance_eligible_events` filtrava pela janela do
 *    ciclo; a funcao chamadora NAO filtra. Medido em 5 eventos anteriores ao ciclo: a inversao
 *    sem guarda **inventaria 32 pares** onde o caminho antigo da 0 — ou seja, selar um evento
 *    antigo a mao gravaria 32 FALTAS que hoje nao existem, no historico de presenca de gente real.
 *    Esta assercao e a unica coisa entre o conserto e essa regressao.
 *
 * 3. O ENSAIO E O ATO tem de carregar o MESMO predicado de coorte. Sao dois trechos distintos (o
 *    CTE `coorte` e o `INSERT ... SELECT`), e antes os dois usavam o mesmo `EXISTS`. Quem mexer em
 *    um e esquecer o outro faz o ensaio prometer um numero e o ato escrever outro — que e
 *    exatamente o que `#1710-D C: o ensaio roda pela mesma funcao que executa` existe para impedir.
 *
 * Cross-ref: #2426, #1710, #1727, #1729, #1948.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

/** Recorta o CTE `coorte` — o bloco que o ENSAIO usa para contar. */
export function blocoDoEnsaio(corpo) {
  const m = corpo.match(/WITH\s+coorte\s+AS\s*\(([\s\S]*?)\n\s*\)\s*\n\s*SELECT\s+count/i);
  return m ? m[1] : null;
}

/** Recorta o `INSERT INTO public.attendance ... ON CONFLICT` — o bloco que o ATO executa. */
export function blocoDoAto(corpo) {
  const m = corpo.match(/INSERT\s+INTO\s+public\.attendance\b([\s\S]*?)ON\s+CONFLICT/i);
  return m ? m[1] : null;
}

/**
 * Normaliza um predicado de coorte para comparar ensaio x ato: tira espacos, caixa, e os apelidos
 * de tabela (`m.id` no CTE vira o mesmo `m.id` no INSERT, mas o resto do trecho difere).
 */
function predicadoDeMembro(bloco) {
  if (bloco === null) return null;
  const m = bloco.match(/v_type\s+IN\s*\(\s*'geral'\s*,\s*'kickoff'\s*\)([\s\S]*?)\)\s*$/i)
        || bloco.match(/v_type\s+IN\s*\(\s*'geral'\s*,\s*'kickoff'\s*\)([\s\S]*)/i);
  if (!m) return null;
  return ("v_type IN ('geral','kickoff')" + m[1])
    .replace(/\s+/g, ' ')
    .replace(/\(\s+/g, '(')
    .replace(/\s+\)/g, ')')
    .trim()
    .toLowerCase();
}

/**
 * Violacoes. Lista vazia = saudavel.
 *
 * Recebe o corpo como dado puro: e a MESMA funcao que julga o corpo vivo e os adulterados do teste
 * de mutacao. Mutacao que nao passa pelo avaliador e parafrase.
 */
export function violacoes(prosrcCru) {
  const corpo = maskLineComments(prosrcCru);
  const v = [];

  // 1. a causa direta do custo
  if (/_attendance_eligible_events/i.test(corpo)) {
    v.push(
      '_seal_event_attendance_apply voltou a chamar _attendance_eligible_events. Medido em 23/09: ' +
      '981 de 1009 ms por evento, e o laco de 9 eventos estoura o teto de 8s do role (#2426).',
    );
  }

  // 2. a guarda de janela — condicao AMARRADA ao resultado, dentro do bloco que decide
  const guarda = corpo.match(
    /IF\s+v_win_start\s+IS\s+NULL\s+OR\s+v_date\s*<\s*v_win_start\s+OR\s+v_date\s*>\s*v_win_end\s+THEN([\s\S]*?)END\s+IF\s*;/i,
  );
  if (!guarda) {
    v.push(
      'a guarda de janela do ciclo sumiu: selar um evento ANTERIOR ao ciclo voltaria a gravar ' +
      'faltas que hoje nao existem (medido: 32 pares inventados em 5 eventos antigos) (#2426).',
    );
  } else if (!/skipped_empty_cohort/i.test(guarda[1])) {
    v.push(
      'a guarda de janela existe mas nao devolve `skipped_empty_cohort`: fora da janela o desfecho ' +
      'tem de ser coorte VAZIA, igual ao comportamento antigo (#2426).',
    );
  }

  // 3. ensaio e ato com o MESMO predicado
  const ensaio = blocoDoEnsaio(corpo);
  const ato = blocoDoAto(corpo);
  if (ensaio === null) v.push('nao achei o CTE `coorte`: o guard ficou sem o bloco do ENSAIO (#2426)');
  if (ato === null) v.push('nao achei o INSERT em public.attendance: o guard ficou sem o bloco do ATO (#2426)');
  if (ensaio !== null && ato !== null) {
    const pe = predicadoDeMembro(ensaio);
    const pa = predicadoDeMembro(ato);
    if (pe === null || pa === null) {
      v.push('um dos dois blocos nao tem o predicado de coorte por v_type: ensaio e ato divergiram (#2426)');
    } else if (pe !== pa) {
      v.push(
        'o predicado de coorte do ENSAIO difere do predicado do ATO. O ensaio prometeria um numero ' +
        `e o ato escreveria outro (#2426).\n  ensaio: ${pe}\n  ato   : ${pa}`,
      );
    }
  }
  return v;
}

test('#2426 — o corpo VIVO resolve elegibilidade por EVENTO, com guarda de janela e ensaio==ato',
  { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb().rpc('_audit_function_source', {
      p_proname: '_seal_event_attendance_apply',
    });
    assert.ifError(error);
    assert.ok(data?.length > 0, '_seal_event_attendance_apply nao existe no banco');
    assert.equal(data.length, 1, `sobrecarga inesperada: ${data.length} assinaturas`);
    assert.equal(data[0].is_secdef, true, 'a funcao perdeu SECURITY DEFINER');

    assert.deepEqual(violacoes(data[0].prosrc), []);
  });

test('#2426 mutacao — o detector reprova cada defeito, pela MESMA funcao', () => {
  const SAUDAVEL = `
DECLARE
  v_win_start date; v_win_end date; v_tribe_id int;
BEGIN
  IF v_win_start IS NULL OR v_date < v_win_start OR v_date > v_win_end THEN
    RETURN jsonb_build_object('reason', 'skipped_empty_cohort');
  END IF;

  WITH coorte AS (
    SELECT m.id FROM public.members m
    WHERE m.is_active = true
      AND (
        v_type IN ('geral','kickoff')
        OR (v_type = 'tribo' AND v_tribe_id IS NOT NULL AND public.get_member_tribe(m.id) = v_tribe_id)
        OR (v_type = 'lideranca' AND public.can_by_member(m.id, 'manage_event'))
      )
  )
  SELECT count(*) INTO v_eligible FROM coorte c;

  INSERT INTO public.attendance (event_id, member_id)
  SELECT p_event_id, m.id FROM public.members m
  WHERE m.is_active = true
    AND (
      v_type IN ('geral','kickoff')
      OR (v_type = 'tribo' AND v_tribe_id IS NOT NULL AND public.get_member_tribe(m.id) = v_tribe_id)
      OR (v_type = 'lideranca' AND public.can_by_member(m.id, 'manage_event'))
    )
  ON CONFLICT DO NOTHING;
END;`;
  assert.deepEqual(violacoes(SAUDAVEL), [], 'controle sem mutacao: o corpo consertado nao viola');

  // Mutacao 1 — o estado EXATO de antes do conserto: volta a chamar por membro.
  const m1 = SAUDAVEL.replace(
    'public.get_member_tribe(m.id) = v_tribe_id',
    'EXISTS (SELECT 1 FROM public._attendance_eligible_events(m.id, NULL) ee WHERE ee.event_id = p_event_id)');
  assert.notEqual(m1, SAUDAVEL, 'a mutacao 1 precisa ter MUDADO o corpo');
  assert.match(violacoes(m1).join(' | '), /voltou a chamar _attendance_eligible_events/,
    'mutacao 1: a chamada por membro tem de reprovar');

  // Mutacao 2 — some a guarda de janela (a regressao das 32 faltas falsas).
  const m2 = SAUDAVEL.replace(/IF v_win_start IS NULL[\s\S]*?END IF;/, '');
  assert.notEqual(m2, SAUDAVEL, 'a mutacao 2 precisa ter MUDADO o corpo');
  assert.match(violacoes(m2).join(' | '), /guarda de janela do ciclo sumiu/,
    'mutacao 2: sem a guarda de janela tem de reprovar');

  // Mutacao 3 — a guarda existe mas para de devolver coorte vazia.
  const m3 = SAUDAVEL.replace("'skipped_empty_cohort'", "'seguiu_em_frente'");
  assert.match(violacoes(m3).join(' | '), /nao devolve `skipped_empty_cohort`/,
    'mutacao 3: guarda que nao esvazia a coorte tem de reprovar');

  // Mutacao 4 — a MAIS PERIGOSA: mexem no ATO e esquecem o ENSAIO. Nenhuma das outras assercoes
  // pegaria isso, porque as duas metades continuam validas isoladamente.
  const m4 = SAUDAVEL.replace(
    /INSERT INTO public\.attendance[\s\S]*?ON CONFLICT/,
    `INSERT INTO public.attendance (event_id, member_id)
  SELECT p_event_id, m.id FROM public.members m
  WHERE m.is_active = true
    AND (
      v_type IN ('geral','kickoff')
      OR (v_type = 'tribo' AND v_tribe_id IS NOT NULL)
    )
  ON CONFLICT`);
  assert.notEqual(m4, SAUDAVEL, 'a mutacao 4 precisa ter MUDADO o corpo');
  assert.match(violacoes(m4).join(' | '), /predicado de coorte do ENSAIO difere/,
    'mutacao 4: ensaio e ato divergentes tem de reprovar');

  // Controle sem mutacao, no fim.
  assert.deepEqual(violacoes(SAUDAVEL), [], 'controle final');
});
