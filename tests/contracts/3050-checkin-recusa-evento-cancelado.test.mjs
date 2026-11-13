// tests/contracts/3050-checkin-recusa-evento-cancelado.test.mjs
/**
 * #3050: `register_own_presence` recusa evento cancelado, para todos.
 *
 * SINTOMA: uma instancia cancelada de uma serie antiga, no mesmo slot de uma serie ativa, aceitou
 * check-in proprio; a pessoa ficou presente nos dois encontros do slot e o guard #1536 reprovou o
 * `validate` de uma PR sem relacao.
 *
 * REGRA: o status do evento e lido na MESMA consulta que confirma a existencia, e a recusa
 * (`event_cancelled`, success false) acontece ANTES do desvio de quem tem `manage_event` e antes do
 * INSERT. Recusa dentro do bloco `IF NOT v_is_admin` deixaria o gestor marcar a si mesmo num
 * encontro que nao aconteceu.
 *
 * O detector recebe o corpo como dado: julga a captura corrente e as adulteradas pela mesma funcao.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();

export function captura() {
  return latestFunctionCapture(ROOT, 'register_own_presence').body;
}

/** Violacoes. Lista vazia = saudavel. */
export function violacoes(corpoBruto) {
  const corpo = maskLineComments(corpoBruto);
  const v = [];
  const leStatus = /SELECT\s+date\s*,\s*status\s+INTO\s+v_event_date\s*,\s*v_event_status\s+FROM\s+public\.events\s+WHERE\s+id\s*=\s*p_event_id/i;
  if (!leStatus.test(corpo)) v.push('o status do evento nao e lido junto com a data');

  const recusa = /IF\s+v_event_status\s*=\s*'cancelled'\s+THEN\s+RETURN\s+json_build_object\(\s*'success'\s*,\s*false\s*,\s*'error'\s*,\s*'event_cancelled'/i;
  const m = recusa.exec(corpo);
  if (!m) {
    v.push('nao ha recusa de evento cancelado que devolva event_cancelled');
    return v;
  }
  const desvioAdmin = corpo.search(/IF\s+NOT\s+v_is_admin\s+THEN/i);
  if (desvioAdmin < 0 || m.index > desvioAdmin) v.push('a recusa fica dentro ou depois do desvio de manage_event');
  const insert = corpo.search(/INSERT\s+INTO\s+public\.attendance/i);
  if (insert < 0 || m.index > insert) v.push('a recusa vem depois do INSERT');
  return v;
}

test('#3050: captura corrente recusa evento cancelado antes do desvio do gestor e do INSERT', () => {
  assert.deepEqual(violacoes(captura()), []);
});

test('#3050: mutacoes fazem o detector reprovar', () => {
  const corpo = captura();
  const mutacoes = {
    'status nao lido': corpo.replace(/SELECT\s+date\s*,\s*status\s+INTO\s+v_event_date\s*,\s*v_event_status/i, 'SELECT date INTO v_event_date'),
    'recusa removida': corpo.replace(/IF\s+v_event_status\s*=\s*'cancelled'\s+THEN[\s\S]*?END IF;/i, ''),
    'recusa vira sucesso': corpo.replace(/'success'\s*,\s*false\s*,\s*'error'\s*,\s*'event_cancelled'/i, "'success', true, 'error', 'event_cancelled'"),
    'recusa so para nao-gestor': (() => {
      const bloco = corpo.match(/\s*IF\s+v_event_status\s*=\s*'cancelled'\s+THEN[\s\S]*?END IF;/i)[0];
      return corpo.replace(bloco, '').replace(/IF\s+NOT\s+v_is_admin\s+THEN/i, (x) => x + bloco);
    })(),
    'recusa so em comentario': corpo.replace(/IF\s+v_event_status\s*=\s*'cancelled'\s+THEN[\s\S]*?END IF;/i,
      (x) => x.split('\n').map((l) => '-- ' + l).join('\n')),
  };
  for (const [nome, mutado] of Object.entries(mutacoes)) {
    assert.notEqual(mutado, corpo, `mutacao "${nome}" nao alterou o corpo`);
    assert.ok(violacoes(mutado).length > 0, `mutacao "${nome}" passou no detector`);
  }
});
