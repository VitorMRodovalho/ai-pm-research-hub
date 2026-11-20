/**
 * #3103: a autoexclusão do art. 18 (delete_my_personal_data) limpa a cópia em persons.
 *
 * Desde a #2556, update_my_profile grava phone, address, city e birth_date em members E em persons.
 * A autoexclusão zerava só members, devolvia success e a tela dizia "Dados pessoais apagados" com a
 * cópia em persons intacta.
 *
 * O guard lê a ÚLTIMA migration que define a função (uma versão posterior que esqueça persons
 * reprova aqui) e amarra cada limpeza ao bloco que decide: depois da confirmação, antes do success,
 * com a mesma pessoa (person_id e a ponte legacy_member_id). Comentários SQL saem antes do assert.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskLineComments as mask } from '../helpers/guard-pin-staleness.mjs';

const DIR = resolve(process.cwd(), 'supabase/migrations');
const HEAD = 'CREATE OR REPLACE FUNCTION public.delete_my_personal_data(';

function latestBody() {
  const files = readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort()
    .filter((f) => mask(readFileSync(resolve(DIR, f), 'utf8')).includes(HEAD));
  assert.ok(files.length > 0, 'alguma migration define delete_my_personal_data');
  const file = files.at(-1);
  const sql = mask(readFileSync(resolve(DIR, file), 'utf8'));
  assert.equal(sql.split(HEAD).length - 1, 1, `${file}: a função é definida uma vez`);
  const start = sql.indexOf(HEAD);
  const end = sql.indexOf('$function$;', start);
  assert.ok(end > start, `${file}: fim do corpo`);
  return { file, body: sql.slice(start, end) };
}

test('#3103: a autoexclusão zera os quatro campos em persons, da mesma pessoa, entre a confirmação e o success', () => {
  const { file, body } = latestBody();
  const confirm = body.search(/IF p_confirm_text IS NULL OR upper\(trim\(p_confirm_text\)\) != 'DELETAR MEUS DADOS PESSOAIS' THEN[\s\S]*?END IF;/);
  const success = body.indexOf("'success', true");
  const upd = body.match(/UPDATE persons SET\s+phone = NULL,\s+address = NULL,\s+city = NULL,\s+birth_date = NULL,\s+updated_at = now\(\)\s+WHERE id = v_caller\.person_id OR legacy_member_id = v_caller\.id;/);
  assert.ok(upd, `${file}: UPDATE persons zera phone, address, city e birth_date pela person_id e pela ponte legacy_member_id`);
  assert.ok(confirm > 0 && upd.index > confirm, `${file}: a limpeza de persons vem depois da checagem da frase de confirmação`);
  assert.ok(success > upd.index, `${file}: o success só é devolvido depois da limpeza de persons`);
  assert.match(body, /SELECT id, person_id,[^;]*FROM members WHERE auth_id = auth\.uid\(\);/,
    `${file}: o membro é lido com a person_id, que é o elo para persons`);
});

test('#3103: cleared_fields diz o que saiu de persons, lido antes de zerar', () => {
  const { file, body } = latestBody();
  const read = body.search(/FROM persons p\s+WHERE p\.id = v_caller\.person_id OR p\.legacy_member_id = v_caller\.id;/);
  const upd = body.indexOf('UPDATE persons SET');
  assert.ok(read > 0 && read < upd, `${file}: persons é lida, para a mesma pessoa, antes do UPDATE`);
  for (const f of ['phone', 'address', 'city', 'birth_date']) {
    assert.match(body, new RegExp(`IF v_person\\.${f} THEN v_cleared := array_append\\(v_cleared, 'persons\\.${f}'\\); END IF;`),
      `${file}: persons.${f} entra em cleared_fields quando existia`);
  }
});

test('#3103: members zera phone_encrypted junto com phone, e o push (#2806) continua saindo', () => {
  const { file, body } = latestBody();
  assert.match(body, /UPDATE members SET\s+phone = NULL,\s+phone_encrypted = NULL,\s+address = NULL,\s+city = NULL,\s+birth_date = NULL,\s+updated_at = now\(\)\s+WHERE id = v_caller\.id;/,
    `${file}: members zera phone, phone_encrypted, address, city e birth_date do próprio membro`);
  assert.match(body, /DELETE FROM public\.push_subscriptions WHERE member_id = v_caller\.id;/,
    `${file}: a inscrição de push do aparelho continua saindo na autoexclusão`);
});
