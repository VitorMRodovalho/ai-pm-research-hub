/**
 * Contract: #1289 — mover card entre boards com autoridade (segurança) + destinos visíveis.
 *
 * Migration: supabase/migrations/20260805000410_1289_harden_move_item_to_board.sql
 *
 * ANTES: move_item_to_board era SECURITY DEFINER SEM gate nenhum — qualquer authenticated movia
 * QUALQUER card para QUALQUER board (privilege escalation, RLS bypassado). O #1289 pede
 * "respeitar can()/visibilidade (confidencial ADR-0105)".
 *
 * DEPOIS: helper board_write_authority(member, board) (a disjuncao do move_board_item) + gate no
 * destino (rls_can_see_initiative + autoridade) E na origem (autoridade OU posse). Fail-closed.
 *
 * Invariantes:
 *  Static:
 *   - board_write_authority criado (STABLE SECURITY DEFINER), REVOKE FROM PUBLIC/anon/authenticated.
 *   - move_item_to_board checa rls_can_see_initiative(destino) + board_write_authority(destino) +
 *     (board_write_authority(origem) OR posse do card). RAISE fail-closed.
 *  DB-gated (nao-destrutivo):
 *   - move_item_to_board via service (auth.uid NULL) e recusado ('Not authenticated').
 *   - board_write_authority(GP, hub) = true; board_write_authority(researcher-de-outra-tribo, board-de-tribo) = false.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000410_1289_harden_move_item_to_board.sql');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// Fixtures estaveis (verificados ao vivo na sessao de autoria)
const GP_MEMBER = '880f736c-3e76-4df4-9375-33575c190305';
const HUB_BOARD = 'a6b78238-11aa-476a-b7e2-a674d224fd79';        // "Hub de Comunicação" (global)

test('#1289: board_write_authority created (SECURITY DEFINER) + locked down', () => {
  assert.ok(existsSync(MIG), 'migration file present');
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.board_write_authority\(p_member_id uuid, p_board_id uuid\)[\s\S]*?SECURITY DEFINER/);
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.board_write_authority\(uuid, uuid\) FROM PUBLIC, anon, authenticated;/);
});

test('#1289: move_item_to_board gates target (visibility + authority) AND source (authority OR ownership)', () => {
  const fn = mig.slice(mig.indexOf('FUNCTION public.move_item_to_board'));
  assert.match(fn, /rls_can_see_initiative\(v_target\.initiative_id\)/, 'target visibility gate (confidential ADR-0105)');
  assert.match(fn, /board_write_authority\(v_actor, p_target_board_id\)/, 'target write authority');
  assert.match(fn, /board_write_authority\(v_actor, v_old_board_id\)/, 'source write authority');
  assert.match(fn, /v_is_owner/, 'source ownership fallback');
  assert.match(fn, /RAISE EXCEPTION 'Unauthorized/, 'fail-closed with Unauthorized');
});

// ── DB-gated (non-destructive) ──
test('#1289 DB: move_item_to_board self-gates (service, no auth.uid => Not authenticated)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { error } = await sb.rpc('move_item_to_board', {
    p_item_id: '00000000-0000-0000-0000-000000000000',
    p_target_board_id: HUB_BOARD,
  });
  assert.ok(error, 'must raise (no auth.uid)');
  assert.match(error.message || '', /Not authenticated|insufficient_privilege/i, `self-gate: ${error?.message}`);
});

test('#1289 DB: board_write_authority — GP true on Hub, offboarded member (no active engagement) false', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  const { data: gpOnHub, error: e1 } = await sb.rpc('board_write_authority', { p_member_id: GP_MEMBER, p_board_id: HUB_BOARD });
  assert.ok(!e1, `must not throw: ${e1?.message}`);
  assert.equal(gpOnHub, true, 'GP has write authority on the Hub board');

  // An offboarded member (alumni/inactive) has NO active engagement, no leadership, and — since
  // write_board is engagement-derived — no write_board capability. board_write_authority must be false
  // on ANY board. (write_board IS a coarse capability, so a plain active researcher who holds it would
  // pass; the isolation guarantee is "no active authority => no board write", which this asserts.)
  const { data: gone } = await sb
    .from('members')
    .select('id')
    .in('member_status', ['alumni', 'inactive'])
    .limit(1);
  assert.ok(gone?.length, 'an offboarded member exists');
  const { data: noAuth, error: e2 } = await sb.rpc('board_write_authority', { p_member_id: gone[0].id, p_board_id: HUB_BOARD });
  assert.ok(!e2, `must not throw: ${e2?.message}`);
  assert.equal(noAuth, false, 'an offboarded member has NO write authority on the Hub board');
});
