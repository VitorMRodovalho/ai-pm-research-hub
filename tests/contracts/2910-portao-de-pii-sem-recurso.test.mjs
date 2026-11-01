/**
 * Portao de dado pessoal chamado sem recurso.
 *
 * Duas definicoes sao afirmadas, cada uma no bloco que decide:
 *
 *   1. can(): o vinculo legado de tribo, sem recurso, deixa de valer para view_pii e manage_member. A
 *      condicao `p_action NOT IN (...)` tem de estar DENTRO do mesmo disjunto que contem
 *      `p_resource_id IS NULL AND ae.legacy_tribe_id IS NOT NULL`, e esse disjunto tem de continuar
 *      dentro do ramo `ekp.scope = 'initiative'`. As outras duas formas de casar (UUID da iniciativa e
 *      tribo por tipo de recurso) continuam presentes, para a mudanca nao virar remocao do ramo inteiro.
 *
 *   2. capture_vep_baseline(): o papel de comite ausente (NULL) nao autoriza. O COALESCE tem de estar
 *      dentro do IN que decide, no IF que levanta a excecao, e esse IF vem antes da primeira escrita.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados.
 * Camada VIVA nao e afirmada aqui: a prova da camada viva e a execucao como a pessoa, feita fora do teste.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();

const can = maskLineComments(latestFunctionCapture(ROOT, 'can').body);
const capture = maskLineComments(latestFunctionCapture(ROOT, 'capture_vep_baseline').body);

/** O disjunto do ramo de iniciativa que casa por vinculo legado, sem recurso, ate o fecha-parenteses dele. */
function legacyDisjunct(body) {
  const at = body.search(/OR \(p_resource_id IS NULL AND ae\.legacy_tribe_id IS NOT NULL/);
  assert.ok(at !== -1, 'o disjunto do vinculo legado sem recurso existe em can()');
  let depth = 0;
  for (let i = at + 3; i < body.length; i++) {
    if (body[i] === '(') depth++;
    if (body[i] === ')') {
      depth--;
      if (depth === 0) return body.slice(at, i + 1);
    }
  }
  assert.fail('o disjunto do vinculo legado nao fecha');
}

/** O bloco `ekp.scope = 'initiative' AND ... ` ate o fim da funcao. */
function initiativeBlock(body) {
  const at = body.indexOf("ekp.scope = 'initiative'");
  assert.ok(at !== -1, "can() tem o ramo ekp.scope = 'initiative'");
  return body.slice(at);
}

/** O IF que decide o portao de capture_vep_baseline, do IF NOT ( ate o RAISE EXCEPTION dele. */
function captureGate(body) {
  const m = body.match(/IF NOT \([\s\S]*?\) THEN\s+RAISE EXCEPTION 'Forbidden[^']*';/);
  assert.ok(m, 'capture_vep_baseline tem um IF NOT (...) THEN RAISE EXCEPTION Forbidden');
  return m;
}

test('A1. can(): o vinculo legado sem recurso exclui view_pii e manage_member, no mesmo disjunto', () => {
  assert.match(
    legacyDisjunct(can),
    /^OR \(p_resource_id IS NULL AND ae\.legacy_tribe_id IS NOT NULL\s+AND p_action NOT IN \('view_pii', 'manage_member'\)\)$/,
    'a exclusao por acao esta dentro do disjunto que casa sem recurso',
  );
});

test('A2. can(): o disjunto de vinculo legado continua DENTRO do ramo de iniciativa', () => {
  const block = initiativeBlock(can);
  assert.match(
    block,
    /ekp\.scope = 'initiative'\s+AND ae\.initiative_id IS NOT NULL\s+AND \(\s+ae\.initiative_id = p_resource_id\s+OR \(p_resource_id IS NULL AND ae\.legacy_tribe_id IS NOT NULL\s+AND p_action NOT IN \('view_pii', 'manage_member'\)\)/,
    'o disjunto vem logo depois do casamento por UUID, dentro do mesmo AND ( ... )',
  );
});

test('A3. can(): as outras formas de casar continuam, a mudanca nao remove o ramo inteiro', () => {
  const block = initiativeBlock(can);
  assert.match(block, /ae\.initiative_id = p_resource_id/, 'casamento por UUID da iniciativa');
  assert.match(
    block,
    /OR \(p_resource_type = 'tribe' AND ae\.legacy_tribe_id = \(p_resource_id::text\)::integer\)/,
    'casamento por tribo passada como tipo de recurso',
  );
  assert.match(can, /ekp\.scope IN \('organization', 'global'\)/, 'escopo de organizacao continua concedendo');
});

test('B1. capture_vep_baseline: o papel ausente nao autoriza (COALESCE dentro do IN que decide)', () => {
  assert.match(
    captureGate(capture)[0],
    /^IF NOT \(\s+public\.can_by_member\(v_caller_id, 'view_internal_analytics'\)\s+OR \(COALESCE\(public\.selection_committee_role_for\(v_caller_id\), ''\) IN \('evaluator', 'lead'\)\s+AND public\.can_by_member\(v_caller_id, 'view_pii'\)\)\s+\) THEN\s+RAISE EXCEPTION 'Forbidden/,
    'o COALESCE esta dentro do IN, dentro do IF NOT que levanta Forbidden',
  );
});

test('B2. capture_vep_baseline: o portao vem antes da primeira escrita', () => {
  const gate = captureGate(capture);
  const write = capture.search(/\bINSERT INTO public\.vep_reconciliation_baselines\b/);
  assert.ok(write !== -1, 'capture_vep_baseline ainda grava em vep_reconciliation_baselines');
  assert.ok(gate.index < write, 'o IF do portao esta antes do INSERT');
});
