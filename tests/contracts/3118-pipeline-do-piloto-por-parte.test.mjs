/**
 * #3118 (ADR-0134 §3): a coluna Pipeline do painel de seleção mostra a candidatura piloto por parte.
 *
 * Na avaliação geral, a coluna mostra "x/2" avaliadores distintos da objetiva. A candidatura piloto é avaliada em três
 * partes, cada uma com o seu esperado (objetiva 2, vídeo 2, fit 1), e cada parte passa por atribuição, calibragem do
 * avaliador para a vaga e a parte, e envio. O "x/2" não dizia nada disso.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. (banco, captura vigente de get_selection_dashboard) a linha leva pilot_parts SÓ para a gestão e SÓ na linha
 *      piloto, com as três partes e o esperado de cada uma; atribuído conta atribuição ativa; calibrado conta a
 *      atribuição ativa cujo avaliador tem a calibragem DAQUELA vaga e DAQUELA parte; enviado conta avaliador distinto
 *      com envio daquela parte; vencido é atribuição ativa com prazo passado e sem envio daquele avaliador;
 *   B. o resto da função é byte a byte a captura anterior (20261107121211): a migration só acrescenta pilot_parts;
 *   C. (tela) na linha piloto, a coluna Pipeline troca o x/2 e a entrevista geral pelas três partes; o estado de cada
 *      parte sai dos números (done, ready, assigned, empty); a linha do tempo da ficha faz o mesmo;
 *   D. o chip da régua líder só aparece em candidatura com role_applied = 'leader';
 *   E. os rótulos existem nos 3 idiomas e no SEL_I18N.
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
  const f = readdirSync(MIG_DIR).filter((n) => /^\d{14}_3118_pipeline_do_piloto_por_parte\.sql$/.test(n));
  assert.equal(f.length, 1, 'a migration da #3118 existe uma vez');
  return f[0];
})();
const CAP = latestFunctionCapture(ROOT, 'get_selection_dashboard');
const BODY = norm(CAP.block);

function blockOf(file, fn) {
  const sql = readFileSync(resolve(MIG_DIR, file), 'utf8');
  const start = sql.indexOf(`CREATE OR REPLACE FUNCTION public.${fn}(`);
  assert.ok(start >= 0, `${fn} em ${file}`);
  const end = sql.indexOf('$function$;', start);
  return sql.slice(start, end + '$function$;'.length);
}

// O recorte que decide: o jsonb_build_object('pilot_parts', ...) até o fechamento do CASE.
const PARTS = (() => {
  const i = BODY.indexOf("|| jsonb_build_object('pilot_parts',");
  assert.ok(i >= 0, 'a linha leva pilot_parts');
  const j = BODY.indexOf("|| jsonb_build_object('divergence_types',", i);
  assert.ok(j > i, 'pilot_parts vem antes de divergence_types');
  return BODY.slice(i, j);
})();

test('A0. a captura vigente de get_selection_dashboard é a da #3118', () => {
  assert.equal(CAP.file, MIG);
});

test('A1. só a gestão e só na linha piloto; três partes com o esperado da ADR', () => {
  assert.match(PARTS, /^\|\| jsonb_build_object\('pilot_parts', CASE WHEN v_ve_piloto AND NOT public\._na_avaliacao_geral\(a\.id\) THEN \( SELECT jsonb_object_agg\(p\.part, jsonb_build_object\(/);
  assert.match(PARTS, /FROM \(VALUES \('objective', 2\), \('video', 2\), \('fit', 1\)\) AS p\(part, expected\)\) END\) $/);
  assert.match(PARTS, /'expected', p\.expected,/);
});

test('A2. atribuído: atribuição ativa daquela candidatura e parte', () => {
  assert.match(PARTS, /'assigned', \(SELECT count\(\*\) FROM public\.selection_evaluation_assignments sea WHERE sea\.application_id = a\.id AND sea\.part = p\.part AND sea\.withdrawn_at IS NULL\),/);
});

test('A3. calibrado: atribuição ativa cujo avaliador tem a calibragem da vaga e da parte', () => {
  assert.match(PARTS, /'calibrated', \(SELECT count\(\*\) FROM public\.selection_evaluation_assignments sea JOIN public\.selection_evaluator_calibrations cal ON cal\.member_id = sea\.evaluator_member_id AND cal\.opportunity_id = a\.vep_opportunity_id AND cal\.part = sea\.part WHERE sea\.application_id = a\.id AND sea\.part = p\.part AND sea\.withdrawn_at IS NULL\),/);
});

test('A4. enviado: avaliador distinto com envio daquela parte', () => {
  assert.match(PARTS, /'submitted', \(SELECT count\(DISTINCT se\.evaluator_id\) FROM public\.selection_evaluations se WHERE se\.application_id = a\.id AND se\.evaluation_type = p\.part AND se\.submitted_at IS NOT NULL\),/);
});

test('A5. vencido: atribuição ativa com prazo passado e sem envio daquele avaliador', () => {
  assert.match(PARTS, /'overdue', \(SELECT count\(\*\) FROM public\.selection_evaluation_assignments sea WHERE sea\.application_id = a\.id AND sea\.part = p\.part AND sea\.withdrawn_at IS NULL AND sea\.due_at < now\(\) AND NOT EXISTS \(SELECT 1 FROM public\.selection_evaluations se WHERE se\.application_id = a\.id AND se\.evaluation_type = p\.part AND se\.evaluator_id = sea\.evaluator_member_id AND se\.submitted_at IS NOT NULL\)\)\)\)/);
});

test('B. fora de pilot_parts, a função é a captura anterior byte a byte', () => {
  const prev = blockOf('20261107121211_alerta_de_divergencia_do_piloto.sql', 'get_selection_dashboard');
  const now = blockOf(MIG, 'get_selection_dashboard');
  const start = now.indexOf('        -- Pipeline por trilha (ADR-0134 §3)');
  const end = now.indexOf('        -- #2393 (emenda de 06/11/2026 à ADR-0134 §4): as partes da candidatura piloto com alerta');
  assert.ok(start > 0 && end > start, 'o bloco inserido está delimitado');
  assert.equal(now.slice(0, start) + now.slice(end), prev);
});

const PAGE = maskJsComments(readFileSync(resolve(ROOT, 'src/pages/admin/selection.astro'), 'utf8'));
function fnBody(name) {
  const i = PAGE.indexOf(`function ${name}(`);
  assert.ok(i >= 0, `function ${name}`);
  const next = PAGE.indexOf('\n  function ', i + 10);
  return PAGE.slice(i, next > 0 ? next : undefined);
}

test('C1. coluna Pipeline: na linha piloto, as três partes no lugar do x/2 e da entrevista geral', () => {
  const b = fnBody('pipelineBadges');
  const m = /if \(isPilotRow\(r\)\) return `([^`]*)`;/.exec(b);
  assert.ok(m, 'pipelineBadges tem o desvio da linha piloto');
  assert.match(m[1], /\$\{pilotPartsBadges\(r\)\}/, 'o desvio piloto mostra as partes');
  assert.doesNotMatch(m[1], /peerBadge|interviewBadge/, 'o desvio piloto não mostra o x/2 nem a entrevista geral');
  assert.ok(b.indexOf('if (isPilotRow(r)) return') < b.lastIndexOf('${peerBadge}'), 'o desvio vem antes do retorno geral');
});

test('C2. estado da parte sai dos números', () => {
  const b = fnBody('pilotPartState');
  assert.match(b, /if \(p\.e > 0 && p\.s >= p\.e\) return 'done';\s*if \(p\.e > 0 && p\.a >= p\.e && p\.c >= p\.e\) return 'ready';\s*if \(p\.a > 0\) return 'assigned';\s*return 'empty';/);
  const r = fnBody('pilotPart');
  assert.match(r, /const p = r\?\.pilot_parts\?\.\[part\];/);
  assert.match(fnBody('pilotPartsBadges'), /return PILOT_PARTS\.map\(\(part\) => \{/);
  assert.match(PAGE, /const PILOT_PARTS = \['objective', 'video', 'fit'\] as const;/);
});

test('C3. linha do tempo da ficha: na linha piloto, as partes no lugar da par-revisão e da entrevista', () => {
  const b = fnBody('pipelineTimeline');
  assert.match(b, /if \(isPilotRow\(r\)\) \{\s*const partStages = PILOT_PARTS\.map\(/);
  assert.match(b, /const keep = stages\.filter\(\(s\) => s\.label !== 'Par-revisão' && s\.label !== 'Entrevista'\);\s*stages\.splice\(0, stages\.length, \.\.\.keep\.slice\(0, 3\), \.\.\.partStages, \.\.\.keep\.slice\(3\)\);/);
});

test('D. chip da régua líder só em candidatura de líder', () => {
  const calls = PAGE.match(/[^\n]*leaderExtraChip\(r\.[^\n]*/g) || [];
  assert.equal(calls.length, 1, 'uma chamada de leaderExtraChip por linha');
  assert.match(calls[0], /\$\{r\.role_applied === 'leader' \? leaderExtraChip\(r\.leader_extra_pert_score, \(currentCycle as any\)\?\.leader_extra_cutoff\) : ''\}/);
});

test('E. rótulos nos 3 idiomas e no SEL_I18N', () => {
  const keys = ['pilotPartObjective', 'pilotPartVideo', 'pilotPartFit', 'pilotPartShortObjective', 'pilotPartShortVideo',
    'pilotPartShortFit', 'pilotPartDetail', 'pilotPartOverdue', 'pilotPartsMissing'];
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const d = readFileSync(resolve(ROOT, `src/i18n/${lang}.ts`), 'utf8');
    for (const k of keys) assert.match(d, new RegExp(`'admin\\.selection\\.${k}': '[^']+',`), `${lang}: ${k}`);
  }
  for (const k of keys) assert.match(PAGE, new RegExp(`  ${k}: t\\('admin\\.selection\\.${k}', lang\\),`), `SEL_I18N: ${k}`);
});
