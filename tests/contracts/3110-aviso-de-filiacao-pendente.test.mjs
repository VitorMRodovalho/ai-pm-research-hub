/**
 * #3110: o aviso de filiação pendente que já existia (nudge_entry_chapter_cohort, tipo entry_chapter_action_needed)
 * passa a alcançar quem tem o portão de filiação fechado, por um cron diário, com liga/desliga, prévia e histórico
 * pela tela de /admin/filiacao (regra do GP, 20/11/2026: toda automação visível, auditável e controlável no front).
 *
 * Trava (sobre a CAPTURA VIGENTE de cada função):
 *   A. o plano mora num lugar só (affiliation_nudge_plan): coorte = affiliation_needs_review (#3105), não o ciclo;
 *   B. a variante sai do motivo do portão e do balde do snapshot (#3107); VEP com filiação e portão fechado não avisa;
 *   C. os quatro textos continuam ligados às variantes, num lugar só (affiliation_nudge_text);
 *   D. o aviso: lê o plano; nada sai em ensaio NEM com o aviso desligado; dedupe de 30 dias; tipo e link de sempre;
 *      a variante fica gravada em source_type; o plano não leva nome;
 *   E. o liga/desliga: a chave nasce desligada e a leitura falha fechada; ligar exige manage_platform, pausar é da
 *      audiência da fila; motivo obrigatório e linha em admin_audit_log;
 *   F. o painel: a audiência da fila; estado, agendamento, prévia, histórico (com a variante dos envios antigos pelo
 *      título) e mudanças da chave;
 *   G. migration: DROP da assinatura antiga, grants (internas sem authenticated), cron diário que chama o envio real, e
 *      pós-condição que prova que a execução real com o aviso desligado não envia;
 *   H. a tela: o painel montado em /admin/filiacao, ligar só para quem pode, motivo, e os rótulos nas 3 línguas.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');
const cap = (n) => maskLineComments(latestFunctionCapture(ROOT, n).body);
const N = cap('nudge_entry_chapter_cohort');
const PLAN = cap('affiliation_nudge_plan');
const TEXT = cap('affiliation_nudge_text');
const ON = cap('affiliation_nudge_enabled');
const SET = cap('set_affiliation_nudge_enabled');
const PANEL = cap('get_affiliation_nudge_panel');
const MIG = (() => {
  const f = readdirSync(MIGRATIONS).filter((n) => /^\d{14}_3110_aviso_de_filiacao_pendente_alcanca_o_portao\.sql$/.test(n));
  assert.equal(f.length, 1, 'a migration da #3110 existe uma vez');
  return maskLineComments(readFileSync(resolve(MIGRATIONS, f[0]), 'utf8'));
})();
const KEY = "'affiliation.action_needed_nudge'";
const escRe = (str) => str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

test('A. o plano mora num lugar só, e a coorte é o portão fechado', () => {
  assert.match(PLAN, /FROM public\.members m\s+WHERE m\.member_status = 'active'\s+AND public\.affiliation_needs_review\(m\.id\)/);
  assert.doesNotMatch(PLAN, /get_entry_chapter_diagnosis|cycle|entry_chapter_code IS NULL/, 'nada da coorte por ciclo');
  assert.match(N, /FOR v_rec IN SELECT p\.member_id, p\.variant FROM public\.affiliation_nudge_plan\(\) p LOOP/);
  assert.match(PANEL, /FROM public\.affiliation_nudge_plan\(\) p\s+JOIN public\.members m ON m\.id = p\.member_id/, 'a prévia lê o mesmo plano');
  assert.doesNotMatch(N, /affiliation_needs_review|affiliation_gate\(/, 'o aviso não recalcula a coorte por fora do plano');
});

test('B. a variante sai do portão e do snapshot; VEP com filiação e portão fechado não avisa', () => {
  assert.match(PLAN, /public\.affiliation_gate\(m\.id\) ->> 'reason' AS reason,\s+public\.affiliation_vep_snapshot\(m\.id\) ->> 'bucket' AS bucket/);
  assert.match(
    PLAN,
    /CASE\s+WHEN x\.reason = 'entry_chapter_required'\s+THEN 'ambiguous'\s+WHEN x\.reason = 'not_affiliated'\s+THEN 'not_affiliated'\s+WHEN x\.bucket = 'profile_private'\s+THEN 'profile_private'\s+WHEN x\.bucket IS NULL OR x\.bucket = 'no_fetch'\s+THEN 'no_fetch'\s+ELSE NULL\s+END AS variant/,
  );
  assert.match(N, /IF v_rec\.variant IS NULL THEN\s+v_internal := v_internal \+ 1;\s+CONTINUE;\s+END IF;/, 'sem variante, não avisa');
});

test('C. os textos continuam ligados às variantes, num lugar só', () => {
  assert.match(TEXT, /WHEN 'ambiguous' THEN jsonb_build_object\(\s+'title', 'Escolha seu capítulo de entrada no Núcleo',/);
  assert.match(TEXT, /WHEN 'profile_private' THEN jsonb_build_object\(\s+'title', 'Deixe seu perfil PMI público para confirmarmos seu capítulo',/);
  assert.match(TEXT, /WHEN 'no_fetch' THEN jsonb_build_object\(\s+'title', 'Vincule seu perfil PMI para definir seu capítulo de entrada',/);
  assert.match(TEXT, /WHEN 'not_affiliated' THEN jsonb_build_object\(\s+'title', 'Confirme sua filiação PMI para definir seu capítulo de entrada',\s+'body',\s+'Não conseguimos confirmar uma filiação PMI ativa/);
  assert.doesNotMatch(N, /'Escolha seu capítulo|'Confirme sua filiação/, 'o aviso não guarda uma segunda cópia dos textos');
});

test('D. nada sai em ensaio nem desligado; dedupe; tipo, link e variante gravada; plano sem nome', () => {
  const plano = N.indexOf("v_plan := v_plan || jsonb_build_object('member_id', v_rec.member_id, 'variant', v_rec.variant);");
  const portao = N.indexOf('IF p_dry_run OR NOT v_enabled THEN\n      CONTINUE;');
  const dedupe = N.indexOf("AND n.type = 'entry_chapter_action_needed'\n        AND n.created_at > now() - interval '30 days'");
  const envio = N.indexOf('PERFORM public.create_notification(');
  assert.ok(plano > 0 && portao > plano && dedupe > portao && envio > dedupe, 'plano, ensaio/desligado, dedupe e envio nessa ordem');
  assert.match(N, /v_enabled := public\.affiliation_nudge_enabled\(\);/);
  assert.match(N, /PERFORM public\.create_notification\(\s+v_rec\.member_id,\s+'entry_chapter_action_needed',\s+v_text ->> 'title',\s+v_text ->> 'body',\s+'\/profile#entry-chapter-card',\s+'affiliation_nudge\.' \|\| v_rec\.variant,\s+NULL::uuid\s+\);/);
  assert.match(N, /'paused', NOT p_dry_run AND NOT v_enabled,/);
  assert.equal((N.match(/PERFORM public\.create_notification\(/g) || []).length, 1, 'um ponto de envio só');
  assert.doesNotMatch(N, /'name'|applicant_name|m\.name/, 'o plano não expõe nome');
});

test('E. liga/desliga: nasce desligado, falha fechada, ligar é da gestão, pausar é da fila, auditado', () => {
  assert.match(MIG, new RegExp(`INSERT INTO public\\.platform_settings \\(key, value, description, change_reason\\)\\s+VALUES \\(\\s+${escRe(KEY)},\\s+'\\{"enabled": false\\}'::jsonb,`));
  assert.match(ON, new RegExp(`SELECT COALESCE\\(\\s+\\(SELECT \\(ps\\.value ->> 'enabled'\\)::boolean IS TRUE\\s+FROM public\\.platform_settings ps WHERE ps\\.key = ${escRe(KEY)}\\),\\s+false\\);`));
  assert.match(SET, /IF p_enabled THEN\s+IF NOT public\.can_by_member\(v_caller_id, 'manage_platform'\) THEN\s+RAISE EXCEPTION/);
  assert.match(SET, /ELSE\s+IF NOT \('filiacao_director' = ANY\(COALESCE\(v_caller_designations, '\{\}'::text\[\]\)\)\)\s+AND NOT public\.can_by_member\(v_caller_id, 'manage_member'\)\s+AND NOT public\.can_by_member\(v_caller_id, 'manage_platform'\) THEN\s+RAISE EXCEPTION/);
  assert.match(SET, /IF p_reason IS NULL OR btrim\(p_reason\) = '' THEN\s+RAISE EXCEPTION 'Reason is required';/);
  const audit = SET.indexOf('INSERT INTO public.admin_audit_log');
  const upd = SET.indexOf('UPDATE public.platform_settings');
  assert.ok(audit > 0 && upd > audit, 'a auditoria é gravada antes da mudança');
  assert.match(SET, /'platform\.setting_changed', 'setting', NULL,\s+jsonb_build_object\('previous_value', v_old, 'new_value', v_new\),\s+jsonb_build_object\('setting_key', 'affiliation\.action_needed_nudge', 'reason', p_reason\)/);
});

test('F. o painel: audiência da fila, estado, agendamento, prévia, histórico e mudanças', () => {
  assert.match(PANEL, /IF NOT \('filiacao_director' = ANY\(COALESCE\(v_caller_designations, '\{\}'::text\[\]\)\)\)\s+AND NOT public\.can_by_member\(v_caller_id, 'manage_member'\) THEN\s+RAISE EXCEPTION/);
  assert.match(PANEL, /IF v_caller_id IS NULL THEN\s+RAISE EXCEPTION/);
  assert.match(PANEL, /'enabled', public\.affiliation_nudge_enabled\(\),/);
  assert.match(PANEL, /'can_enable', public\.can_by_member\(v_caller_id, 'manage_platform'\),/);
  assert.match(PANEL, /FROM cron\.job j WHERE j\.jobname = 'affiliation-action-needed-nudge-daily'/);
  assert.match(PANEL, /'blocked_by_dedupe', EXISTS \(\s+SELECT 1 FROM public\.notifications n\s+WHERE n\.recipient_id = p\.member_id AND n\.type = 'entry_chapter_action_needed'\s+AND n\.created_at > now\(\) - interval '30 days'\)/, 'o dedupe da prévia é o do envio');
  assert.match(PANEL, /COALESCE\(substring\(n\.source_type FROM '\^affiliation_nudge\\\.\(\.\+\)\$'\),\s+\(SELECT v FROM unnest\(ARRAY\['ambiguous', 'not_affiliated', 'profile_private', 'no_fetch'\]\) v\s+WHERE public\.affiliation_nudge_text\(v\) ->> 'title' = n\.title\)\) AS variant/);
  assert.match(PANEL, /WHERE n\.type = 'entry_chapter_action_needed'\s+AND n\.created_at > now\(\) - interval '180 days'\s+ORDER BY n\.created_at DESC\s+LIMIT 500/);
  assert.match(PANEL, /WHERE a\.action = 'platform\.setting_changed'\s+AND a\.metadata ->> 'setting_key' = 'affiliation\.action_needed_nudge'\s+ORDER BY a\.created_at DESC\s+LIMIT 20/);
});

test('G. migration: assinatura antiga sai, grants, cron real, e a pós-condição prova o desligado', () => {
  assert.match(MIG, /DROP FUNCTION IF EXISTS public\.nudge_entry_chapter_cohort\(uuid, boolean\);\s+CREATE FUNCTION public\.nudge_entry_chapter_cohort\(p_dry_run boolean DEFAULT true\)/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.nudge_entry_chapter_cohort\(boolean\) FROM PUBLIC, anon;\s+GRANT EXECUTE ON FUNCTION public\.nudge_entry_chapter_cohort\(boolean\) TO authenticated, service_role;/);
  for (const sig of ['set_affiliation_nudge_enabled\\(boolean, text\\)', 'get_affiliation_nudge_panel\\(\\)']) {
    assert.match(MIG, new RegExp(`REVOKE ALL ON FUNCTION public\\.${sig} FROM PUBLIC, anon;\\s+GRANT EXECUTE ON FUNCTION public\\.${sig} TO authenticated, service_role;`));
  }
  for (const sig of ['affiliation_nudge_plan\\(\\)', 'affiliation_nudge_text\\(text\\)', 'affiliation_nudge_enabled\\(\\)']) {
    assert.match(MIG, new RegExp(`REVOKE ALL ON FUNCTION public\\.${sig} FROM PUBLIC, anon, authenticated;`));
    assert.doesNotMatch(MIG, new RegExp(`GRANT[^;]*${sig}[^;]*\\b(anon|authenticated)\\b`), `${sig} é interna`);
  }
  assert.match(MIG, /SELECT cron\.schedule\(\s+'affiliation-action-needed-nudge-daily',\s+'30 12 \* \* \*',[^\n]*\n\s+\$cron\$ SELECT public\.nudge_entry_chapter_cohort\(p_dry_run := false\) \$cron\$\s+\);/);
  const pos = MIG.slice(MIG.indexOf('DO $postcondition$'));
  assert.match(pos, /IF public\.affiliation_nudge_enabled\(\) THEN\s+RAISE EXCEPTION '#3110: o aviso tem de nascer desligado';/);
  const desligado = pos.indexOf('IF public.affiliation_nudge_enabled() THEN');
  const real = pos.indexOf('v_real := public.nudge_entry_chapter_cohort(false);');
  assert.ok(desligado > 0 && real > desligado, 'a execução real só roda depois de provar que está desligado');
  assert.match(pos, /IF \(v_real ->> 'sent'\)::int <> 0 OR NOT \(v_real ->> 'paused'\)::boolean\s+OR \(SELECT count\(\*\) FROM public\.notifications WHERE type = 'entry_chapter_action_needed'\) <> v_avisos THEN\s+RAISE EXCEPTION/);
  assert.match(pos, /v_ensaio := public\.nudge_entry_chapter_cohort\(true\);/);
  assert.match(pos, /IF \(SELECT count\(\*\) FROM cron\.job WHERE command ~ 'nudge_entry_chapter_cohort'\) <> 1/);
  assert.match(MIG, /NOTIFY pgrst, 'reload schema';/);
});

test('H. a tela: painel em /admin/filiacao, ligar só para quem pode, motivo, rótulos nas 3 línguas', () => {
  const page = readFileSync(resolve(ROOT, 'src/pages/admin/filiacao.astro'), 'utf8');
  assert.match(page, /import AffiliationNudgePanel from '\.\.\/\.\.\/components\/admin\/AffiliationNudgePanel';/);
  assert.match(page, /<AffiliationNudgePanel client:load \/>/);
  assert.match(page, /buildPageI18n\(\[[^\]]*'comp\.affiliationNudge'[^\]]*\], lang\)/);
  const ui = maskJsComments(readFileSync(resolve(ROOT, 'src/components/admin/AffiliationNudgePanel.tsx'), 'utf8'));
  assert.match(ui, /sb\.rpc\('get_affiliation_nudge_panel'\)/);
  assert.match(ui, /sb\.rpc\('set_affiliation_nudge_enabled', \{ p_enabled: enable, p_reason: reason\.trim\(\) \}\)/);
  assert.match(ui, /\{!panel\.enabled && panel\.can_enable && \(\s+<button data-testid="an-enable" onClick=\{\(\) => toggle\(true\)\}/);
  assert.match(ui, /\{panel\.enabled && \(\s+<button data-testid="an-pause" onClick=\{\(\) => toggle\(false\)\}/);
  assert.match(ui, /if \(!reason\.trim\(\)\) \{/);
  for (const id of ['an-preview', 'an-history', 'an-changes', 'an-error']) assert.match(ui, new RegExp(`data-testid="${id}"`));
  const keys = [...new Set([...ui.matchAll(/comp\.affiliationNudge\.([A-Za-z_]+)/g)].map((m) => m[1]))]
    .filter((k) => k !== 'variant_')
    .concat(['variant_ambiguous', 'variant_not_affiliated', 'variant_profile_private', 'variant_no_fetch']);
  for (const d of ['pt-BR', 'en-US', 'es-LATAM']) {
    const dict = readFileSync(resolve(ROOT, `src/i18n/${d}.ts`), 'utf8');
    for (const k of keys) assert.match(dict, new RegExp(`'comp\\.affiliationNudge\\.${k}': '[^']+'`), `${d}: ${k}`);
  }
});
