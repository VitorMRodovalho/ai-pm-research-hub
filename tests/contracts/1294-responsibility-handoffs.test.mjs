/**
 * Contract: #1294 [EPIC #1020 Onda B] estado pending-successor — tabela
 * responsibility_handoffs + park/place/cancel. Modela um handoff estacionado com
 * sucessor TBD e aplica a reatribuicao atomicamente ao colocar o sucessor.
 *
 * Migration: supabase/migrations/20260805000405_1294_responsibility_handoffs.sql
 *
 * Invariants under test:
 *  Static (always):
 *   - tabela com item_type CHECK (7 superfícies), status CHECK, successor NULLABLE (TBD).
 *   - deny-all: ENABLE ROW LEVEL SECURITY (sem policy) + REVOKE de anon, authenticated.
 *   - unique index parcial (1 handoff pending por item de origem).
 *   - 3 funcoes SECDEF, gate manage_platform + service_role, REVOKE FROM PUBLIC/anon/authenticated.
 *   - place: CASE de reatribuicao cobrindo as 7 superfícies + guard de 0-row.
 *   - cards_owned roteia para assignee (created_by imutavel — regra de merito).
 *  DB-gated (nao-destrutivo — item_ref sintetico; a reatribuicao real de superficie foi
 *  provada por bloco DO rolled-back ao vivo, ver PR):
 *   - park cria pending; idempotente por (item_type,item_ref).
 *   - place num item_ref inexistente -> {error: source item not found} E handoff FICA pending
 *     (o guard de 0-row NAO marca placed). Prova o dispatch + a atomicidade.
 *   - cancel -> cancelled; idempotente.
 *   - anon esta trancado (execute revogado).
 *   - cleanup: as linhas de teste sao removidas (service_role bypassa RLS).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000405_1294_responsibility_handoffs.sql');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const SURFACES = ['board_items_assigned', 'cards_owned', 'checklist_items', 'tribe_leadership',
                  'curation_assignments', 'action_items', 'drive_grants'];

test('#1294: table responsibility_handoffs — item_type CHECK (7), status CHECK, successor NULLABLE', () => {
  assert.ok(existsSync(MIG), 'migration file present');
  assert.match(mig, /CREATE TABLE public\.responsibility_handoffs/);
  for (const s of SURFACES) assert.ok(mig.includes(`'${s}'`), `item_type CHECK must include ${s}`);
  assert.match(mig, /status text NOT NULL DEFAULT 'pending' CHECK \(status IN \('pending', 'placed', 'cancelled'\)\)/);
  assert.match(mig, /successor_member_id uuid REFERENCES public\.members\(id\)/, 'successor NULLABLE (TBD)');
  assert.ok(!/successor_member_id uuid NOT NULL/.test(mig), 'successor must be nullable');
});

test('#1294: deny-all RLS + REVOKE from anon, authenticated', () => {
  assert.match(mig, /ALTER TABLE public\.responsibility_handoffs ENABLE ROW LEVEL SECURITY;/);
  assert.match(mig, /REVOKE ALL ON public\.responsibility_handoffs FROM anon, authenticated;/);
  assert.ok(!/CREATE POLICY/.test(mig), 'deny-all: no policy (access via SECDEF RPCs only)');
});

test('#1294: unique partial index — 1 pending handoff per source item', () => {
  assert.match(mig, /CREATE UNIQUE INDEX ux_responsibility_handoffs_pending_item[\s\S]*?\(item_type, item_ref\) WHERE status = 'pending'/);
});

test('#1294: 3 SECDEF functions gated manage_platform + service_role, anon revoked', () => {
  for (const fn of ['park_responsibility_handoff', 'place_responsibility_handoff', 'cancel_responsibility_handoff']) {
    assert.match(mig, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\(`), `${fn} defined`);
    assert.match(mig, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}\\([^)]*\\) FROM PUBLIC, anon, authenticated;`), `${fn} revoked`);
    assert.match(mig, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn}\\([^)]*\\) TO authenticated, service_role;`), `${fn} granted`);
  }
  const gates = mig.match(/can_by_member\(v_caller, 'manage_platform'\)/g) || [];
  assert.ok(gates.length >= 3, `manage_platform gate on all 3 functions (found ${gates.length})`);
  assert.ok((mig.match(/'service_role'/g) || []).length >= 3, 'service_role bypass on all 3');
});

test('#1294: place CASE covers all 7 surfaces + 0-row guard; cards_owned -> assignee (merit)', () => {
  for (const s of SURFACES) assert.match(mig, new RegExp(`WHEN '${s}' THEN`), `place CASE must handle ${s}`);
  assert.match(mig, /GET DIAGNOSTICS v_rows = ROW_COUNT;[\s\S]*?IF v_rows = 0 THEN[\s\S]*?source item not found/,
    'place must guard reassignment against 0 rows (do not mark placed)');
  // cards_owned routes to assignee_id (created_by is immutable per merit rule)
  const cardsBlock = mig.slice(mig.indexOf("WHEN 'cards_owned' THEN"), mig.indexOf("WHEN 'checklist_items' THEN"));
  assert.match(cardsBlock, /SET assignee_id = p_successor_member_id/, 'cards_owned reassigns assignee, not created_by');
  assert.ok(!/created_by = p_successor/.test(mig), 'must never rewrite created_by (merit immutable)');
});

// ── DB-gated: park/place/cancel lifecycle, non-destructive (synthetic item_ref). ──
test('#1294 DB: park -> place(bad ref, stays pending) -> cancel lifecycle + idempotency', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const created = [];
  try {
    // real from/owner members; item_ref is a random uuid that matches NO board_item
    const { data: gp } = await sb.from('members').select('id').eq('id', '880f736c-3e76-4df4-9375-33575c190305').single();
    const { data: someone } = await sb.from('members').select('id').neq('id', gp.id).limit(1).single();
    const syntheticRef = '11111111-2222-3333-4444-555555555555';

    // PARK (successor TBD)
    const { data: park } = await sb.rpc('park_responsibility_handoff', {
      p_from_member_id: someone.id, p_item_type: 'board_items_assigned', p_item_ref: syntheticRef,
      p_owner_member_id: gp.id, p_reason: 'contract test',
    });
    assert.equal(park.status, 'pending', `park should be pending: ${JSON.stringify(park)}`);
    assert.ok(park.handoff_id, 'park returns handoff_id');
    created.push(park.handoff_id);

    // idempotency
    const { data: park2 } = await sb.rpc('park_responsibility_handoff', {
      p_from_member_id: someone.id, p_item_type: 'board_items_assigned', p_item_ref: syntheticRef, p_owner_member_id: gp.id,
    });
    assert.equal(park2.already_parked, true, 'second park is idempotent');
    assert.equal(park2.handoff_id, park.handoff_id, 'idempotent park returns same handoff');

    // PLACE on a ref that matches no board_item -> 0-row guard, stays pending
    const { data: place } = await sb.rpc('place_responsibility_handoff', {
      p_handoff_id: park.handoff_id, p_successor_member_id: gp.id,
    });
    assert.ok(place.error && /source item not found/.test(place.error), `place should hit 0-row guard: ${JSON.stringify(place)}`);
    const { data: row } = await sb.from('responsibility_handoffs').select('status').eq('id', park.handoff_id).single();
    assert.equal(row.status, 'pending', 'handoff must STAY pending when reassignment affected 0 rows (atomicity)');

    // CANCEL + idempotency
    const { data: cancel } = await sb.rpc('cancel_responsibility_handoff', { p_handoff_id: park.handoff_id, p_reason: 'test done' });
    assert.equal(cancel.status, 'cancelled', `cancel: ${JSON.stringify(cancel)}`);
    const { data: cancel2 } = await sb.rpc('cancel_responsibility_handoff', { p_handoff_id: park.handoff_id });
    assert.equal(cancel2.already_cancelled, true, 'second cancel is idempotent');
  } finally {
    for (const id of created) await sb.from('responsibility_handoffs').delete().eq('id', id);
  }
});

test('#1294 DB: anon is locked out (execute revoked)', { skip: (dbGated && ANON_KEY) ? false : 'Skipped: anon key required' }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { error } = await anon.rpc('park_responsibility_handoff', {
    p_from_member_id: '880f736c-3e76-4df4-9375-33575c190305', p_item_type: 'board_items_assigned',
    p_item_ref: 'x', p_owner_member_id: '880f736c-3e76-4df4-9375-33575c190305',
  });
  assert.ok(error, 'anon must be denied execute on park_responsibility_handoff');
});
