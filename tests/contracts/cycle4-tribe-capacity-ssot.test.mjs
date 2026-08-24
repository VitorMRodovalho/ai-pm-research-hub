/**
 * Virada C3→C4 — capacidade de tribo como SSOT (decisão owner 2026-07-04).
 *
 * Antes da mig 335, três superfícies davam três respostas para "tribo cheia":
 * select_tribe e admin_force_tribe_selection hardcodavam 6 (migs 185/20260425143237)
 * e o fluxo híbrido review_tribe_request não checava capacidade nenhuma (SPEC §4.5
 * deferred). A mig 335 cria tribe_capacity_limit() lendo
 * platform_settings.max_researchers_per_tribe (fallback 10) e as três superfícies
 * passam a consumir o helper (Pattern 47).
 *
 * Static source-contract sobre a migration (offline).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();

const MIG = readFileSync(
  fileURLToPath(new URL('../../supabase/migrations/20260805000335_cycle4_tribe_capacity_ssot.sql', import.meta.url)),
  'utf8',
);

test('cap-ssot: a mig 335 ENTREGOU o helper lendo platform_settings com fallback 10', () => {
  assert.match(MIG, /create or replace function public\.tribe_capacity_limit\(\)/);
  assert.match(MIG, /from public\.platform_settings where key = 'max_researchers_per_tribe'/);
  assert.match(MIG, /coalesce\(\s*\(select \(value #>> '\{\}'\)::int/);
  // #1950: a mensagem anterior dizia "fallback = 10 (o valor vivo da setting)". As DUAS metades
  // envelheceram — o fallback vigente é 8 e a setting vale 8 — e o guard passava verde afirmando
  // dois números que não existiam. Fixar aqui é legítimo: a pergunta é o que a 335 ENTREGOU, e
  // migration é história imutável. O presente é o teste seguinte.
  assert.match(MIG, /,\s*10\s*\)/, 'a 335 entregou fallback 10');
  assert.match(MIG, /revoke all on function public\.tribe_capacity_limit\(\) from public, anon/);
});

test('cap-ssot VIGENTE: o helper lê max_members_per_tribe com fallback 8 (= líder + 7)', () => {
  // #1932: afirmar invariante CORRENTE lendo arquivo fixado é o defeito que aquela issue cataloga.
  // Este par (cycle4-tribe-capacity-ssot | tribe_capacity_limit) era a LINHA 77 da linha de base,
  // e a consequência apareceu ao usar: o guard acima passava verde dizendo "fallback 10" enquanto
  // a produção rodava 7. Aqui a fonte é a captura mais nova, não um caminho fixado.
  const cap = latestFunctionCapture(ROOT, 'tribe_capacity_limit');
  assert.match(cap.block, /where key = 'max_members_per_tribe'/,
    'a chave vigente descreve INTEGRANTES: o limite conta o líder (#1950)');
  assert.doesNotMatch(cap.block, /max_researchers_per_tribe/,
    'o nome antigo descrevia 8 pesquisadores, que nunca foi o que o gate aplicou');
  assert.match(cap.block, /coalesce\([\s\S]*?,\s*8\s*\)/,
    'fallback 8 = 1 líder + 7 pesquisadores; 7 era o valor ANTERIOR da setting, preso no corpo');
});

test('cap-ssot: as três superfícies inicializam v_max_slots pelo helper (zero literais)', () => {
  const inits = MIG.match(/v_max_slots\s+integer\s*:=\s*public\.tribe_capacity_limit\(\);/gi) ?? [];
  assert.equal(inits.length, 3, 'select_tribe + admin_force_tribe_selection + review_tribe_request');
  assert.doesNotMatch(MIG, /v_max_slots\s+integer\s*:=\s*6/i, 'o literal 6 morreu');
});

test('cap-ssot: review_tribe_request ganha o cap, só no approve, antes do write', () => {
  const capBlock = MIG.indexOf("IF p_decision = 'approve' THEN\n    SELECT count(*) INTO v_slot_count");
  const updateBlock = MIG.indexOf('UPDATE public.initiative_invitations');
  assert.ok(capBlock > -1, 'bloco de capacidade existe');
  assert.ok(capBlock < updateBlock, 'capacidade é checada ANTES de gravar a decisão');
  // semântica espelha count_tribe_slots(): membros ativos na tribo, papéis sem vaga excluídos
  assert.match(MIG, /m\.tribe_id = v_initiative\.legacy_tribe_id/);
  assert.match(MIG, /operational_role NOT IN \('sponsor', 'chapter_liaison', 'guest', 'none'\)/);
  assert.match(MIG, /Tribo lotada \(%\/%\)/);
});

test('cap-ssot: corpos legados preservados (gates e semântica de contagem intactos)', () => {
  // select_tribe: term gate + deadline bypass + tribe_selections count seguem lá
  assert.match(MIG, /member_is_pre_onboarding\(v_person_id, v_member_status\)/);
  assert.match(MIG, /can_by_member\(v_member_id, 'manage_platform'::text\)/);
  assert.match(MIG, /FROM tribe_selections\s+WHERE tribe_id = p_tribe_id\s+AND member_id IS DISTINCT FROM v_member_id/);
  // admin_force: gate manage_member preservado
  assert.match(MIG, /can_by_member\(v_caller_id, 'manage_member'\)/);
  // review: autoridade líder-desta-tribo OU GP preservada
  assert.match(MIG, /apenas o líder desta tribo ou o GP podem revisar/);
});
