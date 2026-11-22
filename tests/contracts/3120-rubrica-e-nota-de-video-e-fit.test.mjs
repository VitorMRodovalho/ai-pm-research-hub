/**
 * #3120 (ADR-0134 §3): rubrica por vaga e parte, e a nota de vídeo e de fit do piloto da linha.
 *
 * Decisões do GP (20/11/2026): escala de 3 níveis (fraco 1, médio 2, forte 3) com âncora em cada nível; no fit, mínimo
 * opcional por critério, e nota abaixo dele exige justificativa naquele critério sem bloquear a decisão; o fit só abre
 * depois de enviada ao menos 1 nota de vídeo da candidatura. Rubrica versionada, travada na 1ª nota enviada da parte,
 * escrita pela mesma função para a gestão e para o líder ativo da vaga.
 *
 * O QUE ESTE GUARD AFIRMA (na captura vigente, recortada no trecho que decide)
 *   A. a tabela da rubrica: RLS, sem acesso direto de anon/authenticated, grant explícito a service_role, parte só
 *      video e fit, uma versão por vaga e parte, organização obrigatória;
 *   B. selection_evaluations aceita video e fit e guarda a versão da rubrica (coluna nula, sem default);
 *   C. auxiliares: a vigente é a maior versão da vaga piloto; o critério tem escala 1..3, âncoras e mínimo; o fit abre
 *      com nota de vídeo ENVIADA; a parte trava com nota ENVIADA daquela parte na vaga;
 *   D. save_selection_rubric: gestão ou líder ATIVO da vaga; recusa travada antes de gravar; vídeo de 3 a 5; âncora nos
 *      3 níveis; mínimo só no fit e de 1 a 3; versão = maior + 1; histórico;
 *   E. formulário: a trava da rubrica e do fit vem antes do registro de acesso, e vídeo e fit leem a rubrica;
 *   F. envio: a trava vem antes de gravar; com rubrica, só 1, 2 ou 3; no fit, abaixo do mínimo sem justificativa
 *      naquele critério é recusado; a nota grava a versão da rubrica;
 *   G. fila: vídeo e fit só com rubrica, e o fit só com o vídeo enviado;
 *   H. leitura da aba: as rubricas com vigente e trava, e o histórico inclui selection_rubric;
 *   I. tela do avaliador: a parte vai ao formulário e ao envio; nível sem pré-marcação; o mínimo do fit confere antes
 *      de enviar; textos nos 3 idiomas;
 *   J. aba: o editor grava pela save_selection_rubric com os itens normalizados;
 *   K. (guard 3119-E) a concessão e a extensão no histórico do grant decidem pela existência do vínculo ativo.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG_DIR = resolve(ROOT, 'supabase/migrations');
const escRe = (str) => str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const norm = (s) => maskLineComments(s).replace(/\s+/g, ' ');
const MIG = (() => {
  const f = readdirSync(MIG_DIR).filter((n) => /^\d{14}_3120_rubrica_e_nota_de_video_e_fit\.sql$/.test(n));
  assert.equal(f.length, 1, 'a migration da #3120 existe uma vez');
  return f[0];
})();
const SQL = norm(readFileSync(resolve(MIG_DIR, MIG), 'utf8'));
const cap = (n) => {
  const c = latestFunctionCapture(ROOT, n);
  assert.ok(c.file >= MIG, `${n}: a captura vigente (${c.file}) é anterior à da #3120`);
  return norm(c.block);
};
const ordem = (corpo, marcos, rotulo) => {
  let antes = -1;
  for (const m of marcos) {
    const i = typeof m === 'string' ? corpo.indexOf(m) : corpo.search(m);
    assert.ok(i > antes, `${rotulo}: fora de ordem ou ausente: ${String(m).slice(0, 90)}`);
    antes = i;
  }
};

test('A. a tabela da rubrica', () => {
  assert.match(SQL, /CREATE TABLE IF NOT EXISTS public\.selection_opening_rubrics \( id uuid PRIMARY KEY DEFAULT gen_random_uuid\(\), organization_id uuid NOT NULL, opportunity_id text NOT NULL REFERENCES public\.vep_opportunities\(opportunity_id\), part text NOT NULL CHECK \(part IN \('video', 'fit'\)\), version int NOT NULL CHECK \(version >= 1\), items jsonb NOT NULL CHECK \(jsonb_typeof\(items\) = 'array'\),[^;]* UNIQUE \(opportunity_id, part, version\) \);/);
  assert.match(SQL, /ALTER TABLE public\.selection_opening_rubrics ENABLE ROW LEVEL SECURITY; REVOKE ALL ON public\.selection_opening_rubrics FROM PUBLIC, anon, authenticated; GRANT SELECT, INSERT, UPDATE, DELETE ON public\.selection_opening_rubrics TO service_role;/);
});

test('B. selection_evaluations aceita video e fit e guarda a versão da rubrica', () => {
  const drop = SQL.indexOf('ALTER TABLE public.selection_evaluations DROP CONSTRAINT selection_evaluations_evaluation_type_check;');
  const add = SQL.indexOf("ALTER TABLE public.selection_evaluations ADD CONSTRAINT selection_evaluations_evaluation_type_check CHECK (evaluation_type IN ('objective', 'interview', 'leader_extra', 'video', 'fit'));");
  assert.ok(drop >= 0 && add > drop, 'o CHECK novo não substitui o antigo, ou perdeu um tipo');
  assert.match(SQL, /ALTER TABLE public\.selection_evaluations ADD COLUMN IF NOT EXISTS rubric_id uuid REFERENCES public\.selection_opening_rubrics\(id\);/);
});

test('C. auxiliares', () => {
  assert.match(cap('_rubrica_vigente_id'), /JOIN public\.vep_opportunities vo ON vo\.opportunity_id = sa\.vep_opportunity_id AND vo\.evaluation_track = 'line_pilot' JOIN public\.selection_opening_rubrics r ON r\.opportunity_id = vo\.opportunity_id AND r\.part = p_part WHERE sa\.id = p_application_id ORDER BY r\.version DESC LIMIT 1;/);
  assert.match(cap('_criterios_da_rubrica'), /'key', i->>'key', 'label', i->>'label', 'guide', i->>'question', 'weight', 1, 'max', 3, 'scale_min', 1, 'anchors', i->'anchors', 'min_level', i->'min_level'\) ORDER BY o\.n\) FROM public\.selection_opening_rubrics r, jsonb_array_elements\(r\.items\) WITH ORDINALITY AS o\(i, n\) WHERE r\.id = public\._rubrica_vigente_id\(p_application_id, p_part\)\)/);
  assert.match(cap('_fit_aberto'), /WHERE e\.application_id = p_application_id AND e\.evaluation_type = 'video' AND e\.submitted_at IS NOT NULL\);/);
  assert.match(cap('_rubrica_travada'), /WHERE sa\.vep_opportunity_id = p_opportunity_id AND e\.evaluation_type = p_part AND e\.submitted_at IS NOT NULL\);/);
  for (const f of ['_rubrica_vigente_id(uuid, text)', '_criterios_da_rubrica(uuid, text)', '_fit_aberto(uuid)', '_rubrica_travada(text, text)']) {
    assert.ok(SQL.includes(`REVOKE ALL ON FUNCTION public.${f} FROM PUBLIC, anon, authenticated;`), `${f} exposta ao cliente`);
  }
});

test('D. save_selection_rubric', () => {
  const c = cap('save_selection_rubric');
  assert.match(c, /IF NOT public\.can_by_member\(v_caller, 'manage_platform'\) AND NOT EXISTS \(SELECT 1 FROM public\.engagements e WHERE e\.person_id = v_caller_person AND e\.initiative_id = v_vo\.initiative_id AND e\.role = 'leader' AND e\.status = 'active'\) THEN RETURN jsonb_build_object\('error', 'Unauthorized'\); END IF;/);
  assert.match(c, /IF p_part = 'video' AND \(v_n < 3 OR v_n > 5\) THEN/);
  assert.match(c, /IF coalesce\(btrim\(v_item #>> '\{anchors,weak\}'\), ''\) = '' OR coalesce\(btrim\(v_item #>> '\{anchors,medium\}'\), ''\) = '' OR coalesce\(btrim\(v_item #>> '\{anchors,strong\}'\), ''\) = '' THEN v_motivos := v_motivos \|\|/);
  assert.match(c, /IF p_part <> 'fit' THEN v_motivos := v_motivos \|\| \(v_k \|\| ': mínimo só existe no fit'\); ELSIF jsonb_typeof\(v_item -> 'min_level'\) <> 'number' OR \(v_item ->> 'min_level'\) NOT IN \('1', '2', '3'\) THEN/);
  assert.match(c, /SELECT coalesce\(max\(r\.version\), 0\) \+ 1 INTO v_versao FROM public\.selection_opening_rubrics r WHERE r\.opportunity_id = p_opportunity_id AND r\.part = p_part;/);
  ordem(c, [
    "IF public._rubrica_travada(p_opportunity_id, p_part) THEN RETURN jsonb_build_object('error',",
    "IF cardinality(v_motivos) > 0 THEN RETURN jsonb_build_object('error', 'Rubrica recusada: '",
    'INSERT INTO public.selection_opening_rubrics',
    "VALUES (v_caller, 'selection_rubric.saved', 'selection_opening_rubric', v_id,",
  ], 'save: trava, recusa, grava, histórico');
  assert.match(SQL, /GRANT EXECUTE ON FUNCTION public\.save_selection_rubric\(text, text, jsonb\) TO authenticated;/);
  assert.match(SQL, /REVOKE ALL ON FUNCTION public\.save_selection_rubric\(text, text, jsonb\) FROM PUBLIC, anon;/);
});

const TRAVA = /IF p_evaluation_type IN \('video', 'fit'\) THEN (?:v_rubrica := public\._rubrica_vigente_id\(p_application_id, p_evaluation_type\); IF v_rubrica IS NULL|IF public\._rubrica_vigente_id\(p_application_id, p_evaluation_type\) IS NULL) THEN RAISE EXCEPTION 'A vaga desta candidatura ainda não tem rubrica de %'[^;]*; END IF; IF p_evaluation_type = 'fit' AND NOT public\._fit_aberto\(p_application_id\) THEN RAISE EXCEPTION/;

test('E. formulário: trava antes do registro de acesso; vídeo e fit leem a rubrica', () => {
  const c = cap('get_evaluation_form');
  ordem(c, [TRAVA, 'PERFORM public._log_application_pii_access('], 'formulário');
  assert.match(c, /WHEN 'video' THEN public\._criterios_da_rubrica\(p_application_id, 'video'\) WHEN 'fit' THEN public\._criterios_da_rubrica\(p_application_id, 'fit'\) ELSE '\[\]'::jsonb END;/);
  assert.match(c, /\|\| jsonb_build_object\('scale_min', c->'scale_min', 'anchors', c->'anchors', 'min_level', c->'min_level'\)/);
});

test('F. envio: trava antes de gravar, 3 níveis, mínimo do fit com justificativa, versão gravada', () => {
  const c = cap('submit_evaluation');
  ordem(c, [TRAVA, 'INSERT INTO public.selection_evaluations ('], 'envio');
  assert.match(c, /WHEN 'video' THEN public\._criterios_da_rubrica\(p_application_id, 'video'\) WHEN 'fit' THEN public\._criterios_da_rubrica\(p_application_id, 'fit'\) ELSE '\[\]'::jsonb END;/);
  assert.match(c, /IF v_rubrica IS NOT NULL THEN IF v_score NOT IN \(1, 2, 3\) THEN RAISE EXCEPTION [^;]*; END IF; v_minimo := \(v_criterion ->> 'min_level'\)::numeric; IF p_evaluation_type = 'fit' AND v_minimo IS NOT NULL AND v_score < v_minimo AND coalesce\(btrim\(p_criterion_notes ->> v_key\), ''\) = '' THEN RAISE EXCEPTION/);
  assert.match(c, /scores, weighted_subtotal, notes, criterion_notes, submitted_at, rubric_id \) VALUES \( p_application_id, v_caller\.id, p_evaluation_type, p_scores, ROUND\(v_weighted_sum, 2\), p_notes, COALESCE\(p_criterion_notes, '\{\}'::jsonb\), now\(\), v_rubrica \) ON CONFLICT \(application_id, evaluator_id, evaluation_type\) DO UPDATE SET rubric_id = EXCLUDED\.rubric_id,/);
});

test('G. fila: vídeo e fit só com rubrica; o fit só com vídeo enviado', () => {
  assert.match(cap('get_my_pending_evaluations'), /AND \(a\.part = 'objective' OR \(a\.part IN \('video', 'fit'\) AND public\._rubrica_vigente_id\(sa\.id, a\.part\) IS NOT NULL AND \(a\.part <> 'fit' OR public\._fit_aberto\(sa\.id\)\)\)\) AND sa\.status <> ALL \(v_terminal\)/);
});

test('H. leitura da aba: rubricas com vigente e trava; histórico com selection_rubric', () => {
  const c = cap('get_selection_evaluators_admin');
  assert.match(c, /'is_current', r\.version = \(SELECT max\(r2\.version\) FROM public\.selection_opening_rubrics r2 WHERE r2\.opportunity_id = r\.opportunity_id AND r2\.part = r\.part\), 'locked', public\._rubrica_travada\(r\.opportunity_id, r\.part\)\)/);
  assert.match(c, /WHERE l\.action LIKE 'selection\\_evaluator\.%' OR l\.action LIKE 'selection\\_rubric\.%'/);
});

const ME = maskJsComments(readFileSync(resolve(ROOT, 'src/pages/minhas-avaliacoes.astro'), 'utf8'));
const ISLAND = maskJsComments(readFileSync(resolve(ROOT, 'src/components/selection/SelectionEvaluatorsTab.tsx'), 'utf8'));

test('I. tela do avaliador: parte, níveis sem pré-marcação, mínimo do fit, textos', () => {
  assert.match(ME, /data-eval-part="\$\{esc\(p\.part \|\| 'objective'\)\}"/);
  assert.match(ME, /openForm\(btn\.dataset\.evalApp as string, btn\.dataset\.evalPart \|\| 'objective'\)/);
  assert.match(ME, /p_application_id: applicationId,\s*p_evaluation_type: part,\s*\}\);/, 'o formulário não pede a parte');
  assert.match(ME, /p_evaluation_type: part,\s*p_scores: scores,/, 'o envio não manda a parte');
  assert.match(ME, /if \(c\.anchors\) return rubricItem\(c, locked\);/);
  assert.match(ME, /\$\{Number\(c\.your_score\) === v \? 'checked' : ''\}/, 'o nível vem pré-marcado');
  const sub = ME.slice(ME.indexOf('async function submitForm('));
  ordem(sub, [
    "if (!r) { toast(I.pickLevel",
    /if \(scores\[c\.key\] < Number\(c\.min_level\) && !criterionNotes\[c\.key\]\) \{\s*toast\(/,
    "sb.rpc('submit_evaluation'",
  ], 'envio na tela');
  const keys = ['part.objective', 'part.video', 'part.fit', 'level.weak', 'level.medium', 'level.strong', 'minLevelHint', 'justificationRequired', 'pickLevel', 'rubricVersion'];
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const d = readFileSync(resolve(ROOT, `src/i18n/${lang}.ts`), 'utf8');
    for (const k of keys) assert.match(d, new RegExp(`'myEvals\\.${escRe(k)}': '[^']+',`), `${lang}: myEvals.${k}`);
  }
});

test('J. aba: o editor grava pela save_selection_rubric', () => {
  assert.match(ISLAND, /run\('save_selection_rubric', \{ p_opportunity_id: rubOpp, p_part: rubPart, p_items: items \}/);
  assert.match(ISLAND, /min_level: rubPart === 'fit' && it\.min_level \? Number\(it\.min_level\) : null,/);
  assert.match(ISLAND, /disabled=\{busy \|\| !rubOpp \|\| !!currentRubric\?\.locked\} onClick=\{startEdit\}/, 'a rubrica travada voltou a abrir o editor');
});
