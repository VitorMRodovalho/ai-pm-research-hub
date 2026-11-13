// tests/contracts/3052-marcar-a-propria-presenca-segue-o-check-in.test.mjs
/**
 * #3052: `mark_member_present` no ramo de autoatendimento segue a regra do check-in proprio.
 *
 * SINTOMA: o ramo `v_caller_id = p_member_id` nao checava nada, e por ele um membro sem
 * `manage_event` ficou presente num encontro 5 dias no futuro, contornando a janela, a audiencia
 * e (desde #3050) o status que `register_own_presence` aplica.
 *
 * REGRA: dentro do ramo proprio, quando a marcacao e de PRESENCA e quem marca nao tem a capacidade
 * manage_event ESCOPADA ao evento (`_manage_event_scope_ok`; o Path Y de `_can_manage_event`, #3054,
 * nao conta), a decisao e de `register_own_presence`, e a recusa dela volta antes do INSERT. Uma implementacao
 * da regra so: o detector reprova copia local de janela ou de status neste corpo.
 *
 * O detector recebe o corpo como dado: julga a captura corrente e as adulteradas pela mesma funcao.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();

export function captura() {
  return latestFunctionCapture(ROOT, 'mark_member_present').body;
}

/** Violacoes. Lista vazia = saudavel. */
export function violacoes(corpoBruto) {
  const corpo = maskLineComments(corpoBruto).replace(/\s+/g, ' ');
  const v = [];
  const ramo = corpo.match(/IF v_caller_id = p_member_id THEN(.*?)ELSIF NOT public\._can_manage_event\(p_event_id\) THEN/i);
  if (!ramo) return ['ramo de autoatendimento ausente'];
  const r = ramo[1];
  const delega = /IF p_present AND NOT public\._manage_event_scope_ok\(v_caller_id, p_event_id\) THEN v_gate := public\.register_own_presence\(p_event_id\); IF NOT COALESCE\(\(v_gate ->> 'success'\)::boolean, false\) THEN RETURN v_gate; END IF; END IF;/i;
  if (!delega.test(r)) v.push('o ramo proprio nao delega a presenca a register_own_presence com retorno da recusa');
  if (/self_checkin_window_hours|'cancelled'|event_audience_rules/i.test(corpo)) {
    v.push('regra do check-in copiada neste corpo (deveria viver so em register_own_presence)');
  }
  const posRamo = corpo.search(/IF v_caller_id = p_member_id THEN/i);
  const posInsert = corpo.search(/INSERT INTO public\.attendance/i);
  if (posInsert < 0 || posInsert < posRamo) v.push('INSERT antes do ramo de autoatendimento');
  return v;
}

test('#3052: captura corrente delega a presenca propria a register_own_presence', () => {
  assert.deepEqual(violacoes(captura()), []);
});

test('#3052: mutacoes fazem o detector reprovar', () => {
  const corpo = captura();
  const bloco = /IF p_present AND NOT public\._manage_event_scope_ok\(v_caller_id, p_event_id\) THEN[\s\S]*?RETURN v_gate;\s*END IF;\s*END IF;/i;
  const mutacoes = {
    'ramo volta a NULL': corpo.replace(bloco, 'NULL;'),
    'recusa engolida': corpo.replace(/RETURN v_gate;/i, 'NULL;'),
    'delegacao vira so-para-gestor': corpo.replace(/IF p_present AND NOT public\._manage_event_scope_ok/i, 'IF p_present AND public._manage_event_scope_ok'),
    'Path Y volta a escapar': corpo.replace(/IF p_present AND NOT public\._manage_event_scope_ok\(v_caller_id, p_event_id\)/i, 'IF p_present AND NOT public._can_manage_event(p_event_id)'),
    'sucesso presumido': corpo.replace(/COALESCE\(\(v_gate ->> 'success'\)::boolean, false\)/i, "COALESCE((v_gate ->> 'success')::boolean, true) OR true"),
    'regra copiada': corpo.replace(/v_gate := public\.register_own_presence\(p_event_id\);/i,
      "v_gate := public.register_own_presence(p_event_id); IF (SELECT status FROM public.events WHERE id = p_event_id) = 'cancelled' THEN RETURN v_gate; END IF;"),
    'ramo em comentario': corpo.replace(bloco, (x) => x.split('\n').map((l) => '-- ' + l).join('\n') + '\nNULL;'),
  };
  for (const [nome, mutado] of Object.entries(mutacoes)) {
    assert.notEqual(mutado, corpo, `mutacao "${nome}" nao alterou o corpo`);
    assert.ok(violacoes(mutado).length > 0, `mutacao "${nome}" passou no detector`);
  }
});
