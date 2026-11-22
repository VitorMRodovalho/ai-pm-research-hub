/**
 * #3112: as três anonimizações limpam também a pessoa em persons.
 *
 * admin_anonymize_member e anonymize_inactive_members anonimizavam members e não tocavam persons (a ponte
 * da #2732 leva só o nome), e anonymize_by_engagement_kind trocava em persons só nome, e-mail e auth_id.
 * Desde a #2556 o dado pessoal também mora em persons. _anonymize_person_pii faz a limpeza num lugar só, e
 * as três funções o chamam colado ao UPDATE de members, dentro do ramo que de fato apaga (não no ensaio).
 *
 * O guard lê a ÚLTIMA migration que define cada função; uma versão posterior que esqueça persons reprova.
 * Comentários SQL saem antes do assert.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskLineComments as mask } from '../helpers/guard-pin-staleness.mjs';

const DIR = resolve(process.cwd(), 'supabase/migrations');
const FILES = readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort();

function latest(name) {
  const head = `CREATE OR REPLACE FUNCTION public.${name}(`;
  const hits = FILES.filter((f) => mask(readFileSync(resolve(DIR, f), 'utf8')).includes(head));
  assert.ok(hits.length > 0, `alguma migration define ${name}`);
  const file = hits.at(-1);
  const sql = mask(readFileSync(resolve(DIR, file), 'utf8'));
  assert.equal(sql.split(head).length - 1, 1, `${file}: ${name} definida uma vez`);
  const start = sql.indexOf(head);
  const end = sql.indexOf('$function$;', start);
  assert.ok(end > start, `${file}: fim do corpo de ${name}`);
  return { file, sql, body: sql.slice(start, end) };
}

test('#3112: o helper troca a identidade e zera o dado pessoal da pessoa, por person_id ou pela ponte', () => {
  const { file, sql, body } = latest('_anonymize_person_pii');
  const upd = body.match(/UPDATE public\.persons p SET([\s\S]*?)WHERE p\.id = p_person_id\s+OR \(p_member_id IS NOT NULL AND p\.legacy_member_id = p_member_id\);/);
  assert.ok(upd, `${file}: um UPDATE de persons pela pessoa ou pela ponte legacy_member_id`);
  const set = upd[1];
  assert.match(set, /name = 'Pessoa Anonimizada #' \|\| SUBSTR\(p\.id::text, 1, 8\),\s+email = 'anon_' \|\| SUBSTR\(p\.id::text, 1, 8\) \|\| '@removed\.local',\s+auth_id = NULL,/,
    `${file}: nome, e-mail e auth_id trocados pelo padrão anônimo`);
  for (const col of ['phone', 'address', 'city', 'birth_date', 'pmi_id', 'linkedin_url', 'photo_url', 'credly_url', 'credly_badges', 'credly_verified_at', 'state', 'country']) {
    assert.match(set, new RegExp(`\\b${col} = NULL\\b`), `${file}: ${col} zerado em persons`);
  }
  assert.match(set, /secondary_emails = '\{\}'::text\[\]/, `${file}: e-mails secundários esvaziados`);
  assert.match(set, /anonymized_at = now\(\)/, `${file}: persons marcada como anonimizada`);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\._anonymize_person_pii\(uuid, uuid\) FROM PUBLIC, anon, authenticated;/,
    `${file}: ninguém pela API chama o helper direto`);
});

test('#3112: admin_anonymize_member chama o helper para a pessoa do membro, logo depois de anonimizar members', () => {
  const { file, body } = latest('admin_anonymize_member');
  assert.match(body,
    /anonymized_at = now\(\), anonymized_by = v_caller_id,\s+updated_at = now\(\)\s+WHERE id = p_member_id;\s+PERFORM public\._anonymize_person_pii\(\s*\(SELECT m\.person_id FROM public\.members m WHERE m\.id = p_member_id\), p_member_id\);/,
    `${file}: a pessoa do membro anonimizado é anonimizada em seguida`);
});

test('#3112: anonymize_inactive_members chama o helper dentro do ramo que apaga, colado ao UPDATE de members', () => {
  const { file, body } = latest('anonymize_inactive_members');
  assert.match(body,
    /IF NOT p_dry_run THEN\s+UPDATE public\.members SET[\s\S]*?anonymized_at = now\(\), anonymized_by = NULL,\s+updated_at = now\(\)\s+WHERE id = v_candidate\.member_id;\s+PERFORM public\._anonymize_person_pii\(\s*\(SELECT m\.person_id FROM public\.members m WHERE m\.id = v_candidate\.member_id\), v_candidate\.member_id\);/,
    `${file}: no ramo que não é ensaio, a pessoa do candidato é anonimizada logo depois de members`);
});

test('#3112: anonymize_by_engagement_kind usa o helper no lugar do UPDATE que só trocava nome, e-mail e auth_id', () => {
  const { file, body } = latest('anonymize_by_engagement_kind');
  assert.match(body,
    /PERFORM public\._anonymize_person_pii\(v_person\.person_id, NULL\);\s+IF v_person\.legacy_member_id IS NOT NULL THEN\s+UPDATE public\.members SET/,
    `${file}: a pessoa é anonimizada pelo helper, antes do membro ligado a ela`);
  assert.doesNotMatch(body, /UPDATE public\.persons SET/, `${file}: nenhum UPDATE de persons por fora do helper`);
});
