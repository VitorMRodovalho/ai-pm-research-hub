/**
 * #3104: o check-in não diz "success" sobre uma falta que continua falta.
 *
 * register_own_presence fazia ON CONFLICT DO UPDATE SET checked_in_at = now() e devolvia success.
 * Com uma linha present = false já gravada, present continuava false e as telas mostravam
 * "Presença registrada". Agora, com linha existente, o que está lançado decide: já presente fica;
 * falta presumida pelo selo vira presença; qualquer outra falta ou justificativa volta recusada.
 *
 * O guard lê a ÚLTIMA migration que define a função e amarra cada condição ao resultado dela,
 * dentro do mesmo bloco. Comentários SQL saem antes do assert.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskLineComments as mask } from '../helpers/guard-pin-staleness.mjs';

const DIR = resolve(process.cwd(), 'supabase/migrations');
const HEAD = 'CREATE OR REPLACE FUNCTION public.register_own_presence(';

function latestBody() {
  const files = readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort()
    .filter((f) => mask(readFileSync(resolve(DIR, f), 'utf8')).includes(HEAD));
  assert.ok(files.length > 0, 'alguma migration define register_own_presence');
  const file = files.at(-1);
  const sql = mask(readFileSync(resolve(DIR, file), 'utf8'));
  assert.equal(sql.split(HEAD).length - 1, 1, `${file}: a função é definida uma vez`);
  const start = sql.indexOf(HEAD);
  const end = sql.indexOf('$function$;', start);
  assert.ok(end > start, `${file}: fim do corpo`);
  return { file, body: sql.slice(start, end) };
}

test('#3104: sem linha, a presença nasce; com linha, o conflito não muda nada e o success só vem se inseriu', () => {
  const { file, body } = latestBody();
  assert.match(body,
    /INSERT INTO public\.attendance \(event_id, member_id, checked_in_at, present, excused\)\s+VALUES \(p_event_id, v_member_id, now\(\), true, false\)\s+ON CONFLICT \(event_id, member_id\) DO NOTHING;\s+GET DIAGNOSTICS v_inserted = ROW_COUNT;\s+IF v_inserted > 0 THEN\s+RETURN json_build_object\('success', true, 'member_id', v_member_id\);\s+END IF;/,
    `${file}: a inserção não atualiza no conflito, e o success de presença nova depende da linha inserida`);
  assert.doesNotMatch(body, /ON CONFLICT \(event_id, member_id\)\s+DO UPDATE/,
    `${file}: nenhum DO UPDATE no conflito, que era o que tocava só checked_in_at e dizia success`);
});

test('#3104: linha já presente devolve success sem mexer em present', () => {
  const { file, body } = latestBody();
  const m = body.match(/IF v_present THEN([\s\S]*?)END IF;/);
  assert.ok(m, `${file}: bloco da linha já presente`);
  assert.match(m[1], /RETURN json_build_object\('success', true, 'member_id', v_member_id, 'already_present', true\);/,
    `${file}: já presente devolve success com already_present`);
  assert.doesNotMatch(m[1], /present = /, `${file}: o bloco da linha já presente não regrava present`);
});

test('#3104: falta presumida pelo selo vira presença, pelo mesmo critério do unseal', () => {
  const { file, body } = latestBody();
  assert.match(body,
    /IF NOT v_excused AND v_notes IS NOT DISTINCT FROM public\._roster_seal_marker\(\) THEN\s+UPDATE public\.attendance SET present = true, checked_in_at = now\(\), updated_at = now\(\)\s+WHERE event_id = p_event_id AND member_id = v_member_id;\s+RETURN json_build_object\('success', true, 'member_id', v_member_id, 'replaced', 'presumed_absence'\);\s+END IF;/,
    `${file}: só a linha do selo, sem justificativa, é corrigida para presente, e só então volta success`);
  const sel = body.search(/SELECT a\.present, COALESCE\(a\.excused, false\), a\.notes\s+INTO v_present, v_excused, v_notes\s+FROM public\.attendance a\s+WHERE a\.event_id = p_event_id AND a\.member_id = v_member_id\s+FOR UPDATE;/);
  assert.ok(sel > 0 && sel < body.indexOf('IF v_present THEN'), `${file}: a linha existente é lida, travada, antes de decidir`);
});

test('#3104: outra falta ou justificativa volta recusada, depois de todos os ramos de success', () => {
  const { file, body } = latestBody();
  const refusal = body.search(/RETURN json_build_object\('success', false, 'error', 'attendance_already_recorded',\s+'recorded_as', CASE WHEN v_excused THEN 'excused' ELSE 'absent' END,\s+'message', CASE WHEN v_excused/);
  assert.ok(refusal > 0, `${file}: recusa attendance_already_recorded com o que está lançado e mensagem`);
  assert.ok(refusal > body.indexOf("'replaced', 'presumed_absence'"), `${file}: a recusa vem depois do ramo da falta presumida`);
  assert.equal(body.slice(refusal).search(/UPDATE public\.attendance/), -1, `${file}: nada é gravado depois da recusa`);
  for (const gate of ["'event_cancelled'", "'checkin_window_expired'", "'not_in_audience'"]) {
    const g = body.indexOf(gate);
    assert.ok(g > 0 && g < body.indexOf('INSERT INTO public.attendance'), `${file}: o portão ${gate} continua antes de gravar`);
  }
});
