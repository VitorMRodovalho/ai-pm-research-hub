/**
 * #2718 (#1995, fatia 2) — a jornada de onboarding reconhece o fato e vale por papel.
 *
 * Regras do GP (16/10/2026): "Conheça sua tribo" fecha pela presença numa reunião da própria tribo; a trilha
 * segue pelo Credly e a tela avisa quem não tem Credly; o Código de Conduta segue por clique; só pesquisador e
 * líder recebem as etapas de membro; vídeo e tema do líder fecham pelo cadastro da tribo.
 *
 * O que este arquivo trava, cada asserção amarrando a condição ao resultado dentro do bloco que decide:
 *   - a regra 4 mora no CATÁLOGO (applies_to_role), e quem não lê o predicado não enxerga a regra: a fila da
 *     fatia 1 passa a aplicá-lo, e o marco de jornada concluída ignora etapa que não vale para a pessoa;
 *   - cada bloco novo do lote diário só toca pendência (pending/overdue) de quem a etapa vale;
 *   - o gatilho da presença fecha só "Conheça sua tribo", e só por reunião da tribo da pessoa.
 *
 * Os corpos SQL são lidos pela captura MAIS NOVA (#1932). Um seed inalcançável fica verde em todo teste: o
 * alcance de cada regra no dia da aplicação está na PR e na pós-condição da migration.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(import.meta.dirname, '../..');
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const body = (fn) => maskLineComments(latestFunctionCapture(ROOT, fn).body);
const migNames = readdirSync(resolve(ROOT, 'supabase/migrations')).filter((f) => f.endsWith('_2718_jornada_reconhece_o_fato.sql'));
const MIG = migNames.length === 1 ? maskLineComments(read(`supabase/migrations/${migNames[0]}`)) : '';
const DETECT = body('auto_detect_onboarding_completions');
const MILESTONE = body('_trg_record_onboarding_complete_milestone');
const PRESENCE = body('_trg_complete_meet_tribe_on_presence');
const QUEUE = body('get_affiliation_verification_queue');
const CHECKLIST = maskJsComments(read('src/components/onboarding/OnboardingChecklist.tsx'));

/** O bloco do lote que conclui `step`: do SELECT que o nomeia até o próximo INSERT (ou o fim do corpo). Parar no
 *  próximo INSERT, e não no próximo ON CONFLICT, impede que a asserção de um bloco case o texto do vizinho. */
function detectBlock(step) {
  const start = DETECT.indexOf(`SELECT m.id, '${step}', 'completed'`);
  assert.ok(start > 0, `o lote não tem bloco para ${step}`);
  const next = DETECT.indexOf('INSERT INTO onboarding_progress', start);
  return DETECT.slice(start, next === -1 ? DETECT.lastIndexOf('END;') : next);
}

const APPLIES = /public\.onboarding_step_applies\(s\.applies_to_role, m\.operational_role\)/;
const PENDING_ONLY = /ON CONFLICT \(member_id, step_key\) DO UPDATE\s+SET status = 'completed', completed_at = now\(\), updated_at = now\(\),\s+metadata = COALESCE\(onboarding_progress\.metadata, '\{\}'::jsonb\) \|\| EXCLUDED\.metadata\s+WHERE onboarding_progress\.status IN \('pending', 'overdue'\);/;

test('#2718 há exatamente uma migration da fatia 2', () => {
  assert.equal(migNames.length, 1, `esperava 1 migration *_2718_jornada_reconhece_o_fato.sql, achei ${migNames.length}`);
});

test('#2718 regra 4: etapa de membro só vale para pesquisador e líder, pelo catálogo', () => {
  assert.match(MIG, /UPDATE public\.onboarding_steps\s+SET applies_to_role = ARRAY\['researcher', 'tribe_leader'\]\s+WHERE applies_to_role IS NULL;/,
    'a regra mora no catálogo, para todo leitor que já aplica onboarding_step_applies (#1103)');
});

test('#2718 regra 4: a fila da fatia 1 só conta etapa que vale para o papel da pessoa', () => {
  assert.match(QUEUE, /FROM public\.onboarding_progress op\s+JOIN public\.onboarding_steps s ON s\.id = op\.step_key\s+WHERE op\.member_id = m\.id\s+AND public\.onboarding_step_applies\(s\.applies_to_role, m\.operational_role\)\s+\) ob ON true/);
});

test('#2718 regra 4: etapa que não vale para a pessoa não grava o marco de jornada concluída', () => {
  const guard = MILESTONE.search(/IF NOT EXISTS \(SELECT 1 FROM public\.onboarding_steps s\s+WHERE s\.id = NEW\.step_key\s+AND public\.onboarding_step_applies\(s\.applies_to_role, v_member_role\)\) THEN\s+RETURN NEW;\s+END IF;/);
  assert.ok(guard > 0, 'retorno antecipado ausente');
  assert.ok(guard < MILESTONE.indexOf('INTO v_all_complete'), 'o retorno tem de vir antes do cálculo de jornada completa');
});

test('#2718 regra 1: "Conheça sua tribo" fecha pela presença numa reunião da própria tribo', () => {
  const b = detectBlock('meet_tribe');
  assert.match(b, APPLIES);
  assert.match(b, /AND EXISTS \(SELECT 1 FROM attendance a\s+JOIN events e ON e\.id = a\.event_id\s+JOIN initiatives i ON i\.id = e\.initiative_id\s+WHERE a\.member_id = m\.id AND a\.present = true AND i\.legacy_tribe_id = m\.tribe_id\)/);
  assert.match(b, PENDING_ONLY);
});

test('#2718 regra 1: o gatilho fecha no instante da presença, só a etapa da tribo e só pela tribo da pessoa', () => {
  assert.match(PRESENCE, /UPDATE public\.onboarding_progress op\s+SET status = 'completed'[\s\S]*?WHERE op\.member_id = NEW\.member_id\s+AND op\.step_key = 'meet_tribe'\s+AND op\.status IN \('pending', 'overdue'\)\s+AND EXISTS \(SELECT 1 FROM public\.members m\s+JOIN public\.onboarding_steps s ON s\.id = 'meet_tribe'\s+JOIN public\.events e ON e\.id = NEW\.event_id\s+JOIN public\.initiatives i ON i\.id = e\.initiative_id\s+WHERE m\.id = NEW\.member_id\s+AND i\.legacy_tribe_id = m\.tribe_id\s+AND public\.onboarding_step_applies\(s\.applies_to_role, m\.operational_role\)\);/);
  assert.match(MIG, /CREATE TRIGGER trg_complete_meet_tribe_on_presence\s+AFTER INSERT OR UPDATE OF present ON public\.attendance\s+FOR EACH ROW WHEN \(NEW\.present = true\)\s+EXECUTE FUNCTION public\._trg_complete_meet_tribe_on_presence\(\);/,
    'ausência materializada pelo selamento (present=false) não pode fechar a etapa');
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._trg_complete_meet_tribe_on_presence\(\) FROM PUBLIC, anon, authenticated;/);
});

test('#2718 regra 5: vídeo pelo cadastro da tribo, tema por quadrante e descrição', () => {
  const v = detectBlock('leader_capture_video');
  assert.match(v, APPLIES);
  assert.match(v, /JOIN tribes t ON t\.id = m\.tribe_id[\s\S]*AND NULLIF\(btrim\(COALESCE\(t\.video_url, ''\)\), ''\) IS NOT NULL\s+ON CONFLICT/);
  assert.match(v, PENDING_ONLY);
  const t = detectBlock('leader_refine_theme');
  assert.match(t, APPLIES);
  assert.match(t, /AND t\.quadrant IS NOT NULL\s+AND EXISTS \(SELECT 1 FROM initiatives i, jsonb_each_text\(COALESCE\(i\.description_i18n, '\{\}'::jsonb\)\) d\s+WHERE i\.legacy_tribe_id = t\.id AND NULLIF\(btrim\(d\.value\), ''\) IS NOT NULL\)\s+ON CONFLICT/,
    'a descrição é a da iniciativa da tribo (fonte única desde a #2609)');
  assert.match(t, PENDING_ONLY);
  for (const step of ['leader_roadmap', 'leader_review_tribe']) {
    assert.ok(!DETECT.includes(`'${step}'`), `${step} segue por clique: não há fato medível`);
  }
});

test('#2718 o lote preserva a detecção que já existia', () => {
  assert.match(DETECT, /SELECT DISTINCT a\.member_id, 'first_meeting', 'completed', now\(\)\s+FROM attendance a\s+WHERE a\.present = true/,
    'PR11: só presença fecha a primeira reunião');
  assert.match(DETECT, /SELECT DISTINCT gp\.member_id, 'start_trail', 'completed', now\(\)\s+FROM gamification_points gp WHERE gp\.category = 'trail'/,
    'regra 2: a trilha continua fechando pelo badge sincronizado');
});

test('#2718 o sinal da fila: foi a reunião, mas nenhuma da própria tribo', () => {
  assert.match(QUEUE, /AND EXISTS \(SELECT 1 FROM public\.attendance a WHERE a\.member_id = m\.id AND a\.present\)\s+AND NOT EXISTS \(SELECT 1 FROM public\.attendance a\s+JOIN public\.events e ON e\.id = a\.event_id\s+JOIN public\.initiatives i ON i\.id = e\.initiative_id\s+WHERE a\.member_id = m\.id AND a\.present AND i\.legacy_tribe_id = m\.tribe_id\)\s+THEN 'tribe_pending_but_attended'/);
});

test('#2718 regra 2: a tela do membro avisa quem não tem Credly, na etapa da trilha', () => {
  assert.match(CHECKLIST, /\{s\.step_id === 'start_trail' && !member\?\.credly_url && \(\s+<>\s+<p className="[^"]*">\{l\.credlyMissing\}<\/p>\s+<a href=\{`\$\{lp\}\/profile`\}[^>]*>\s+🔗 \{l\.connectCredly\}/);
  for (const loc of ['pt-BR', 'en-US', 'es-LATAM']) {
    const entry = CHECKLIST.match(new RegExp(`'${loc}': \\{[^\\n]*\\}`));
    assert.ok(entry, `dicionário ${loc} ausente`);
    assert.match(entry[0], /credlyMissing: '[^']+'/, `${loc} sem credlyMissing`);
    assert.match(entry[0], /connectCredly: '[^']+'/, `${loc} sem connectCredly`);
  }
});

// ───────────────────────── DB-aware: o catálogo vivo ─────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const skip = SUPABASE_URL && SUPABASE_KEY ? false : 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#2718 vivo: etapa de membro vale para pesquisador e líder, não para convidado', { skip }, async () => {
  const { createClient } = await import('@supabase/supabase-js');
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: steps, error } = await sb.from('onboarding_steps').select('id, applies_to_role');
  assert.ok(!error, error?.message);
  const member = steps.filter((s) => !String(s.id).startsWith('leader_'));
  assert.ok(member.length >= 7, `etapas de membro no catálogo: ${member.length}`);
  for (const s of member) assert.deepEqual(s.applies_to_role, ['researcher', 'tribe_leader'], `${s.id} vale para quem?`);
  const applies = async (role) => {
    const { data, error: e } = await sb.rpc('onboarding_step_applies', { p_applies_to_role: ['researcher', 'tribe_leader'], p_member_role: role });
    assert.ok(!e, e?.message);
    return data;
  };
  assert.equal(await applies('researcher'), true);
  assert.equal(await applies('tribe_leader'), true);
  assert.equal(await applies('guest'), false, 'convidado não recebe etapa de membro');
  assert.equal(await applies('chapter_liaison'), false, 'ponto focal não recebe etapa de membro');
});
