/**
 * Contract: #2393, M2 (ADR-0134 §4) — o avaliador mínimo do piloto da linha e o lembrete único do portal.
 *
 *   Autoridade (procedimento V4): o kind selection_evaluator não é atado a espécie de iniciativa (etapa 0), não
 *     exige termo no alfa (D21) e tem data de fim; a ação evaluate_assigned_application tem um par só, em
 *     organização.
 *   Regra única: _avaliador_do_piloto decide quem avalia (atribuição ativa, ação, calibragem, sem conflito e SEM
 *     vínculo na iniciativa da vaga). Fila, formulário e envio a usam; a atribuição recusa pelas mesmas razões.
 *   Revisão cega (ADR-0059): o formulário só lê a avaliação de quem chama, e as notas do piloto só a gestão lê.
 *   Corte: a candidatura piloto não entra no corte do ciclo, nem como candidata nem na mediana.
 *   D23: o avaliador de fora não recebe nome, e-mail nem LinkedIn, nem a triagem por IA antes da nota.
 *   C9: o lembrete do portal sai uma vez, na janela de 4 a 6 dias, só para quem não abriu nenhum link.
 * Camada S (estática): cada asserção casa a condição com o resultado no trecho que decide.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');
const todas = () => readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql')).sort()
  .map((f) => ({ f, s: maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8')).replace(/\s+/g, ' ') }));
function captura(nome) {
  const cap = latestFunctionCapture(ROOT, nome);
  assert.ok(cap, `${nome}: nenhuma migration cria esta função`);
  return maskLineComments(cap.block).replace(/\s+/g, ' ');
}
const ATRIBUIDO = /v_piloto_atribuido := NOT public\._na_avaliacao_geral\(p_application_id\) AND public\._avaliador_do_piloto\(v_caller\.id, p_application_id, p_evaluation_type\);/;

test('#2393n V4: o kind não é atado a espécie (etapa 0), não exige termo no alfa e tem data de fim', () => {
  const m = todas().filter((x) => /INSERT INTO public\.engagement_kinds \([^)]*\) VALUES \( 'selection_evaluator',/.test(x.s)).pop();
  assert.ok(m, 'o kind selection_evaluator não é criado');
  const v = m.s.slice(m.s.indexOf("VALUES ( 'selection_evaluator',"));
  assert.match(v, /^VALUES \( 'selection_evaluator', '[^']+', '[^']+', 'legitimate_interest', false, NULL, 120, 730, false, false, false, 180, 'anonymize', true, 'notify_only', 14, ARRAY\['manager','deputy_manager'\], ARRAY\['manager','deputy_manager'\], ARRAY\[\]::text\[\],/,
    'mudou o escopo de iniciativa, a exigência de termo ou as espécies admitidas do kind');
  assert.match(m.s, /ADD CONSTRAINT engagements_selection_evaluator_end_date_check CHECK \(kind <> 'selection_evaluator' OR end_date IS NOT NULL\);/,
    'o vínculo de avaliador deixou de exigir data de fim');
});

test('#2393n V4: a ação evaluate_assigned_application tem um par só, avaliador em organização', () => {
  const pares = [];
  for (const { s } of todas()) for (const x of s.matchAll(/\('([a-z_]+)', '([a-z_]+)', 'evaluate_assigned_application', '([a-z_]+)'/g)) pares.push(x.slice(1).join('×'));
  assert.deepEqual(pares, ['selection_evaluator×evaluator×organization'], 'a ação ganhou outro par ou mudou de escopo');
});

test('#2393n: a regra única exige atribuição, ação, calibragem, ausência de conflito e de vínculo na linha', () => {
  const c = captura('_avaliador_do_piloto');
  assert.match(c,
    /WHERE a\.application_id = p_application_id AND a\.part = p_part AND a\.evaluator_member_id = p_member_id AND a\.withdrawn_at IS NULL AND public\.can_by_member\(p_member_id, 'evaluate_assigned_application'\) AND EXISTS \(SELECT 1 FROM public\.selection_evaluator_calibrations c WHERE c\.member_id = p_member_id AND c\.opportunity_id = vo\.opportunity_id AND c\.part = p_part\) AND NOT public\.selection_coi_recused\(p_member_id, sa\.cycle_id\) AND NOT EXISTS \(SELECT 1 FROM public\.engagements e WHERE e\.person_id = m\.person_id AND e\.initiative_id = vo\.initiative_id AND e\.status IN \('active', 'suspended'\)\)/,
    'a regra de quem avalia perdeu uma condição');
  assert.match(c, /JOIN public\.vep_opportunities vo ON vo\.opportunity_id = sa\.vep_opportunity_id AND vo\.evaluation_track = 'line_pilot' JOIN public\.members m ON m\.id = a\.evaluator_member_id AND m\.is_active/,
    'a regra deixou de valer só para o piloto ou para membro ativo');
});

test('#2393n: a atribuição recusa, tudo ou nada, antes de gravar e de avisar', () => {
  const c = captura('assign_selection_evaluators');
  for (const [cond, motivo] of [
    [/IF NOT public\.can_by_member\(p_member_id, 'evaluate_assigned_application'\) THEN v_motivos := v_motivos \|\| 'sem o vínculo de avaliador';/, 'sem vínculo'],
    [/IF NOT EXISTS \(SELECT 1 FROM public\.selection_evaluator_calibrations c WHERE c\.member_id = p_member_id AND c\.opportunity_id = p_opportunity_id AND c\.part = p_part\) THEN v_motivos := v_motivos \|\| 'sem calibragem desta vaga e parte';/, 'calibragem'],
    [/IF EXISTS \(SELECT 1 FROM public\.engagements e WHERE e\.person_id = v_member\.person_id AND e\.initiative_id = v_vo\.initiative_id AND e\.status IN \('active', 'suspended'\)\) THEN v_motivos := v_motivos \|\| 'tem vínculo na iniciativa da vaga/, 'vínculo na linha'],
    [/ELSIF public\.selection_coi_recused\(p_member_id, v_app\.cycle_id\) THEN v_motivos := v_motivos \|\| \(left\(v_app\.id::text, 8\) \|\| ': conflito de interesse'\);/, 'conflito'],
    [/AND a\.evaluator_member_id <> p_member_id\) >= 2 THEN v_motivos := v_motivos \|\| \(left\(v_app\.id::text, 8\) \|\| ': já tem 2 avaliadores nesta parte'\);/, 'dois por parte'],
  ]) assert.match(c, cond, `a atribuição deixou de recusar: ${motivo}`);
  const recusa = c.indexOf('IF cardinality(v_motivos) > 0 THEN RETURN jsonb_build_object(');
  assert.ok(recusa > 0 && recusa < c.indexOf('INSERT INTO public.selection_evaluation_assignments'), 'a recusa não vem antes de gravar');
  assert.ok(c.indexOf('INSERT INTO public.selection_evaluation_assignments') < c.indexOf("PERFORM public.create_notification( p_member_id, 'selection_evaluator_assigned',"),
    'o aviso deixou de vir depois de gravar, ou de ir ao avaliador');
});

test('#2393n: o formulário abre ao avaliador atribuído, esconde o contato e só lê a avaliação de quem chama', () => {
  const c = captura('get_evaluation_form');
  assert.match(c, ATRIBUIDO, 'a exceção deixou de vir da regra única');
  assert.match(c,
    /IF v_piloto_atribuido THEN v_app_core := v_app_core \|\| jsonb_build_object\('applicant_name', 'Candidatura ' \|\| left\(v_app\.id::text, 8\), 'email', NULL, 'linkedin_url', NULL\); v_app_profile := v_app_profile \|\| jsonb_build_object\('profile_linkedin_url', NULL\); (?:v_app_ai := '\{\}'::jsonb; )?END IF; RETURN jsonb_build_object\(/,
    'o avaliador do piloto voltou a receber o contato do candidato');
  assert.match(c, /CASE WHEN v_piloto_atribuido THEN ARRAY\[\]::text\[\] ELSE ARRAY\['email','applicant_name','linkedin_url'\] END \|\| ARRAY\[/,
    'o registro de acesso voltou a listar contato que o avaliador do piloto não recebeu');
  const leituras = [...c.matchAll(/FROM public\.selection_evaluations\b[^;]*;/g)].map((m) => m[0]);
  assert.ok(leituras.length >= 1, 'o formulário não lê o rascunho');
  for (const l of leituras) assert.match(l, /evaluator_id = v_caller\.id/, 'o formulário lê avaliação de outra pessoa: a revisão cega quebrou');
});

test('#2393n: o envio abre ao avaliador atribuído e tira o piloto do corte do ciclo e da mediana', () => {
  const c = captura('submit_evaluation');
  assert.match(c, ATRIBUIDO, 'a exceção deixou de vir da regra única');
  assert.match(c, /IF v_committee\.role = 'observer' AND NOT public\.can_by_member\(v_caller\.id, 'manage_platform'::text\) AND NOT v_piloto_atribuido THEN/,
    'o observador do comitê que avalia o piloto voltou a ser barrado');
  assert.match(c,
    /UPDATE public\.selection_applications SET objective_score_avg = v_pert_score, updated_at = now\(\) WHERE id = p_application_id; IF public\._na_avaliacao_geral\(p_application_id\) THEN SELECT PERCENTILE_CONT\(0\.5\) WITHIN GROUP \(ORDER BY objective_score_avg\) INTO v_median FROM public\.selection_applications WHERE cycle_id = v_app\.cycle_id AND objective_score_avg IS NOT NULL AND public\._na_avaliacao_geral\(id\); .*? UPDATE public\.selection_applications SET status = v_new_status, updated_at = now\(\) WHERE id = p_application_id AND status IN \('submitted', 'screening', 'objective_eval'\); END IF;/,
    'o piloto voltou ao corte do ciclo ou à mediana');
});

test('#2393n: a fila mostra ao avaliador só o que a regra única libera, sem nome e com prazo', () => {
  const c = captura('get_my_pending_evaluations');
  assert.match(c, /'applicant_name', 'Candidatura ' \|\| left\(sa\.id::text, 8\),/, 'a fila do piloto voltou a mostrar o nome');
  assert.match(c, /WHERE a\.evaluator_member_id = v_caller_member_id AND a\.withdrawn_at IS NULL AND a\.part = 'objective' AND sa\.status <> ALL \(v_terminal\) AND public\._avaliador_do_piloto\(v_caller_member_id, sa\.id, a\.part\)/,
    'a fila do piloto deixou de passar pela regra única');
  assert.match(c, /IF v_piloto IS NULL THEN RAISE EXCEPTION 'Unauthorized: caller is not on this cycle committee' USING ERRCODE = 'insufficient_privilege'; END IF; RETURN jsonb_build_object\( 'cycle_code', v_cycle\.cycle_code, 'cycle_phase', v_cycle\.phase, 'pending', v_piloto,/,
    'fora do comitê, a fila deixou de mostrar só o piloto, ou deixou de recusar quem não tem atribuição');
});

test('#2393n: as notas do piloto só a gestão lê (revisão cega para quem também tem assento)', () => {
  const c = captura('get_evaluation_results');
  const trava = "IF NOT public._na_avaliacao_geral(p_application_id) AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN RAISE EXCEPTION";
  assert.ok(c.includes(trava), 'as notas do piloto voltaram a abrir para o comitê');
  assert.ok(c.indexOf(trava) < c.indexOf('FROM public.selection_evaluations'), 'a trava vem depois da leitura das notas');
});

test('#2393n: o aviso de atribuição é imediato, na função e no catálogo', () => {
  assert.match(captura('_delivery_mode_for'), /WHEN 'selection_evaluator_assigned' THEN 'transactional_immediate'/, 'o modo de entrega do aviso mudou');
  const cat = JSON.parse(readFileSync(resolve(ROOT, 'docs/adr/ADR-0022-notification-types-catalog.json'), 'utf8'));
  assert.equal(cat.types.selection_evaluator_assigned?.delivery_mode, 'transactional_immediate', 'o catálogo diverge da função');
});

test('#2393n C9: o lembrete sai uma vez, de 4 a 6 dias, a quem não abriu nenhum link, e marca o envio', () => {
  const c = captura('_lembrete_do_portal_do_piloto_cron');
  assert.match(c,
    /WHERE sa\.status = 'submitted' AND sa\.pilot_portal_reminder_at IS NULL AND sa\.email IS NOT NULL AND t\.issued_at <= now\(\) - interval '4 days' AND t\.issued_at > now\(\) - interval '6 days' AND NOT EXISTS \(SELECT 1 FROM public\.onboarding_tokens t2 WHERE t2\.source_type = 'pmi_application' AND t2\.source_id = sa\.id AND t2\.access_count > 0\)/,
    'a condição do lembrete mudou');
  assert.match(c, /PERFORM public\.campaign_send_one_off\( 'pmi_pilot_portal_reminder', r\.email, .*?\); UPDATE public\.selection_applications SET pilot_portal_reminder_at = now\(\) WHERE id = r\.application_id;/,
    'o lembrete deixou de marcar o envio logo depois de mandar');
  const m = todas().filter((x) => x.s.includes("cron.schedule( 'selection-pilot-portal-reminder-daily',")).pop();
  assert.ok(m, 'o lembrete não está agendado');
  assert.match(m.s, /cron\.schedule\( 'selection-pilot-portal-reminder-daily', '0 13 \* \* \*', \$cron\$ SELECT public\._lembrete_do_portal_do_piloto_cron\(\) \$cron\$ \);/, 'o agendamento mudou');
});

test('#2393n C9: o texto do lembrete só usa variável que o cron passa, nas 3 línguas, sem travessão', () => {
  const m = todas().filter((x) => x.s.includes("'Lembrete do cadastro, vaga piloto da linha', 'pmi_pilot_portal_reminder',")).pop();
  assert.ok(m, 'o template do lembrete não é criado');
  const ini = m.s.indexOf("'pmi_pilot_portal_reminder', jsonb_build_object(");
  const bloco = m.s.slice(ini, m.s.indexOf("WHERE NOT EXISTS (SELECT 1 FROM public.campaign_templates WHERE slug = 'pmi_pilot_portal_reminder');", ini));
  const usadas = new Set([...bloco.matchAll(/\{\{([a-z_]+)\}\}/g)].map((x) => x[1]));
  const cron = captura('_lembrete_do_portal_do_piloto_cron');
  for (const v of usadas) assert.match(cron, new RegExp(`'${v}', `), `o texto usa {{${v}}}, que o cron não passa`);
  assert.doesNotMatch(bloco, /—|–/, 'travessão no texto do lembrete');
  for (const lang of ['pt', 'en', 'es']) assert.ok((bloco.match(new RegExp(`'${lang}', '`, 'g')) || []).length >= 3, `falta ${lang} no assunto ou no corpo`);
});

test('#2393n (opção A do GP): o avaliador do piloto não vê a triagem por IA, nem antes nem depois da nota; quem já via segue vendo', () => {
  const c = captura('get_evaluation_form');
  assert.match(c, /v_app_ai := jsonb_build_object\( 'consent_ai_analysis_at', v_app\.consent_ai_analysis_at, 'ai_analysis', v_app\.ai_analysis, 'ai_triage_score', v_app\.ai_triage_score, 'ai_triage_reasoning', v_app\.ai_triage_reasoning, 'ai_triage_confidence', v_app\.ai_triage_confidence,/,
    'a triagem deixou de ser montada: a gestão e o comitê geral também a perderiam');
  const ini = c.indexOf('IF v_piloto_atribuido THEN v_app_core := v_app_core');
  const bloco = c.slice(ini, c.indexOf('END IF;', ini));
  assert.match(bloco, / v_app_ai := '\{\}'::jsonb; $/, 'o avaliador do piloto voltou a ver a triagem por IA');
  assert.doesNotMatch(bloco, /submitted_at|v_draft/, 'a triagem passou a depender da nota enviada (opção B), e o GP decidiu a A');
  assert.equal([...c.matchAll(/v_app_ai := '\{\}'::jsonb;/g)].length, 1, 'a triagem é esvaziada fora do caso do avaliador do piloto');
});
