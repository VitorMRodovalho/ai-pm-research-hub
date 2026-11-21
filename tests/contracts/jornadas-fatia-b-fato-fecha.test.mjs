/**
 * Jornadas de onboarding, fatia B: a autodeclaração não fecha etapa que tem fato.
 *
 * Quem diz se uma etapa fecha por clique ou por fato é o catálogo (onboarding_steps.closed_by),
 * não uma lista copiada em cada função ou tela. As duas portas de autodeclaração
 * (complete_onboarding_step e update_pmi_onboarding_step) recusam a etapa de fato ANTES de gravar;
 * as telas não oferecem o botão; a visita à página da tribo deixou de fechar "Conheça sua tribo".
 * A exceção é o GP, com justificativa escrita, por admin_complete_onboarding_step.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG_DIR = resolve(ROOT, 'supabase/migrations');
const migFiles = readdirSync(MIG_DIR).filter((f) => /^\d{14}_jornadas_b_fato_fecha_a_etapa\.sql$/.test(f));
const MIG = migFiles.length === 1 ? maskLineComments(readFileSync(join(MIG_DIR, migFiles[0]), 'utf8')) : '';
const cap = (n) => maskLineComments(latestFunctionCapture(ROOT, n).block);
const src = (p) => maskJsComments(readFileSync(resolve(ROOT, p), 'utf8'));

const FACT_STEPS = ['first_meeting', 'meet_tribe', 'vep_acceptance', 'volunteer_term'];

test('B0. a migration existe', () => {
  assert.equal(migFiles.length, 1, `esperava 1 migration, achei ${migFiles.length}`);
});

test('B1. o catálogo ganha closed_by, só member|fact, e o padrão é clique', () => {
  assert.match(MIG, /ALTER TABLE public\.onboarding_steps\s+ADD COLUMN closed_by text NOT NULL DEFAULT 'member'\s+CONSTRAINT onboarding_steps_closed_by_check CHECK \(closed_by IN \('member', 'fact'\)\);/);
});

test('B1. exatamente as quatro etapas com fato viram fact', () => {
  const m = MIG.match(/UPDATE public\.onboarding_steps SET closed_by = 'fact'\s+WHERE id IN \(([^)]*)\);/);
  assert.ok(m, 'UPDATE do closed_by ausente');
  const ids = [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]).sort();
  assert.deepEqual(ids, FACT_STEPS);
});

test('B2. complete_onboarding_step recusa a etapa de fato antes de gravar', () => {
  const b = cap('complete_onboarding_step');
  const refuse = b.search(/IF EXISTS \(SELECT 1 FROM onboarding_steps s WHERE s\.id = p_step_id AND s\.closed_by = 'fact'\) THEN\s+RETURN jsonb_build_object\('error', 'step_closed_by_fact'/);
  assert.ok(refuse > 0, 'recusa ausente');
  assert.ok(refuse < b.indexOf('INSERT INTO onboarding_progress'), 'a recusa tem de vir antes do INSERT');
  assert.match(b, /public\.onboarding_step_applies\(s\.applies_to_role, v_member_role\)/, 'o predicado de papel (#1103) continua');
});

test('B3. update_pmi_onboarding_step (portal do token) recusa a etapa de fato antes de gravar', () => {
  const b = cap('update_pmi_onboarding_step');
  const refuse = b.search(/IF EXISTS \(SELECT 1 FROM public\.onboarding_steps s WHERE s\.id = p_step_key AND s\.closed_by = 'fact'\) THEN\s+RAISE EXCEPTION/);
  assert.ok(refuse > 0, 'recusa ausente');
  assert.ok(refuse < b.indexOf('UPDATE public.onboarding_progress'), 'a recusa tem de vir antes do UPDATE');
  assert.doesNotMatch(b, /update_onboarding_step path/, 'o comentário que apontava a função retirada foi corrigido');
});

test('B4. as duas leituras levam closed_by às telas', () => {
  assert.match(cap('get_my_onboarding'),
    /'steps', \(SELECT jsonb_agg\(row_to_json\(t\) ORDER BY t\.step_order\) FROM \(\s+SELECT s\.id AS step_id,[^;]*?s\.is_required, s\.closed_by,/);
  assert.match(cap('consume_onboarding_token'),
    /'applies_to_role', os\.applies_to_role,\s+'closed_by', os\.closed_by,[\s\S]*?INTO v_step_catalog\s+FROM onboarding_steps os;/);
});

test('B5. a exceção é do GP: portão manage_platform e justificativa antes de gravar, sem anon', () => {
  const b = cap('admin_complete_onboarding_step');
  const gate = b.search(/IF v_caller_id IS NULL OR NOT public\.can_by_member\(v_caller_id, 'manage_platform'\) THEN\s+RAISE EXCEPTION/);
  const note = b.search(/IF p_note IS NULL OR length\(btrim\(p_note\)\) < 3 THEN\s+RAISE EXCEPTION/);
  const write = b.indexOf('INSERT INTO onboarding_progress');
  assert.ok(gate > 0 && note > gate && write > note, 'portão, depois justificativa, depois a escrita');
  assert.match(b, /jsonb_build_object\('closed_by', 'gp', 'gp_member_id', v_caller_id, 'gp_note', btrim\(p_note\)/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.admin_complete_onboarding_step\(uuid, text, text\) FROM PUBLIC, anon;/);
});

test('B6. o checklist do membro só mostra o clique onde o catálogo diz clique', () => {
  const s = src('src/components/onboarding/OnboardingChecklist.tsx');
  const clicks = [...s.matchAll(/completeStep\(s\.step_id\)/g)].length;
  const gated = [...s.matchAll(/s\.closed_by !== 'fact' && \(\s+<button onClick=\{\(\) => completeStep\(s\.step_id\)\}/g)].length;
  assert.equal(clicks, 2, 'esperava os dois cliques genéricos (VEP e o fallback)');
  assert.equal(gated, clicks, 'todo clique genérico tem de estar atrás de closed_by !== fact');
  assert.match(s, /s\.step_id === 'vep_acceptance' && s\.closed_by === 'fact' && \(\s+<p[^>]*>\{l\.vepByFact\}<\/p>/);
});

test('B6. o portal do token só mostra o botão onde o catálogo diz clique', () => {
  const s = src('src/components/pmi-onboarding/PMIOnboardingPortal.tsx');
  assert.match(s, /\{!done && stepCatalog\.get\(step\.step_key\)\?\.closed_by !== 'fact' && \(\s+<button\s+disabled=\{busyStep === step\.step_key\}\s+onClick=\{\(\) => handleStepUpdate\(step\.step_key, 'completed'\)\}/);
  assert.equal([...s.matchAll(/handleStepUpdate\(step\.step_key/g)].length, 1, 'outro botão de etapa apareceu sem o portão');
});

test('B7. visitar a página da tribo não fecha etapa', () => {
  const s = src('src/pages/tribe/[id].astro');
  assert.doesNotMatch(s, /complete_onboarding_step/);
});

test('B8. nenhuma tela copia a lista de etapas de fato', () => {
  for (const p of ['src/components/onboarding/OnboardingChecklist.tsx', 'src/components/pmi-onboarding/PMIOnboardingPortal.tsx']) {
    const s = src(p);
    assert.doesNotMatch(s, /\[\s*'(?:volunteer_term|vep_acceptance|meet_tribe|first_meeting)'\s*,\s*'(?:volunteer_term|vep_acceptance|meet_tribe|first_meeting)'/,
      `${p} tem uma lista literal de etapas de fato; leia closed_by`);
  }
});
