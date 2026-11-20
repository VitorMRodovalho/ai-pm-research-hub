/**
 * #3110: o aviso de filiação pendente que já existia (nudge_entry_chapter_cohort, tipo entry_chapter_action_needed)
 * passa a alcançar quem tem o portão de filiação fechado, por um cron diário.
 *
 * Trava (sobre a CAPTURA VIGENTE da função):
 *   A. a coorte é affiliation_needs_review (#3105), não mais o ciclo de seleção;
 *   B. a variante sai do motivo do portão e do balde do snapshot (#3107), e o caso em que a VEP mostra filiação mas o
 *      portão não abriu NÃO avisa a pessoa;
 *   C. os quatro textos continuam ligados às suas variantes;
 *   D. dedupe de 30 dias, tipo e link de sempre; ensaio não envia e o plano não leva nome;
 *   E. migration da função: DROP da assinatura antiga, grants, pós-condição, e NENHUM agendamento;
 *   F. o cron mora numa migration curta à parte (decisão do GP: ver a lista antes do primeiro disparo).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');
const N = maskLineComments(latestFunctionCapture(ROOT, 'nudge_entry_chapter_cohort').body);
const CRON = (() => {
  const f = readdirSync(MIGRATIONS).filter((n) => /^\d{14}_3110_cron_do_aviso_de_filiacao\.sql$/.test(n));
  assert.equal(f.length, 1, 'a migration do cron da #3110 existe uma vez');
  return maskLineComments(readFileSync(resolve(MIGRATIONS, f[0]), 'utf8'));
})();
const MIG = (() => {
  const f = readdirSync(MIGRATIONS).filter((n) => /^\d{14}_3110_aviso_de_filiacao_pendente_alcanca_o_portao\.sql$/.test(n));
  assert.equal(f.length, 1, 'a migration da #3110 existe uma vez');
  return maskLineComments(readFileSync(resolve(MIGRATIONS, f[0]), 'utf8'));
})();

test('A. a coorte é quem tem o portão fechado com vínculo que exige termo', () => {
  assert.match(
    N,
    /FROM public\.members m\s+WHERE m\.member_status = 'active'\s+AND public\.affiliation_needs_review\(m\.id\)/,
  );
  assert.doesNotMatch(N, /get_entry_chapter_diagnosis|p_cycle_id|entry_chapter_code IS NULL/, 'nada da coorte por ciclo');
});

test('B. a variante sai do portão e do snapshot; VEP com filiação e portão fechado não avisa', () => {
  assert.match(N, /public\.affiliation_gate\(m\.id\) ->> 'reason' AS reason,\s+public\.affiliation_vep_snapshot\(m\.id\) ->> 'bucket' AS bucket/);
  assert.match(
    N,
    /v_variant := CASE\s+WHEN v_rec\.reason = 'entry_chapter_required' THEN 'ambiguous'\s+WHEN v_rec\.reason = 'not_affiliated'\s+THEN 'not_affiliated'\s+WHEN v_rec\.bucket = 'profile_private'\s+THEN 'profile_private'\s+WHEN v_rec\.bucket IS NULL OR v_rec\.bucket = 'no_fetch' THEN 'no_fetch'\s+ELSE NULL\s+END;/,
  );
  assert.match(N, /IF v_variant IS NULL THEN\s+v_internal := v_internal \+ 1;\s+CONTINUE;\s+END IF;/, 'sem variante, não avisa');
});

test('C. os textos continuam ligados às variantes', () => {
  assert.match(N, /WHEN 'ambiguous'\s+THEN 'Escolha seu capítulo de entrada no Núcleo'/);
  assert.match(N, /WHEN 'profile_private' THEN 'Deixe seu perfil PMI público para confirmarmos seu capítulo'/);
  assert.match(N, /WHEN 'no_fetch'\s+THEN 'Vincule seu perfil PMI para definir seu capítulo de entrada'/);
  assert.match(N, /ELSE\s+'Confirme sua filiação PMI para definir seu capítulo de entrada'/);
  assert.match(N, /ELSE\s+'Não conseguimos confirmar uma filiação PMI ativa/);
});

test('D. ensaio não envia; dedupe de 30 dias; tipo e link de sempre; plano sem nome', () => {
  const plano = N.indexOf("v_plan := v_plan || jsonb_build_object('member_id', v_rec.member_id, 'variant', v_variant);");
  const ensaio = N.indexOf('IF p_dry_run THEN\n      CONTINUE;');
  const dedupe = N.indexOf("AND n.type = 'entry_chapter_action_needed'\n        AND n.created_at > now() - interval '30 days'");
  const envio = N.indexOf('PERFORM public.create_notification(');
  assert.ok(plano > 0 && ensaio > plano && dedupe > ensaio && envio > dedupe, 'plano, ensaio, dedupe e envio nessa ordem');
  assert.match(N, /PERFORM public\.create_notification\(\s+v_rec\.member_id,\s+'entry_chapter_action_needed',\s+v_title,\s+v_body,\s+'\/profile#entry-chapter-card'\s+\);/);
  assert.doesNotMatch(N, /'name'|applicant_name|m\.name/, 'o plano não expõe nome');
});

test('E. migration da função: assinatura antiga sai, grants, pós-condição, sem agendar nada', () => {
  assert.match(MIG, /DROP FUNCTION IF EXISTS public\.nudge_entry_chapter_cohort\(uuid, boolean\);\s+CREATE FUNCTION public\.nudge_entry_chapter_cohort\(p_dry_run boolean DEFAULT true\)/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.nudge_entry_chapter_cohort\(boolean\) FROM PUBLIC, anon;/);
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.nudge_entry_chapter_cohort\(boolean\) TO authenticated, service_role;/);
  assert.doesNotMatch(MIG, /cron\.schedule/, 'a migration da função não agenda');
  assert.match(MIG, /IF EXISTS \(SELECT 1 FROM cron\.job WHERE command ~ 'nudge_entry_chapter_cohort'\) THEN\s+RAISE EXCEPTION/);
  assert.match(MIG, /v_ensaio := public\.nudge_entry_chapter_cohort\(true\);/);
  assert.match(MIG, /RAISE EXCEPTION '#3110: ensaio inesperado/);
  assert.match(MIG, /NOTIFY pgrst, 'reload schema';/);
});

test('F. o cron mora à parte e envia de verdade', () => {
  assert.match(CRON, /SELECT cron\.schedule\(\s+'affiliation-action-needed-nudge-daily',\s+'30 12 \* \* \*',\s+\$cron\$ SELECT public\.nudge_entry_chapter_cohort\(p_dry_run := false\) \$cron\$\s+\);/);
  assert.match(CRON, /IF \(SELECT count\(\*\) FROM cron\.job WHERE command ~ 'nudge_entry_chapter_cohort'\) <> 1/);
  assert.doesNotMatch(CRON, /CREATE (OR REPLACE )?FUNCTION/, 'a migration do cron não mexe na função');
});
