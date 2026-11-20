/**
 * #3119 (ADR-0134 §3 e §4): a tela de avaliadores do piloto, o encerramento do vínculo, o histórico e o fit na
 * atribuição.
 *
 * Regra do GP (20/11/2026): toda automação e todo poder da gestão tem tela de ver, auditar e corrigir. As funções do
 * avaliador do piloto só rodavam por chamada direta, não gravavam histórico, não havia como encerrar o vínculo, e a
 * terceira parte da avaliação (fit, do líder da vaga) não cabia em atribuição nem em calibragem.
 *
 * O QUE ESTE GUARD AFIRMA (sempre na captura vigente de cada função, recortada no trecho que decide)
 *   A. CHECK de part nas duas tabelas aceita objective, video e fit;
 *   B. _impedimento_na_linha: no fit, depois da falha fechada e antes do "sem vínculo na linha não impede", só passa o
 *      líder ativo da iniciativa da vaga;
 *   C. assign aceita fit, com 1 avaliador por candidatura no fit (antes da regra dos 2), e grava o histórico depois de
 *      gravar a atribuição;
 *   D. calibragem aceita fit e grava o histórico depois de gravar;
 *   E. grant grava granted quando não havia vínculo e extended quando havia, lendo a data de fim anterior;
 *   F. withdraw grava o histórico só depois de achar a atribuição;
 *   G. end_selection_evaluator: só a gestão; motivo obrigatório; encerra hoje com status offboarded; retira as
 *      atribuições ativas DAQUELA pessoa; grava o histórico; executável por authenticated e não por anon;
 *   H. get_selection_evaluators_admin: só a gestão; o estado da atribuição na ordem retirada, enviada, vencida,
 *      rascunho, pendente; o vínculo vale só ativo e dentro da data de fim; o histórico lê só selection_evaluator.*;
 *   I. a aba existe só para manage_platform, entra no switchTab e monta a ilha;
 *   J. a ilha chama cada função com os argumentos dela, por rpcChecked (recusa no corpo vira erro), relê depois de
 *      escrever, e pede motivo para encerrar e para retirar;
 *   K. todo rótulo da ilha existe nos 3 idiomas.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG_DIR = resolve(ROOT, 'supabase/migrations');
const norm = (s) => maskLineComments(s).replace(/\s+/g, ' ');
const MIG = (() => {
  const f = readdirSync(MIG_DIR).filter((n) => /^\d{14}_3119_tela_de_avaliadores_e_fit\.sql$/.test(n));
  assert.equal(f.length, 1, 'a migration da #3119 existe uma vez');
  return f[0];
})();
const MIG_SQL = norm(readFileSync(resolve(MIG_DIR, MIG), 'utf8'));
const cap = (n) => {
  const c = latestFunctionCapture(ROOT, n);
  assert.equal(c.file, MIG, `${n}: a captura vigente é a da #3119`);
  return norm(c.block);
};

test('A. CHECK de part aceita objective, video e fit nas duas tabelas', () => {
  for (const t of ['selection_evaluator_calibrations', 'selection_evaluation_assignments']) {
    const drop = MIG_SQL.indexOf(`ALTER TABLE public.${t} DROP CONSTRAINT ${t}_part_check;`);
    const add = MIG_SQL.indexOf(`ALTER TABLE public.${t} ADD CONSTRAINT ${t}_part_check CHECK (part IN ('objective', 'video', 'fit'));`);
    assert.ok(drop >= 0 && add > drop, `${t}: o CHECK novo não substitui o antigo`);
  }
});

test('B. no fit, só o líder ativo da iniciativa da vaga', () => {
  const c = cap('_impedimento_na_linha');
  const naoAchou = c.indexOf("IF NOT FOUND THEN RETURN 'candidatura de vaga piloto ou membro inexistente'; END IF;");
  const fit = c.search(/IF p_part = 'fit' THEN IF EXISTS \(SELECT 1 FROM public\.engagements e WHERE e\.person_id = v_pessoa AND e\.initiative_id = v_iniciativa AND e\.role = 'leader' AND e\.status = 'active'\) THEN RETURN NULL; END IF; RETURN 'não é o líder ativo da iniciativa da vaga [^']*'; END IF;/);
  const semVinculo = c.indexOf('IF NOT EXISTS (SELECT 1 FROM public.engagements e WHERE e.person_id = v_pessoa AND e.initiative_id = v_iniciativa AND e.status IN');
  assert.ok(naoAchou >= 0 && fit > naoAchou, 'o desvio do fit não vem depois da falha fechada');
  assert.ok(semVinculo > fit, 'o desvio do fit não vem antes do "sem vínculo na linha, não impede"');
});

test('C. assign aceita fit, 1 avaliador no fit, e grava o histórico depois da atribuição', () => {
  const c = cap('assign_selection_evaluators');
  assert.match(c, /IF p_part NOT IN \('objective', 'video', 'fit'\) OR p_application_ids IS NULL/);
  const um = c.search(/ELSIF p_part = 'fit' AND \(SELECT count\(\*\) FROM public\.selection_evaluation_assignments a WHERE a\.application_id = v_app\.id AND a\.part = 'fit' AND a\.withdrawn_at IS NULL AND a\.evaluator_member_id <> p_member_id\) >= 1 THEN v_motivos := v_motivos \|\| \(left\(v_app\.id::text, 8\) \|\| ': o fit já tem avaliador'\);/);
  const dois = c.indexOf(") >= 2 THEN v_motivos := v_motivos || (left(v_app.id::text, 8) || ': já tem 2 avaliadores nesta parte');");
  assert.ok(um > 0 && dois > um, 'o limite de 1 no fit não vem antes do limite de 2');
  const grava = c.indexOf('INSERT INTO public.selection_evaluation_assignments');
  const hist = c.search(/INSERT INTO public\.admin_audit_log \(actor_id, action, target_type, target_id, metadata\) VALUES \(v_caller, 'selection_evaluator\.assigned', 'member', p_member_id, jsonb_build_object\('opportunity_id', p_opportunity_id, 'part', p_part, 'application_ids', to_jsonb\(p_application_ids\),/);
  const ok = c.indexOf("RETURN jsonb_build_object('success', true, 'assigned', v_n, 'due_at', v_prazo);");
  assert.ok(grava > 0 && hist > grava && ok > hist, 'o histórico da atribuição não fica entre gravar e devolver sucesso');
});

test('D. calibragem aceita fit e grava o histórico depois de gravar', () => {
  const c = cap('record_selection_evaluator_calibration');
  assert.match(c, /IF p_part NOT IN \('objective', 'video', 'fit'\) OR coalesce\(btrim\(p_material_version\), ''\) = '' THEN/);
  const grava = c.indexOf('ON CONFLICT (member_id, opportunity_id, part) DO UPDATE');
  const hist = c.search(/INSERT INTO public\.admin_audit_log \(actor_id, action, target_type, target_id, metadata\) VALUES \(v_caller, 'selection_evaluator\.calibrated', 'member', p_member_id, jsonb_build_object\('opportunity_id', p_opportunity_id, 'part', p_part, 'material_version', btrim\(p_material_version\)/);
  assert.ok(grava > 0 && hist > grava, 'o histórico da calibragem não vem depois de gravar');
});

test('E. grant grava granted ou extended pela data de fim anterior', () => {
  const c = cap('grant_selection_evaluator');
  assert.match(c, /SELECT e\.id, e\.end_date INTO v_eng, v_fim_antes FROM public\.engagements e WHERE e\.person_id = v_member\.person_id AND e\.kind = 'selection_evaluator' AND e\.status = 'active'/);
  assert.match(c, /VALUES \(v_caller, CASE WHEN v_fim_antes IS NULL THEN 'selection_evaluator\.granted' ELSE 'selection_evaluator\.extended' END, 'member', p_member_id, jsonb_build_object\('engagement_id', v_eng, 'end_date', p_end_date, 'end_date_before', v_fim_antes,/);
});

test('F. withdraw grava o histórico só depois de achar a atribuição', () => {
  const c = cap('withdraw_selection_evaluator_assignment');
  const upd = c.search(/WHERE id = p_assignment_id AND withdrawn_at IS NULL RETURNING evaluator_member_id, application_id, part INTO v_a; IF NOT FOUND THEN RETURN jsonb_build_object\('error', 'Atribuição inexistente ou já retirada\.'\); END IF;/);
  const hist = c.indexOf("VALUES (v_caller, 'selection_evaluator.assignment_withdrawn', 'selection_evaluation_assignment', p_assignment_id,");
  assert.ok(upd > 0 && hist > upd, 'o histórico da retirada não vem depois do IF NOT FOUND');
});

test('G. end_selection_evaluator: gestão, motivo, encerra hoje, retira as atribuições da pessoa, histórico, grants', () => {
  const c = cap('end_selection_evaluator');
  const gate = c.search(/IF v_caller IS NULL OR NOT public\.can_by_member\(v_caller, 'manage_platform'\) THEN RETURN jsonb_build_object\('error', 'Unauthorized'\); END IF;/);
  const motivo = c.indexOf("IF coalesce(btrim(p_reason), '') = '' THEN RETURN jsonb_build_object('error', 'O motivo é obrigatório.'); END IF;");
  const enc = c.search(/UPDATE public\.engagements SET status = 'offboarded', end_date = CURRENT_DATE, revoked_at = now\(\), revoked_by = v_caller_person, revoke_reason = btrim\(p_reason\), updated_at = now\(\) WHERE id = v_eng;/);
  const ret = c.search(/UPDATE public\.selection_evaluation_assignments SET withdrawn_at = now\(\), withdrawn_reason = [^;]* WHERE evaluator_member_id = p_member_id AND withdrawn_at IS NULL;/);
  const hist = c.indexOf("VALUES (v_caller, 'selection_evaluator.ended', 'member', p_member_id,");
  assert.ok(gate > 0 && motivo > gate && enc > motivo && ret > enc && hist > ret, 'a ordem gate, motivo, encerra, retira, histórico se quebrou');
  assert.match(c, /SELECT e\.id INTO v_eng FROM public\.engagements e WHERE e\.person_id = v_person AND e\.kind = 'selection_evaluator' AND e\.status = 'active'/, 'encerra outro vínculo que não o de avaliador');
  assert.match(MIG_SQL, /GRANT EXECUTE ON FUNCTION public\.end_selection_evaluator\(uuid, text\) TO authenticated;/);
  assert.match(MIG_SQL, /REVOKE ALL ON FUNCTION public\.end_selection_evaluator\(uuid, text\) FROM PUBLIC, anon;/);
});

test('H. get_selection_evaluators_admin: gestão, estado, vínculo válido, histórico só do avaliador', () => {
  const c = cap('get_selection_evaluators_admin');
  const gate = c.search(/IF v_caller IS NULL OR NOT public\.can_by_member\(v_caller, 'manage_platform'\) THEN RETURN jsonb_build_object\('error', 'Unauthorized'\); END IF; RETURN jsonb_build_object\(/);
  assert.ok(gate > 0, 'a leitura não recusa quem não é gestão antes de devolver dado');
  assert.match(c, /'state', CASE WHEN a\.withdrawn_at IS NOT NULL THEN 'withdrawn' WHEN se\.submitted_at IS NOT NULL THEN 'submitted' WHEN a\.due_at < now\(\) THEN 'overdue' WHEN se\.id IS NOT NULL THEN 'draft' ELSE 'pending' END\)/);
  assert.match(c, /ON se\.application_id = a\.application_id AND se\.evaluator_id = a\.evaluator_member_id AND se\.evaluation_type = a\.part\)/);
  assert.match(c, /'authoritative', \(e\.status = 'active' AND \(e\.end_date IS NULL OR e\.end_date >= CURRENT_DATE\)\)\)/);
  assert.match(c, /WHERE l\.action LIKE 'selection\\_evaluator\.%'/);
  assert.match(MIG_SQL, /GRANT EXECUTE ON FUNCTION public\.get_selection_evaluators_admin\(\) TO authenticated;/);
  assert.match(MIG_SQL, /REVOKE ALL ON FUNCTION public\.get_selection_evaluators_admin\(\) FROM PUBLIC, anon;/);
});

const PAGE = readFileSync(resolve(ROOT, 'src/pages/admin/selection.astro'), 'utf8');
const ISLAND = maskJsComments(readFileSync(resolve(ROOT, 'src/components/selection/SelectionEvaluatorsTab.tsx'), 'utf8'));

test('I. a aba é só da gestão, entra no switchTab e monta a ilha', () => {
  assert.match(PAGE, /<button data-sel-tab="evaluators" data-sel-requires="manage_platform" class="sel-tab-btn /);
  assert.match(PAGE, /<div id="tab-evaluators" data-sel-requires="manage_platform" class="hidden space-y-4">\s*<SelectionEvaluatorsTab client:visible \/>\s*<\/div>/);
  assert.match(PAGE, /\['pipeline', 'import', 'committee', 'evaluators', 'diversity'\]\.forEach\(t => \{/);
});

test('J. a ilha chama cada função por rpcChecked, relê depois de escrever e pede motivo', () => {
  assert.match(ISLAND, /const d = await rpcChecked<AdminData>\(sb, 'get_selection_evaluators_admin'\);/);
  const run = ISLAND.slice(ISLAND.indexOf('async function run('), ISLAND.indexOf('const authoritative'));
  assert.match(run, /await rpcChecked\(sb, fn, args\);\s*setMsg\(\{ kind: 'ok', text: okText \}\);\s*await load\(\);\s*return true;/, 'a escrita não relê o banco depois de dar certo');
  for (const re of [
    /run\('grant_selection_evaluator', \{ p_member_id: grantMember, p_end_date: grantEnd, p_note: grantNote\.trim\(\) \|\| null \}/,
    /run\('grant_selection_evaluator', \{ p_member_id: e\.member_id, p_end_date: extendEnd, p_note: null \}/,
    /disabled=\{busy \|\| !endReason\.trim\(\)\}\s*onClick=\{async \(\) => \{ if \(await run\('end_selection_evaluator', \{ p_member_id: e\.member_id, p_reason: endReason\.trim\(\) \}/,
    /run\('record_selection_evaluator_calibration', \{ p_member_id: calMember, p_opportunity_id: calOpp, p_part: calPart, p_material_version: calVersion\.trim\(\), p_notes: calNotes\.trim\(\) \|\| null \}/,
    /run\('assign_selection_evaluators', \{ p_opportunity_id: asgOpp, p_part: asgPart, p_member_id: asgMember, p_application_ids: asgApps \}/,
    /disabled=\{busy \|\| !wdReason\.trim\(\)\}\s*onClick=\{async \(\) => \{ if \(await run\('withdraw_selection_evaluator_assignment', \{ p_assignment_id: a\.id, p_reason: wdReason\.trim\(\) \}/,
  ]) assert.match(ISLAND, re);
  assert.match(ISLAND, /const PARTS = \['objective', 'video', 'fit'\] as const;/);
});

test('K. todo rótulo da ilha existe nos 3 idiomas', () => {
  const keys = new Set([...ISLAND.matchAll(/tr\('([A-Za-z.]+)', /g)].map((m) => m[1]));
  for (const p of ['objective', 'video', 'fit']) keys.add(`part.${p}`);
  for (const s of ['pending', 'draft', 'overdue', 'submitted', 'withdrawn']) keys.add(`state.${s}`);
  for (const a of ['granted', 'extended', 'ended', 'calibrated', 'assigned', 'assignment_withdrawn']) keys.add(`action.${a}`);
  keys.add('tab');
  assert.ok(keys.size > 60, `poucas chaves achadas (${keys.size}): o recorte quebrou`);
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const d = readFileSync(resolve(ROOT, `src/i18n/${lang}.ts`), 'utf8');
    for (const k of keys) assert.match(d, new RegExp(`'admin\\.selection\\.evaluators\\.${k.replace(/\./g, '\\.')}': '`), `${lang}: ${k}`);
  }
});
