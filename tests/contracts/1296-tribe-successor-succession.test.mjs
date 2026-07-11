/**
 * Contract: #1296 [EPIC #1020 Onda D] sucessao de lideranca first-class — headless/nomeacao
 * SOBRE admin_change_tribe_leader (reusa o swap governado, nao reimplementa).
 *
 * Migration: supabase/migrations/20260805000406_1296_tribe_successor_succession.sql
 *
 * Invariants under test:
 *  Static (always):
 *   - 3 funcoes: nominate_tribe_successor, place_tribe_successor, get_headless_tribes.
 *   - nominate/place SECDEF, gate manage_platform, REVOKE PUBLIC/anon/authenticated + GRANT.
 *   - get_headless_tribes STABLE SECDEF, manage_platform + service_role.
 *   - REUSE: place chama admin_change_tribe_leader (nao reimplementa o swap).
 *   - nominate(successor NULL) -> headless (park handoff tribe_leadership + leader_member_id NULL).
 *   - nominate(successor dado) -> delega a place_tribe_successor.
 *   - fix do bloqueador (descoberto no QA-ao-vivo): admin_change_tribe_leader usa now()::date
 *     (colunas date, era now()::text -> 42804) + guard de record v_old_leader_name (headless -> place).
 *  DB-gated:
 *   - get_headless_tribes (service) retorna {headless_tribes:[], count:n}.
 *   - gate: nominate/place via service (auth.uid NULL) sao recusados (Unauthorized) — prova o gate.
 *
 *  O ciclo funcional headless->visible->place (que exige um GP autenticado, pois admin_change_tribe_leader
 *  depende de auth.uid) foi provado por bloco DO rolled-back ao vivo (ver PR): tribe 1 headless
 *  f64ee70a->NULL, visivel, place->sucessor via swap governado, handoff placed, tudo revertido.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000406_1296_tribe_successor_succession.sql');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1296: 3 functions defined with correct volatility', () => {
  assert.ok(existsSync(MIG), 'migration file present');
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.nominate_tribe_successor\(/);
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.place_tribe_successor\(/);
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.get_headless_tribes\(\)/);
  assert.match(mig, /FUNCTION public\.get_headless_tribes\(\)[\s\S]*?STABLE SECURITY DEFINER/, 'get_headless_tribes is STABLE (read)');
});

test('#1296: nominate/place gated manage_platform + REVOKE/GRANT; get_headless + service_role', () => {
  for (const fn of ['nominate_tribe_successor', 'place_tribe_successor']) {
    assert.match(mig, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}\\([^)]*\\) FROM PUBLIC, anon, authenticated;`), `${fn} revoked`);
    assert.match(mig, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn}\\([^)]*\\) TO authenticated, service_role;`), `${fn} granted`);
  }
  const gates = mig.match(/can_by_member\(v_caller, 'manage_platform'\)/g) || [];
  assert.ok(gates.length >= 3, `manage_platform gate on all 3 (found ${gates.length})`);
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.get_headless_tribes\(\) FROM PUBLIC, anon;/);
  assert.match(mig, /'service_role'/, 'get_headless_tribes has service_role bypass');
});

test('#1296: REUSE admin_change_tribe_leader (swap NOT reimplemented)', () => {
  assert.match(mig, /public\.admin_change_tribe_leader\(p_tribe_id, p_successor_member_id/, 'place delegates to admin_change_tribe_leader');
  // place must not itself write leader_member_id via a raw swap (that is B/admin_change_tribe_leader's job)
  const placeBlock = mig.slice(mig.indexOf('FUNCTION public.place_tribe_successor'), mig.indexOf('FUNCTION public.nominate_tribe_successor'));
  assert.ok(!/UPDATE public\.tribes SET leader_member_id/.test(placeBlock), 'place must not raw-swap leader (reuses admin_change_tribe_leader)');
});

test('#1296: nominate — headless (park + vacate) vs delegate to place', () => {
  const nomBlock = mig.slice(mig.indexOf('FUNCTION public.nominate_tribe_successor'), mig.indexOf('FUNCTION public.get_headless_tribes'));
  assert.match(nomBlock, /IF p_successor_member_id IS NOT NULL THEN[\s\S]*?RETURN public\.place_tribe_successor/, 'successor given -> delegate to place');
  assert.match(nomBlock, /UPDATE public\.tribes SET leader_member_id = NULL/, 'headless vacates the leader slot');
  assert.match(nomBlock, /park_responsibility_handoff\([\s\S]*?'tribe_leadership'/, 'headless parks a tribe_leadership handoff (Onda B)');
  assert.match(nomBlock, /'tribe\.headless'/, 'headless is audited (visible, not silent)');
});

test('#1296: admin_change_tribe_leader blocker fix — date casts + record guard', () => {
  // no now()::text feeding date columns; both cycle_start COALESCEs use now()::date
  assert.ok(!/COALESCE\(v_cycle\.cycle_start, now\(\)::text\)/.test(mig), 'must not COALESCE(date, now()::text) (42804)');
  assert.ok((mig.match(/COALESCE\(v_cycle\.cycle_start, now\(\)::date\)/g) || []).length >= 2, 'both inserts use now()::date');
  // headless -> place: v_old_leader record guarded via a separate name variable
  assert.match(mig, /v_old_leader_name text;/, 'record guard variable declared');
  assert.match(mig, /'old_leader', COALESCE\(v_old_leader_name, 'N\/A'\)/, 'RETURN uses guarded name (not unassigned record)');
});

// ── DB-gated ──
test('#1296 DB: get_headless_tribes returns {headless_tribes:[], count}', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_headless_tribes');
  assert.ok(!error, `RPC must not throw: ${error?.message}`);
  assert.ok(Array.isArray(data.headless_tribes), 'headless_tribes is an array');
  assert.equal(typeof data.count, 'number', 'count is a number');
  assert.equal(data.count, data.headless_tribes.length, 'count matches array length');
});

test('#1296 DB: nominate/place self-gate — a service-role call (no auth.uid) is refused', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: nom } = await sb.rpc('nominate_tribe_successor', { p_tribe_id: 1, p_successor_member_id: null });
  assert.match(nom?.error || '', /Unauthorized/, `nominate must self-gate: ${JSON.stringify(nom)}`);
  const { data: place } = await sb.rpc('place_tribe_successor', {
    p_tribe_id: 1, p_successor_member_id: '880f736c-3e76-4df4-9375-33575c190305',
  });
  assert.match(place?.error || '', /Unauthorized/, `place must self-gate: ${JSON.stringify(place)}`);
});
