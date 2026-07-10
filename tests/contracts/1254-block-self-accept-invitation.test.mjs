// #1254 (Wave 0) — respond_to_initiative_invitation NÃO pode deixar um pedido self-service
// (invitee == inviter, criado por request_tribe_assignment) ser auto-aceito: isso criaria o
// engagement pulando a revisão do líder (o núcleo do modelo híbrido). Ver
// docs/specs/SPEC_TRIBE_SWITCH_AND_LEADER_REVIEW.md §Wave 0.
// Teste estático sobre a migration que aplicou o fix; o gate de body-drift (Phase C) cobre
// divergência live-vs-migration em runtime.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIG = join(
  __dirname,
  '../../supabase/migrations/20260805000391_1254_wave0_block_self_accept_invitation.sql',
);
const sql = readFileSync(MIG, 'utf8');

test('#1254: migration redefine respond_to_initiative_invitation', () => {
  assert.match(
    sql,
    /CREATE OR REPLACE FUNCTION public\.respond_to_initiative_invitation\(/,
    'a migration deve redefinir respond_to_initiative_invitation',
  );
});

test('#1254: bloqueia accept quando invitee == inviter (self-request)', () => {
  assert.match(
    sql,
    /p_response = 'accept'\s+AND\s+v_invitation\.invitee_member_id = v_invitation\.inviter_member_id/,
    'o guard deve bloquear accept em pedido self-service (invitee == inviter)',
  );
  assert.match(
    sql,
    /Pedido self-service nao pode ser auto-aceito[\s\S]*?USING ERRCODE = 'insufficient_privilege'/,
    'o guard deve levantar insufficient_privilege com a mensagem de auto-aprovação',
  );
});

test('#1254: decline permanece permitido (guard só sobre accept)', () => {
  const guard = sql.match(/IF p_response = 'accept' AND[\s\S]*?END IF;/);
  assert.ok(guard, 'bloco do guard presente');
  assert.doesNotMatch(
    guard[0],
    /'decline'/,
    'o guard não deve mencionar decline — decline segue como caminho de cancelamento',
  );
});
