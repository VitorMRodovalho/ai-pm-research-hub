// #1256 (Wave 2) — self-service leave: a researcher in the wrong tribe can leave (reusing
// withdraw_from_initiative) and the picker reopens. This wave extends get_my_tribe_request_context
// (ADDITIVE) to expose current_tribe_id + current_tribe_initiative_id on the has_tribe case, sourced
// from the caller's ACTIVE volunteer engagement (the initiative withdraw_from_initiative requires).
// See docs/specs/SPEC_TRIBE_SWITCH_AND_LEADER_REVIEW.md §Wave 2.
// Static test over the migration + the FE island; the body-drift gate (Phase C) covers live drift.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIG = join(
  __dirname,
  '../../supabase/migrations/20260805000393_1256_leave_tribe_self_service_context.sql',
);
const WITHDRAW_MIG = join(
  __dirname,
  '../../supabase/migrations/20260805000394_1256_fix_withdraw_from_initiative_valid_status.sql',
);
const TSX = join(__dirname, '../../src/components/tribe/TribeRequestBlock.tsx');
const sql = readFileSync(MIG, 'utf8');
const withdrawSql = readFileSync(WITHDRAW_MIG, 'utf8');
const tsx = readFileSync(TSX, 'utf8');

test('#1256: migration redefine get_my_tribe_request_context', () => {
  assert.match(
    sql,
    /CREATE OR REPLACE FUNCTION public\.get_my_tribe_request_context\(\)/,
    'a migration deve redefinir get_my_tribe_request_context',
  );
});

test('#1256: extensão é ADITIVA (mantém as chaves de #1255 intactas)', () => {
  // pending com invitation_id (Wave 1) permanece
  assert.match(sql, /SELECT ii\.id AS invitation_id,/, 'o pending deve continuar expondo invitation_id');
  assert.match(sql, /'eligible', v_eligible/, 'chave eligible intacta');
  assert.match(sql, /'ineligible_reason', v_reason/, 'chave ineligible_reason intacta');
  assert.match(sql, /'current_tribe_title', v_current_tribe_title/, 'chave current_tribe_title intacta');
});

test('#1256: RETURN expõe current_tribe_id + current_tribe_initiative_id', () => {
  assert.match(sql, /'current_tribe_id', v_current_tribe_id/, 'expõe current_tribe_id');
  assert.match(
    sql,
    /'current_tribe_initiative_id', v_current_tribe_initiative_id/,
    'expõe current_tribe_initiative_id',
  );
});

test('#1256: initiative_id vem do engagement volunteer ATIVO (alvo do withdraw)', () => {
  // o SELECT que preenche o initiative_id junta engagements ativos do próprio person
  assert.match(
    sql,
    /JOIN public\.engagements e ON e\.initiative_id = i\.id\s*\n\s*AND e\.person_id = v_person_id AND e\.kind = 'volunteer' AND e\.status = 'active'/,
    'o initiative_id deve sair da junção com o engagement volunteer ativo',
  );
});

test('#1256: legacy-only (sem engagement ativo) mantém título mas initiative_id NULL', () => {
  // fallback preenche só o título quando não há engagement ativo
  assert.match(
    sql,
    /IF v_current_tribe_title IS NULL THEN[\s\S]*?SELECT i\.title, i\.legacy_tribe_id INTO v_current_tribe_title, v_current_tribe_id/,
    'fallback legacy-only preenche o título sem tocar no initiative_id (fica NULL)',
  );
});

// --- withdraw_from_initiative latent-bug fix (Wave 2 depends on it working) ---

test('#1256: withdraw_from_initiative usa status TERMINAL VÁLIDO offboarded (não o revoked inválido)', () => {
  assert.match(
    withdrawSql,
    /CREATE OR REPLACE FUNCTION public\.withdraw_from_initiative\(p_initiative_id uuid, p_reason text\)/,
    'a migration deve redefinir withdraw_from_initiative',
  );
  assert.match(
    withdrawSql,
    /SET status = 'offboarded',/,
    "deve setar status='offboarded' (valor aceito por engagements_status_check)",
  );
  // 'revoked' não existe no CHECK; a versão antiga quebrava sempre. Não pode reaparecer.
  assert.doesNotMatch(withdrawSql, /status = 'revoked'/, "não pode voltar ao status 'revoked' inválido");
});

test('#1256: o safeguard único-do-kind (remaining_of_kind) é preservado no withdraw corrigido', () => {
  assert.match(withdrawSql, /'remaining_of_kind', v_active_count_same_kind/, 'mantém o bloqueio de único voluntário');
});

// --- FE island (TribeRequestBlock.tsx) ---

test('#1256: o FE chama withdraw_from_initiative com initiative_id + motivo', () => {
  assert.match(tsx, /sb\.rpc\('withdraw_from_initiative'/, 'usa withdraw_from_initiative');
  assert.match(tsx, /p_initiative_id: initiativeId/, 'passa o initiative_id do contexto');
  assert.match(tsx, /p_reason: leaveReason\.trim\(\)/, 'passa o motivo digitado');
});

test('#1256: o FE gate o botão em motivo >= 10 (espelha o guard do withdraw)', () => {
  assert.match(tsx, /const LEAVE_MIN_REASON = 10;/, 'constante espelha o guard >= 10 do withdraw');
  assert.match(
    tsx,
    /disabled=\{leaving \|\| leaveReason\.trim\(\)\.length < LEAVE_MIN_REASON\}/,
    'o botão só habilita com motivo >= 10',
  );
});

test('#1256: safeguard único-voluntário/líder vira mensagem de rota ao GP, não toast genérico', () => {
  assert.match(
    tsx,
    /typeof data\.remaining_of_kind === 'number'[\s\S]*?setLeaveBlocked\(copy\.leaveBlockedSoleVolunteer\)/,
    'o retorno com remaining_of_kind deve exibir a mensagem de rota ao GP',
  );
});

test('#1256: a ação de saída só aparece quando há initiative_id (senão fallback legacy)', () => {
  assert.match(tsx, /const canLeave = !!ctx\.current_tribe_initiative_id;/, 'canLeave depende do initiative_id');
});

test('#1256: chaves i18n de leave existem nas 3 dicts', () => {
  for (const key of ['leaveTribe', 'leaveConfirm', 'leaveBlockedSoleVolunteer', 'toastLeft', 'leaveReasonLabel']) {
    const count = (tsx.match(new RegExp(`\\b${key}:`, 'g')) || []).length;
    assert.ok(count >= 3, `a chave ${key} deve existir nas 3 dicts (achou ${count})`);
  }
});
