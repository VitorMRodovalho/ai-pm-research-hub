// #1255 (Wave 1) — cancel_tribe_request lets a researcher cancel their OWN pending self-service
// tribe request (reusing status='declined' + reviewed_note='self_cancelled'), and
// get_my_tribe_request_context exposes the pending invitation_id so the card can call it. See
// docs/specs/SPEC_TRIBE_SWITCH_AND_LEADER_REVIEW.md §Wave 1.
// Static test over the migration; the body-drift gate (Phase C) covers live-vs-migration drift.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIG = join(
  __dirname,
  '../../supabase/migrations/20260805000392_1255_wave1_cancel_tribe_request.sql',
);
const sql = readFileSync(MIG, 'utf8');

test('#1255: migration cria a função cancel_tribe_request(uuid)', () => {
  assert.match(
    sql,
    /CREATE OR REPLACE FUNCTION public\.cancel_tribe_request\(p_invitation_id uuid\)/,
    'a migration deve criar cancel_tribe_request(p_invitation_id uuid)',
  );
});

test('#1255: só o próprio invitee pode cancelar (guard de autoria)', () => {
  assert.match(
    sql,
    /v_invitation\.invitee_member_id <> v_caller_member_id[\s\S]*?USING ERRCODE = 'insufficient_privilege'/,
    'deve bloquear quem não é o invitee do pedido',
  );
});

test('#1255: só cancela pedido self-service (invitee == inviter)', () => {
  assert.match(
    sql,
    /v_invitation\.inviter_member_id <> v_invitation\.invitee_member_id[\s\S]*?USING ERRCODE = 'invalid_parameter_value'/,
    'convite líder→pesquisador (invitee != inviter) não é cancelado por esta RPC',
  );
});

test('#1255: só cancela pedido de research_tribe pendente', () => {
  assert.match(sql, /v_initiative\.kind IS DISTINCT FROM 'research_tribe'/, 'restringe a research_tribe');
  assert.match(sql, /v_invitation\.status <> 'pending'/, 'só cancela pedido pendente');
});

test('#1255: reusa declined + marca self_cancelled (sem mexer no CHECK do enum)', () => {
  assert.match(
    sql,
    /SET status = 'declined',\s*\n\s*reviewed_note = 'self_cancelled'/,
    "seta status='declined' + reviewed_note='self_cancelled'",
  );
  // não introduz um novo valor 'cancelled' de status (evita alterar o CHECK)
  assert.doesNotMatch(sql, /status = 'cancelled'/, "não deve usar um status 'cancelled' novo");
});

test('#1255: grant só a authenticated, revoga PUBLIC (paridade com as RPCs de tribo)', () => {
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.cancel_tribe_request\(uuid\) FROM PUBLIC/);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.cancel_tribe_request\(uuid\) TO authenticated/);
});

test('#1255: get_my_tribe_request_context expõe invitation_id no pending', () => {
  assert.match(
    sql,
    /CREATE OR REPLACE FUNCTION public\.get_my_tribe_request_context\(\)/,
    'a migration deve redefinir get_my_tribe_request_context',
  );
  assert.match(
    sql,
    /SELECT ii\.id AS invitation_id,/,
    'o subquery pending deve retornar ii.id AS invitation_id',
  );
});
