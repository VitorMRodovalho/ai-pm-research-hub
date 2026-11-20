/**
 * Jornadas de onboarding, fatia B (parte 2): a gestão vê, audita e corrige a jornada pela tela.
 *
 * - get_onboarding_journey_admin (manage_member) devolve a fonte de cada fechamento DERIVADA DA EVIDÊNCIA:
 *   gp, fato, clique ou sem_evidencia. A ordem do CASE é a regra: a marca do GP vence, depois o catálogo diz clique,
 *   depois a evidência decide entre fato e sem_evidencia.
 * - admin_reopen_onboarding_step (manage_platform) reabre com justificativa, guarda o que havia antes e tira a marca
 *   do GP, para o próximo fechamento não herdar a fonte.
 * - /admin/jornadas tem link na sidebar, redirects en/es, e só mostra os botões do GP a quem tem manage_platform.
 * A coerência link × página × RPC da rota é do guard 2974-f1-link-e-pagina, que itera ADMIN_ROUTE_ACCESS.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG_DIR = resolve(ROOT, 'supabase/migrations');
const migFiles = readdirSync(MIG_DIR).filter((f) => /^\d{14}_jornadas_b2_jornada_na_tela\.sql$/.test(f));
const MIG = migFiles.length === 1 ? maskLineComments(readFileSync(join(MIG_DIR, migFiles[0]), 'utf8')) : '';
const cap = (n) => maskLineComments(latestFunctionCapture(ROOT, n).block);
const src = (p) => maskJsComments(readFileSync(resolve(ROOT, p), 'utf8'));

test('C0. a migration existe', () => {
  assert.equal(migFiles.length, 1, `esperava 1 migration, achei ${migFiles.length}`);
});

test('C1. a leitura pede manage_member antes de ler qualquer coisa', () => {
  const b = cap('get_onboarding_journey_admin');
  const gate = b.search(/IF v_caller_id IS NULL OR NOT public\.can_by_member\(v_caller_id, 'manage_member'\) THEN\s+RAISE EXCEPTION/);
  assert.ok(gate > 0, 'portão ausente');
  assert.ok(gate < b.indexOf('WITH mem AS'), 'o portão tem de vir antes da leitura');
  assert.doesNotMatch(b, /'manage_platform'/, 'a leitura não pergunta manage_platform: quem lê são diretorias e gestão');
});

test('C2. a fonte: GP vence, o catálogo diz clique, a evidência decide entre fato e sem_evidencia', () => {
  const b = cap('get_onboarding_journey_admin');
  assert.match(b, /CASE\s+WHEN r\.status IS DISTINCT FROM 'completed' THEN NULL\s+WHEN r\.metadata->>'closed_by' = 'gp' THEN 'gp'\s+WHEN r\.step_closed_by = 'member' THEN 'clique'\s+WHEN r\.evidence IS NOT NULL THEN 'fato'\s+ELSE 'sem_evidencia'\s+END AS source/);
  assert.match(b, /s\.closed_by AS step_closed_by/, 'a fonte de clique vem do catálogo, não de uma lista');
});

test('C3. cada etapa de fato tem a sua evidência', () => {
  const b = cap('get_onboarding_journey_admin');
  assert.match(b, /WHEN 'volunteer_term' THEN \([^;]*?FROM certificates c\s+WHERE c\.member_id = mem\.id AND c\.type = 'volunteer_agreement' AND c\.revoked_at IS NULL/);
  assert.match(b, /WHEN 'vep_acceptance' THEN \([^;]*?FROM selection_applications sa\s+WHERE \(sa\.id = op\.application_id OR lower\(sa\.email\) = lower\(mem\.email\)\)\s+AND sa\.vep_status_raw IN \('Active', 'Complete'\)/);
  assert.match(b, /WHEN 'first_meeting' THEN \([^;]*?FROM attendance a JOIN events e ON e\.id = a\.event_id\s+WHERE a\.member_id = mem\.id AND a\.present\s/);
  assert.match(b, /WHEN 'meet_tribe' THEN \([^;]*?WHERE a\.member_id = mem\.id AND a\.present\s+AND i\.legacy_tribe_id IS NOT NULL\s+AND \(mem\.tribe_id IS NULL OR i\.legacy_tribe_id = mem\.tribe_id\)/);
});

test('C4. reabrir é do GP: portão, justificativa, só etapa fechada, histórico e a marca do GP sai', () => {
  const b = cap('admin_reopen_onboarding_step');
  const gate = b.search(/IF v_caller_id IS NULL OR NOT public\.can_by_member\(v_caller_id, 'manage_platform'\) THEN\s+RAISE EXCEPTION/);
  const note = b.search(/IF p_note IS NULL OR length\(btrim\(p_note\)\) < 3 THEN\s+RAISE EXCEPTION/);
  const closed = b.search(/IF v_row\.status NOT IN \('completed', 'skipped'\) THEN\s+RAISE EXCEPTION/);
  const write = b.indexOf('UPDATE onboarding_progress');
  assert.ok(gate > 0 && note > gate && closed > note && write > closed, 'portão, justificativa, etapa fechada, depois a escrita');
  assert.match(b, /SET status = 'pending', completed_at = NULL, updated_at = now\(\),\s+metadata = \(COALESCE\(metadata, '\{\}'::jsonb\) - 'closed_by' - 'gp_member_id' - 'gp_note' - 'gp_at'\)\s+\|\| jsonb_build_object\('reopen_history',\s+COALESCE\(metadata->'reopen_history', '\[\]'::jsonb\) \|\| jsonb_build_array\(v_entry\)\)/);
  assert.match(b, /v_entry := jsonb_build_object\(\s+'reopened_by', v_caller_id, 'reopen_note', btrim\(p_note\)/);
});

test('C5. sem anon nas duas funções', () => {
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.get_onboarding_journey_admin\(uuid\) FROM PUBLIC, anon;/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.admin_reopen_onboarding_step\(uuid, text, text\) FROM PUBLIC, anon;/);
});

test('C6. a tela não fica órfã: entrada de rota, link na sidebar e redirects', () => {
  const nav = src('src/lib/navigation.config.ts');
  assert.match(nav, /'\/admin\/jornadas': \{ actions: \['manage_member'\], rpcs: \['get_onboarding_journey_admin'\] \}/);
  assert.match(nav, /\{ href: '\/admin\/jornadas', label: \{[^}]*\}, icon: 'Route' \}/, 'link na sidebar ausente');
  assert.match(src('src/components/admin/AdminSidebar.tsx'), /const ICONS[^;]*\bRoute,/, 'o ícone tem de estar no mapa, senão o link some');
  for (const l of ['en', 'es']) assert.ok(existsSync(resolve(ROOT, `src/pages/${l}/admin/jornadas.astro`)), `redirect ${l} ausente`);
});

test('C7. os botões do GP só aparecem a quem pode, e marcar só vale para etapa de fato aberta', () => {
  const s = src('src/components/admin/OnboardingJourneyIsland.tsx');
  assert.match(s, /setCanCorrect\(canForUnscoped\('manage_platform'\)\)/);
  assert.match(s, /const canMark = canCorrect && isFact\(s\.step_key\) && !isClosed\(s\);/);
  assert.match(s, /const canReopen = canCorrect && isClosed\(s\);/);
  assert.match(s, /\{canMark && \(\s+<button type="button" onClick=\{\(\) => \{ setAction\(\{ memberId: m\.member_id, stepKey: s\.step_key, kind: 'complete' \}\)/);
  assert.match(s, /\{canReopen && \(\s+<button type="button" onClick=\{\(\) => \{ setAction\(\{ memberId: m\.member_id, stepKey: s\.step_key, kind: 'reopen' \}\)/);
  assert.match(s, /action\.kind === 'complete' \? 'admin_complete_onboarding_step' : 'admin_reopen_onboarding_step'/);
  assert.match(s, /if \(note\.trim\(\)\.length < 3\) \{ setActionError/, 'a tela também exige a justificativa');
  assert.doesNotMatch(s, /window\.(confirm|alert|prompt)\(/, 'sem diálogo do navegador');
});

test('C8. a fonte é a do servidor: a tela não deriva fato nem copia a lista de etapas de fato', () => {
  const s = src('src/components/admin/OnboardingJourneyIsland.tsx');
  assert.match(s, /const isFact = useCallback\(\(id: string\) => stepById\.get\(id\)\?\.closed_by === 'fact'/);
  assert.doesNotMatch(s, /'(?:volunteer_term|vep_acceptance|meet_tribe|first_meeting)'/, 'a tela tem nome de etapa de fato escrito à mão');
});
