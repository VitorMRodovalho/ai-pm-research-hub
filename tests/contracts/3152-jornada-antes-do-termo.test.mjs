/**
 * #3152: a jornada de onboarding lê o papel que vale para a jornada, sem mudar a autoridade.
 *
 * Quem tem vínculo ativo que pede Termo e ainda não tem certificado é guest na escada (_derive_operational_role,
 * #1925), e isso fica. Os leitores da jornada passam a filtrar as etapas por _onboarding_journey_role, que devolve o
 * papel que o vínculo dará quando o Termo for assinado. As listas de papéis do helper têm de ser as da escada: o
 * guard as extrai das duas funções e compara.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG_DIR = resolve(ROOT, 'supabase/migrations');
const migFiles = readdirSync(MIG_DIR).filter((f) => /^\d{14}_3152_jornada_antes_do_termo\.sql$/.test(f));
const RAW = migFiles.length === 1 ? readFileSync(join(MIG_DIR, migFiles[0]), 'utf8') : '';
const MIG = maskLineComments(RAW);
const cap = (n) => maskLineComments(latestFunctionCapture(ROOT, n).block);
const src = (p) => maskJsComments(readFileSync(resolve(ROOT, p), 'utf8'));
const list = (s) => [...s.matchAll(/'([a-z_]+)'/g)].map((x) => x[1]).sort();

test('G0. a migration existe', () => {
  assert.equal(migFiles.length, 1, `esperava 1 migration, achei ${migFiles.length}`);
});

test('G1. o helper só troca o papel de guest, e só por vínculo ativo, vigente, que pede Termo e não tem certificado', () => {
  const b = cap('_onboarding_journey_role');
  assert.match(b, /WHEN m\.operational_role IS DISTINCT FROM 'guest' THEN m\.operational_role/);
  assert.match(b, /WHERE ae\.person_id = m\.person_id\s+AND ae\.status = 'active'\s+AND ae\.start_date <= CURRENT_DATE AND \(ae\.end_date IS NULL OR ae\.end_date >= CURRENT_DATE\)\s+AND ae\.requires_agreement IS TRUE\s+AND ae\.agreement_certificate_id IS NULL\s+\), m\.operational_role\)/,
    'sem vínculo nessas condições, o papel continua o do cache');
  assert.doesNotMatch(b, /\bUPDATE\b|\bINSERT\b/, 'o helper não escreve: a autoridade e o cache não mudam');
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._onboarding_journey_role\(uuid\) FROM PUBLIC, anon, authenticated;/);
});

test('G2. os papéis do helper são os degraus da escada (#1925), sem cópia que divirja', () => {
  const h = cap('_onboarding_journey_role');
  const d = cap('_derive_operational_role');
  const leaderH = h.match(/WHEN bool_or\(ae\.kind = 'volunteer' AND ae\.role IN \(([^)]*)\)\) THEN 'tribe_leader'/);
  const leaderD = d.match(/WHEN bool_or\(ae\.kind = 'volunteer' AND ae\.role IN \(([^)]*)\)\)\s+THEN 'tribe_leader'/);
  assert.ok(leaderH && leaderD, 'degrau de líder ausente');
  assert.deepEqual(list(leaderH[1]), list(leaderD[1]));
  const resH = h.match(/\(ae\.kind = 'volunteer' AND ae\.role IN \(([^)]*)\)\)\s+OR \(ae\.kind = 'study_group_owner'\s+AND ae\.role IN \(([^)]*)\)\)\s+\) THEN 'researcher'/);
  const resD = d.match(/\(ae\.kind = 'volunteer' AND ae\.role IN \(([^)]*)\)\)\s+OR \(ae\.kind IN \(([^)]*)\)\s+AND ae\.role IN \(([^)]*)\)\)/);
  assert.ok(resH && resD, 'degrau de pesquisador ausente');
  assert.deepEqual(list(resH[1]), list(resD[1]), 'papéis de volunteer que dão researcher');
  assert.ok(list(resD[2]).includes('study_group_owner'), 'study_group_owner é kind de pesquisador na escada');
  assert.deepEqual(list(resH[2]), list(resD[3]), 'papéis de study_group_owner que dão researcher');
});

test('G3. get_my_onboarding e o gatilho de conclusão leem o papel da jornada', () => {
  const g = cap('get_my_onboarding');
  assert.match(g, /SELECT id INTO v_member_id\s+FROM members WHERE auth_id = auth\.uid\(\);\s+IF NOT FOUND THEN RETURN[^;]*;\s+END IF;\s+v_member_role := public\._onboarding_journey_role\(v_member_id\);/);
  assert.doesNotMatch(g, /operational_role/, 'get_my_onboarding não lê mais o cache');
  const t = cap('_trg_record_onboarding_complete_milestone');
  assert.match(t, /v_member_role := public\._onboarding_journey_role\(NEW\.member_id\);/);
  assert.doesNotMatch(t, /operational_role/, 'o gatilho não lê mais o cache');
});

test('G4. a leitura da gestão filtra pelo papel da jornada, mostra os dois papéis e nunca devolve steps null', () => {
  const b = cap('get_onboarding_journey_admin');
  assert.match(b, /public\._onboarding_journey_role\(m\.id\) AS journey_role/);
  assert.match(b, /JOIN onboarding_steps s ON public\.onboarding_step_applies\(s\.applies_to_role, mem\.journey_role\)/);
  assert.doesNotMatch(b, /onboarding_step_applies\([^)]*operational_role\)/);
  assert.match(b, /'operational_role', mem\.operational_role, 'journey_role', mem\.journey_role,/);
  assert.match(b, /'steps', COALESCE\(\(SELECT jsonb_agg\(jsonb_build_object\([\s\S]*?FROM srcd x WHERE x\.member_id = mem\.id\), '\[\]'::jsonb\)/);
});

test('G5. a tela diz quando a jornada vale pelo vínculo antes do Termo', () => {
  const s = src('src/components/admin/OnboardingJourneyIsland.tsx');
  assert.match(s, /\{m\.journey_role && m\.journey_role !== m\.operational_role && \(\s+<span[^>]*>\{t\('comp\.onboardingJourney\.beforeTerm'/);
});

test('G6. emulação do #785: nenhuma SECDEF da migration seria acusada', () => {
  const fns = [...RAW.matchAll(/CREATE (?:OR REPLACE )?FUNCTION public\.(\w+)\(([^)]*)\)[\s\S]*?AS \$(\w*)\$([\s\S]*?)\$\3\$/g)];
  assert.ok(fns.length >= 4, `esperava 4 funções, achei ${fns.length}`);
  for (const [hdr, name, , , body] of fns) {
    const secdef = /SECURITY DEFINER/.test(hdr);
    const reads = /(board_items|project_boards|board_members|board_lifecycle_events|board_item_|board_drive_links|meeting_action_items)/.test(body)
      || /\bevents\b/.test(body) || /\binitiatives\b/.test(body);
    const writer = /(INSERT |UPDATE |DELETE )/.test(body.toUpperCase());
    const revokedAuth = new RegExp(`REVOKE[^;]*FUNCTION public\\.${name}\\([^;]*FROM[^;]*authenticated`).test(RAW);
    const gated = /rls_can_see_(initiative|board|item)|confidential/.test(body);
    if (secdef && reads && !writer && !revokedAuth) assert.ok(gated, `${name} seria acusada pelo #785`);
  }
});
