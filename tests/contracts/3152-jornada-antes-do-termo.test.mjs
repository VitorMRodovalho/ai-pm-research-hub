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

// ---------------------------------------------------------------------------------------------------------------
// #3156: os outros leitores e escritores da jornada passam a recortar as etapas pelo papel da jornada.
// ---------------------------------------------------------------------------------------------------------------
const mig3156 = readdirSync(MIG_DIR).filter((f) => /^\d{14}_3156_jornada_papel_em_todas\.sql$/.test(f));
const RAW3156 = mig3156.length === 1 ? readFileSync(join(MIG_DIR, mig3156[0]), 'utf8') : '';

test('G7. as cinco funções da #3156 tiram o papel do helper e recortam por ele', () => {
  assert.equal(mig3156.length, 1, `esperava 1 migration da #3156, achei ${mig3156.length}`);

  const a = cap('complete_onboarding_step');
  assert.match(a, /SELECT id INTO v_member_id FROM members WHERE auth_id = auth\.uid\(\);\s+IF NOT FOUND THEN RETURN[^;]*;\s+END IF;\s+v_member_role := public\._onboarding_journey_role\(v_member_id\);/);
  assert.match(a, /WHERE s\.id = p_step_id\s+AND public\.onboarding_step_applies\(s\.applies_to_role, v_member_role\)\s+\) THEN\s+RETURN jsonb_build_object\('error', 'Invalid step'\)/,
    'o clique recusa a etapa que não vale, pelo papel da jornada');

  const b = cap('get_candidate_onboarding_progress');
  assert.match(b, /v_member_role := public\._onboarding_journey_role\(v_mid\);/);
  assert.match(b, /'total', \(SELECT count\(\*\) FROM onboarding_progress WHERE member_id = v_mid\s+AND step_key IN \(SELECT id FROM onboarding_steps s WHERE public\.onboarding_step_applies\(s\.applies_to_role, v_member_role\)\)\)/);

  const c = cap('admin_complete_onboarding_step');
  assert.match(c, /SELECT public\._onboarding_journey_role\(m\.id\) INTO v_role FROM members m WHERE m\.id = p_member_id;\s+IF NOT FOUND THEN\s+RAISE EXCEPTION 'Member not found'/,
    'o membro inexistente continua recusado, e o papel vem do helper');
  assert.match(c, /WHERE s\.id = p_step_key AND public\.onboarding_step_applies\(s\.applies_to_role, v_role\)\) THEN\s+RAISE EXCEPTION 'Step % does not apply to this member'/);

  const d = cap('get_onboarding_dashboard');
  const laterals = d.match(/FROM members m\s+CROSS JOIN LATERAL \(SELECT public\._onboarding_journey_role\(m\.id\) AS journey_role\) jr/g) || [];
  assert.equal(laterals.length, 2, 'o papel da jornada é lido uma vez por membro, no resumo e na lista');
  const uses = d.match(/public\.onboarding_step_applies\(s\.applies_to_role, jr\.journey_role\)/g) || [];
  assert.equal(uses.length, 3, 'pendentes do resumo, completed_count e total_steps');

  const e = cap('_trg_complete_meet_tribe_on_presence');
  assert.match(e, /AND i\.legacy_tribe_id = m\.tribe_id\s+AND public\.onboarding_step_applies\(s\.applies_to_role, public\._onboarding_journey_role\(m\.id\)\)\);/);

  for (const [n, body] of [['complete_onboarding_step', a], ['get_candidate_onboarding_progress', b],
    ['admin_complete_onboarding_step', c], ['get_onboarding_dashboard', d], ['_trg_complete_meet_tribe_on_presence', e]]) {
    assert.doesNotMatch(body, /operational_role/, `${n} não lê mais o cache`);
  }
});

// Exceções nomeadas: recortam a jornada por outro papel, de propósito.
const EXCECOES = {
  approve_selection_application:
    'recorta pelo papel-alvo da candidatura (v_target_role), o papel que a aprovação está concedendo; não lê o cache para o recorte',
  get_affiliation_verification_queue:
    'é da filiação (fila, portão, radar, nudge), de outra lane; adotar o helper é decisão dela',
};
// Formas aceitas para o papel no recorte: o helper direto, a coluna derivada dele ou uma variável atribuída por ele.
const ROLE_OK = /^(public\._onboarding_journey_role\([\w.]+\)|jr\.journey_role|mem\.journey_role)$/;

test('G8. nenhuma função da jornada recorta etapa pelo cache de autoridade, salvo as exceções nomeadas', () => {
  // Candidatas: as funções definidas em alguma migration que chama o recorte. A mais nova de cada uma decide se ela
  // ainda chama: uma função que passou a chamar entra pela própria migration nova.
  const cand = new Set();
  for (const f of readdirSync(MIG_DIR).filter((x) => x.endsWith('.sql'))) {
    const sql = maskLineComments(readFileSync(join(MIG_DIR, f), 'utf8'));
    if (!/onboarding_step_applies\(/.test(sql)) continue;
    for (const m of sql.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?(\w+)\s*\(/gi)) cand.add(m[1].toLowerCase());
  }
  assert.ok(cand.size >= 10, `varredura pequena demais: ${cand.size} candidatas`);
  const checked = [];
  for (const name of [...cand].sort()) {
    if (name === 'onboarding_step_applies') continue;
    const body = maskLineComments(latestFunctionCapture(ROOT, name).body);
    const calls = [...body.matchAll(/onboarding_step_applies\(s\.applies_to_role,\s*((?:[^()]|\([^()]*\))+)\)/g)].map((x) => x[1].trim());
    if (/onboarding_step_applies\(/.test(body) && calls.length === 0) assert.fail(`${name}: chamada de onboarding_step_applies em forma que o guard não lê`);
    if (calls.length === 0) continue;
    if (EXCECOES[name]) { checked.push(`${name} (exceção)`); continue; }
    for (const arg of calls) {
      if (ROLE_OK.test(arg)) continue;
      assert.match(arg, /^v_\w+$/, `${name}: papel do recorte em forma não aceita: ${arg}`);
      const assign = new RegExp(`${arg} := public\\._onboarding_journey_role\\(|SELECT public\\._onboarding_journey_role\\([\\w.]+\\) INTO ${arg}\\b`);
      assert.match(body, assign, `${name}: ${arg} não vem do papel da jornada`);
      assert.doesNotMatch(body, new RegExp(`operational_role[^;]*INTO[^;]*\\b${arg}\\b`), `${name}: ${arg} também é lida do cache`);
    }
    checked.push(name);
  }
  for (const n of Object.keys(EXCECOES)) assert.ok(checked.includes(`${n} (exceção)`), `exceção ${n} não chama mais o recorte: retire-a da lista`);
  for (const n of ['complete_onboarding_step', 'get_candidate_onboarding_progress', 'admin_complete_onboarding_step',
    'get_onboarding_dashboard', '_trg_complete_meet_tribe_on_presence', 'get_my_onboarding']) {
    assert.ok(checked.includes(n), `${n} saiu da varredura`);
  }
});

test('G9. emulação do #785 sobre a migration da #3156', () => {
  const fns = [...RAW3156.matchAll(/CREATE (?:OR REPLACE )?FUNCTION public\.(\w+)\(([^)]*)\)[\s\S]*?AS \$(\w*)\$([\s\S]*?)\$\3\$/g)];
  assert.equal(fns.length, 5, `esperava 5 funções, achei ${fns.length}`);
  for (const [hdr, name, , , body] of fns) {
    const secdef = /SECURITY DEFINER/.test(hdr);
    const reads = /(board_items|project_boards|board_members|board_lifecycle_events|board_item_|board_drive_links|meeting_action_items)/.test(body)
      || /\bevents\b/.test(body) || /\binitiatives\b/.test(body);
    const writer = /(INSERT |UPDATE |DELETE )/.test(body.toUpperCase());
    const revokedAuth = new RegExp(`REVOKE[^;]*FUNCTION public\\.${name}\\([^;]*FROM[^;]*authenticated`).test(RAW3156);
    const gated = /rls_can_see_(initiative|board|item)|confidential/.test(body);
    if (secdef && reads && !writer && !revokedAuth) assert.ok(gated, `${name} seria acusada pelo #785`);
  }
});
