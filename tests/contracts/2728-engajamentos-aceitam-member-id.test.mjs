/**
 * #2728 — get_active_engagements aceita persons.id OU members.id, como get_person (#1383 W2).
 *
 * member_get (MCP) passa o members.id como p_person_id. get_person resolve os dois; get_active_engagements
 * usava o valor literalmente e devolvia count 0, sem erro. A autoridade vem ANTES do "não encontrado", para
 * quem não tem manage_member não distinguir id inexistente de id de outra pessoa.
 *
 * O corpo é lido pela captura MAIS NOVA (#1932), sem comentários. Cada asserção amarra a condição ao resultado.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(import.meta.dirname, '../..');
const MIGS = readdirSync(resolve(ROOT, 'supabase/migrations'));
const FN = maskLineComments(latestFunctionCapture(ROOT, 'get_active_engagements').body);

test('#2728 a migration tem arquivo com a versão registrada', () => {
  const f = MIGS.filter((x) => x.endsWith('_2728_engajamentos_aceitam_member_id.sql'));
  assert.equal(f.length, 1);
  assert.doesNotMatch(f[0], /^20261018999999_/, 'arquivo ainda com o placeholder: renomeie para a versão registrada');
});

test('#2728 o id é resolvido como persons.id e, se não for, como persons.legacy_member_id', () => {
  assert.match(
    FN,
    /SELECT id INTO v_target_person_id FROM public\.persons WHERE id = p_person_id;\s*IF v_target_person_id IS NULL THEN\s*SELECT id INTO v_target_person_id FROM public\.persons WHERE legacy_member_id = p_person_id;\s*END IF;/,
  );
  assert.doesNotMatch(FN, /v_target_person_id := p_person_id;/);
});

test('#2728 a autoridade vem antes do "não encontrado", e um id que não resolve também exige manage_member', () => {
  const auth = FN.search(
    /IF v_target_person_id IS DISTINCT FROM v_caller_person_id THEN\s*IF NOT public\.can\(v_caller_person_id, 'manage_member', NULL, NULL\) THEN\s*RETURN jsonb_build_object\('error', 'Unauthorized: manage_member required'\);/,
  );
  const notFound = FN.search(/IF v_target_person_id IS NULL THEN\s*RETURN jsonb_build_object\('error', 'Person not found'\);/);
  assert.ok(auth >= 0, 'checagem de autoridade com IS DISTINCT FROM não encontrada');
  assert.ok(notFound >= 0, "retorno 'Person not found' não encontrado");
  assert.ok(auth < notFound, 'a autoridade precisa vir antes do "não encontrado" (sem oráculo de existência)');
});

test('#2728 os engajamentos são lidos da pessoa resolvida', () => {
  assert.match(FN, /WHERE e\.person_id = v_target_person_id AND e\.status = 'active';/);
});
