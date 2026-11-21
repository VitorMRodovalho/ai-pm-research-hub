/**
 * Jornadas fatia C: uma regra de perfil (decisão do GP, 21/11/2026).
 *
 * O perfil pronto é o que a assinatura do Termo exige (sign_volunteer_agreement): o guard extrai a lista de campos
 * da assinatura e a compara com o helper e com o gatilho. A etapa fecha só pelo fato (closed_by = 'fact'), pelo
 * lote, pela checagem da aprovação e na hora, por um gatilho em members, sempre só em etapa aberta e só onde a
 * etapa vale para o papel da jornada (#3152). Nada rebaixa completed.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG_DIR = resolve(ROOT, 'supabase/migrations');
const migFiles = readdirSync(MIG_DIR).filter((f) => /^\d{14}_jornadas_c_uma_regra_de_perfil\.sql$/.test(f));
const RAW = migFiles.length === 1 ? readFileSync(join(MIG_DIR, migFiles[0]), 'utf8') : '';
const MIG = maskLineComments(RAW);
const cap = (n) => maskLineComments(latestFunctionCapture(ROOT, n).block);
const src = (p) => maskJsComments(readFileSync(resolve(ROOT, p), 'utf8'));
const APPLIES_J = (who) => new RegExp(`public\\.onboarding_step_applies\\(s\\.applies_to_role, public\\._onboarding_journey_role\\(${who}\\)\\)`);
const OPEN = /status IN \('pending', 'overdue'\)/;

/** Campos que a assinatura do Termo exige, na ordem em que ela os confere. */
function camposDaAssinatura() {
  const b = cap('sign_volunteer_agreement');
  return [...b.matchAll(/v_missing_fields := array_append\(v_missing_fields, '([a-z_]+)'\)/g)].map((m) => m[1]);
}
/** Campos do helper: cada um com IS NOT NULL e, se texto, com trim não vazio. */
function camposDoHelper() {
  const b = cap('_member_profile_ready');
  return [...b.matchAll(/m\.([a-z_]+) IS NOT NULL(?: AND length\(trim\(m\.\1\)\) > 0)?/g)].map((m) => m[1]);
}

test('C0. a migration existe', () => {
  assert.equal(migFiles.length, 1, `esperava 1 migration, achei ${migFiles.length}`);
});

test('C1. o perfil pronto são os campos da assinatura do Termo, nem mais nem menos', () => {
  const termo = camposDaAssinatura();
  assert.equal(termo.length, 7, `a assinatura confere ${termo.length} campos`);
  assert.deepEqual(camposDoHelper(), termo, 'o helper diverge da assinatura');
  const b = cap('_member_profile_ready');
  for (const f of termo.filter((x) => x !== 'birth_date')) {
    assert.match(b, new RegExp(`m\\.${f} IS NOT NULL AND length\\(trim\\(m\\.${f}\\)\\) > 0`), `${f} vazio contaria como preenchido`);
  }
  assert.doesNotMatch(b, /photo_url|linkedin_url/, 'foto e LinkedIn não fazem parte (decisão do GP)');
  assert.match(b, /FROM public\.members m WHERE m\.id = p_member_id\), false\);/, 'membro inexistente é perfil não pronto');
  assert.doesNotMatch(b, /\bUPDATE\b|\bINSERT\b|\bDELETE\b/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._member_profile_ready\(uuid\) FROM PUBLIC, anon, authenticated;/);
});

test('C2. a etapa de perfil fecha só pelo fato', () => {
  assert.match(MIG, /UPDATE public\.onboarding_steps SET closed_by = 'fact' WHERE id = 'complete_profile';/);
});

test('C3. a checagem da aprovação usa a regra única, só em etapa aberta e onde a etapa vale', () => {
  const b = cap('check_pre_onboarding_auto_steps');
  assert.match(b, /v_profile_complete := public\._member_profile_ready\(p_member_id\);/);
  const blk = b.slice(b.indexOf("op.step_key = 'complete_profile'"), b.indexOf("step_key = 'setup_credly'"));
  assert.match(blk, /op\.step_key = 'complete_profile' AND op\.status IN \('pending', 'overdue'\)\s+AND v_profile_complete\s+AND EXISTS \(SELECT 1 FROM onboarding_steps s\s+WHERE s\.id = 'complete_profile'\s+AND public\.onboarding_step_applies\(s\.applies_to_role, public\._onboarding_journey_role\(p_member_id\)\)\);/);
  assert.doesNotMatch(b, /v_profile_complete := v_member\./, 'a regra antiga de 7 campos voltou');
});

test('C4. o lote: perfil pela regra única, sem o 4 de 6, e os três primeiros blocos só tocam etapa aberta de quem a etapa vale', () => {
  const d = cap('auto_detect_onboarding_completions');
  assert.doesNotMatch(d, />= 4/, 'a regra 4 de 6 voltou');
  assert.doesNotMatch(d, /status != 'completed'/, "status != 'completed' sobrescreve skipped");
  assert.doesNotMatch(d, /m\.operational_role/, 'o lote lê o papel pela jornada (#3152)');
  const p = d.slice(d.indexOf("SELECT m.id, 'complete_profile'"), d.indexOf("'start_trail'"));
  assert.match(p, /WHERE m\.is_active\s+AND public\.onboarding_step_applies\(s\.applies_to_role, public\._onboarding_journey_role\(m\.id\)\)\s+AND public\._member_profile_ready\(m\.id\)\s+ON CONFLICT[\s\S]*?WHERE onboarding_progress\.status IN \('pending', 'overdue'\);/);
  for (const [step, from] of [['start_trail', 'gp.member_id'], ['first_meeting', 'a.member_id']]) {
    const i = d.indexOf(`'${step}', 'completed'`);
    const blk = d.slice(i, d.indexOf('INSERT INTO onboarding_progress', i));
    assert.match(blk, new RegExp(`AND EXISTS \\(SELECT 1 FROM members m JOIN onboarding_steps s ON s\\.id = '${step}'\\s+WHERE m\\.id = ${from.replace('.', '\\.')} AND m\\.is_active\\s+AND public\\.onboarding_step_applies\\(s\\.applies_to_role, public\\._onboarding_journey_role\\(m\\.id\\)\\)\\)\\s+ON CONFLICT[^;]*WHERE onboarding_progress\\.status IN \\('pending', 'overdue'\\);`),
      `${step}: recorte por papel ou por estado ausente`);
  }
});

test('C5. o gatilho: só os 7 campos, só mudança real de membro ativo, sai cedo e não volta a members', () => {
  const t = MIG.match(/CREATE TRIGGER trg_complete_profile_on_ready_fields\s+AFTER UPDATE OF ([a-z_, ]+) ON public\.members\s+FOR EACH ROW\s+WHEN \(([\s\S]*?)\)\s+EXECUTE FUNCTION public\._trg_complete_profile_on_ready_fields\(\);/);
  assert.ok(t, 'gatilho ausente ou disparando em qualquer UPDATE');
  const termo = camposDaAssinatura();
  assert.deepEqual(t[1].split(',').map((s) => s.trim()), termo, 'UPDATE OF diverge dos campos da assinatura');
  assert.match(t[2], /^NEW\.is_active\s+AND \(OLD\.[\s\S]*\)\s+IS DISTINCT FROM\s+\(NEW\.[\s\S]*\)$/);
  const olds = [...t[2].matchAll(/OLD\.([a-z_]+)/g)].map((m) => m[1]);
  const news = [...t[2].matchAll(/NEW\.([a-z_]+)/g)].map((m) => m[1]).filter((f) => f !== 'is_active');
  assert.deepEqual(olds, termo);
  assert.deepEqual(news, termo);
  const f = cap('_trg_complete_profile_on_ready_fields');
  const early = f.search(/IF NOT EXISTS \(SELECT 1 FROM public\.onboarding_progress op\s+WHERE op\.member_id = NEW\.id AND op\.step_key = 'complete_profile'\s+AND op\.status IN \('pending', 'overdue'\)\) THEN\s+RETURN NULL;\s+END IF;/);
  assert.ok(early > 0, 'sem a saída cedo, todo salvamento de perfil lê o helper');
  assert.ok(early < f.indexOf('_member_profile_ready'), 'a saída cedo vem antes do helper');
  assert.match(f, /WHERE op\.member_id = NEW\.id AND op\.step_key = 'complete_profile' AND op\.status IN \('pending', 'overdue'\)\s+AND public\._member_profile_ready\(NEW\.id\)\s+AND EXISTS \(SELECT 1 FROM public\.onboarding_steps s\s+WHERE s\.id = 'complete_profile'\s+AND public\.onboarding_step_applies\(s\.applies_to_role, public\._onboarding_journey_role\(NEW\.id\)\)\);/);
  assert.doesNotMatch(f, /UPDATE\s+(public\.)?members\b/i, 'escrever em members faria o gatilho voltar a si');
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._trg_complete_profile_on_ready_fields\(\) FROM PUBLIC, anon, authenticated;/);
});

test('C6. a gestão vê a evidência do perfil pela mesma regra', () => {
  const a = cap('get_onboarding_journey_admin');
  assert.match(a, /WHEN 'complete_profile' THEN \(\s+CASE WHEN public\._member_profile_ready\(mem\.id\) THEN jsonb_build_object\('kind', 'profile'\) END\)/);
  assert.match(src('src/components/admin/OnboardingJourneyIsland.tsx'), /case 'profile': return t\('comp\.onboardingJourney\.evProfile'/);
  for (const loc of ['pt-BR', 'en-US', 'es-LATAM']) {
    assert.match(readFileSync(resolve(ROOT, `src/i18n/${loc}.ts`), 'utf8'), /'comp\.onboardingJourney\.evProfile': '[^']+'/, `${loc} sem evProfile`);
  }
});

test('C7. o checklist do membro não promete marcar o perfil: leva ao perfil e diz como a etapa fecha', () => {
  const c = src('src/components/onboarding/OnboardingChecklist.tsx');
  const blk = c.match(/\{s\.step_id === 'complete_profile' && \(([\s\S]*?)\n\s{20}\)\}/);
  assert.ok(blk, 'bloco do perfil ausente');
  assert.doesNotMatch(blk[1], /markDone/, 'o link do perfil não marca nada');
  assert.match(blk[1], /\{l\.profileByFact\}[\s\S]*href=\{`\$\{lp\}\/profile`\}[\s\S]*\{l\.completeProfile\}/);
  for (const loc of ['pt-BR', 'en-US', 'es-LATAM']) {
    const entry = c.match(new RegExp(`'${loc}': \\{[^\\n]*\\}`));
    assert.ok(entry, `dicionário ${loc} ausente`);
    assert.match(entry[0], /completeProfile: '[^']+'/);
    assert.match(entry[0], /profileByFact: '[^']+'/);
  }
});

test('C8. emulação do #785: nenhuma SECDEF da migration seria acusada', () => {
  const fns = [...RAW.matchAll(/CREATE (?:OR REPLACE )?FUNCTION public\.(\w+)\(([^)]*)\)[\s\S]*?AS \$(\w*)\$([\s\S]*?)\$\3\$/g)];
  assert.equal(fns.length, 5, `esperava 5 funções, achei ${fns.length}`);
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
