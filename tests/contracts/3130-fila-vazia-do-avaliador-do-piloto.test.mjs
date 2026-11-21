/**
 * #3130: get_my_pending_evaluations, fora do comitê do ciclo, devolve fila vazia a quem tem atribuição ATIVA no piloto
 * da linha (ADR-0134) e nenhum item aberto agora, em vez de recusar. O estado é normal no piloto: o fit espera a 1ª
 * nota de vídeo enviada e o vídeo espera a rubrica da vaga (#3120). Sem atribuição ativa, a recusa continua.
 *
 * O QUE ESTE GUARD AFIRMA (na captura vigente, recortada no bloco do portão do comitê)
 *   A. a recusa só acontece com a fila do piloto vazia E sem atribuição ativa (withdrawn_at nulo) de quem chama;
 *   B. quem passa sem item recebe '[]', não nulo (a contagem e a tela leem um array);
 *   C. a migration recria só essa função, sem tocar grant (CREATE OR REPLACE mantém os do catálogo);
 *   D. a tela trata a fila vazia como "nada pendente" e só a recusa como "não está no comitê".
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
  const f = readdirSync(MIG_DIR).filter((n) => /^\d{14}_3130_fila_vazia_do_avaliador_do_piloto\.sql$/.test(n));
  assert.equal(f.length, 1, 'a migration da #3130 existe uma vez');
  return f[0];
})();
const SQL = norm(readFileSync(resolve(MIG_DIR, MIG), 'utf8'));
const CAP = (() => {
  const c = latestFunctionCapture(ROOT, 'get_my_pending_evaluations');
  assert.ok(c.file >= MIG, `a captura vigente (${c.file}) é anterior à da #3130`);
  return norm(c.block);
})();
const PORTAO = (() => {
  const i = CAP.indexOf("AND NOT public.can_by_member(v_caller_member_id, 'manage_member') THEN");
  const j = CAP.indexOf('-- Pending = EVAL', i) >= 0 ? CAP.indexOf('-- Pending = EVAL', i) : CAP.indexOf("SELECT jsonb_agg(jsonb_build_object( 'application_id', sa.id, 'applicant_name', sa.applicant_name,", i);
  assert.ok(i >= 0 && j > i, 'o bloco do portão do comitê não foi encontrado');
  return CAP.slice(i, j);
})();

test('A. a recusa exige fila do piloto vazia E nenhuma atribuição ativa de quem chama', () => {
  assert.match(PORTAO, /IF v_piloto IS NULL AND NOT EXISTS \( SELECT 1 FROM public\.selection_evaluation_assignments a WHERE a\.evaluator_member_id = v_caller_member_id AND a\.withdrawn_at IS NULL\) THEN RAISE EXCEPTION 'Unauthorized: caller is not on this cycle committee' USING ERRCODE = 'insufficient_privilege'; END IF;/);
});

test('B. quem passa sem item recebe array vazio, antes do RETURN que o lê', () => {
  assert.match(PORTAO, /END IF; v_piloto := COALESCE\(v_piloto, '\[\]'::jsonb\); RETURN jsonb_build_object\( 'cycle_code', v_cycle\.cycle_code, 'cycle_phase', v_cycle\.phase, 'pending', v_piloto, 'pending_count', jsonb_array_length\(v_piloto\), 'completed_count', 0, 'total_count', jsonb_array_length\(v_piloto\), 'progress_pct', 0\);/);
});

test('C. a migration recria só get_my_pending_evaluations e não mexe em grant', () => {
  assert.equal((SQL.match(/CREATE OR REPLACE FUNCTION/g) || []).length, 1);
  assert.match(SQL, /CREATE OR REPLACE FUNCTION public\.get_my_pending_evaluations\(\) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER/);
  assert.doesNotMatch(SQL, /\b(GRANT|REVOKE|ALTER|DROP)\b/);
});

test('D. a tela: fila vazia é "nada pendente"; só a recusa é "não está no comitê"', () => {
  const ME = maskJsComments(readFileSync(resolve(ROOT, 'src/pages/minhas-avaliacoes.astro'), 'utf8'));
  assert.match(ME, /if \(String\(error\.code\) === '42501' \|\| \/not on this cycle committee\/i\.test\(error\.message \|\| ''\)\) \{\s*showDenied\(I\.notCommittee\);/);
  assert.match(ME, /if \(pending\.length === 0\) \{\s*host\.innerHTML = `[^`]*\$\{esc\(I\.noPending\)\}/);
});
