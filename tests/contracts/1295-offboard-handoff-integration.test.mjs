/**
 * Contract: #1295 [EPIC #1020 Onda C] integracao no offboard — pre-flight por-item + auto-park.
 * O offboard governado NAO orfaniza: roteia cada posse (7 superfícies) para um sucessor (place,
 * Onda B/D) ou auto-park (TBD, Onda B) antes de finalizar via admin_offboard_member.
 *
 * Migration: supabase/migrations/20260805000408_1295_offboard_handoff_integration.sql
 *
 * Invariants under test:
 *  Static:
 *   - prepare_member_offboard (STABLE read), offboard_member_with_handoffs (gate manage_member),
 *     detect_orphan_assignees_from_offboards (handoff-aware).
 *   - orchestrator REUSA park/place (Onda B), nominate_tribe_successor (Onda D),
 *     admin_offboard_member (finaliza com p_reassign_to NULL) e detect_orphan (verifica 0).
 *   - detect_orphan handoff-aware: item com responsibility_handoff pending NAO e orfao.
 *   - 6 superfícies de atribuicao + tribe_leadership no loop.
 *   - grants: orchestrator REVOKE PUBLIC/anon/authenticated; prepare REVOKE PUBLIC/anon.
 *  DB-gated (nao-destrutivo):
 *   - prepare_member_offboard (service) retorna inventario + requires_routing + total_owned.
 *   - offboard_member_with_handoffs via service (auth.uid NULL) e recusado (self-gate).
 *
 *  O ciclo destrutivo completo (route -> place / auto-park -> tribe headless -> finalize -> orphans=0)
 *  foi provado por bloco DO rolled-back ao vivo (ver PR): Henrique (tribe 9) offboard alumni,
 *  1 placed + tribe 9 headless, orphans_detected=0, tudo revertido.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000408_1295_offboard_handoff_integration.sql');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1295: 3 functions — prepare (STABLE), orchestrator, detect_orphan (handoff-aware)', () => {
  assert.ok(existsSync(MIG), 'migration file present');
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.prepare_member_offboard\(p_member_id uuid\)[\s\S]*?STABLE SECURITY DEFINER/);
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.offboard_member_with_handoffs\(/);
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.detect_orphan_assignees_from_offboards\(/);
});

test('#1295: orchestrator gate manage_member + REVOKE/GRANT; prepare REVOKE PUBLIC/anon', () => {
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.offboard_member_with_handoffs\([^)]*\) FROM PUBLIC, anon, authenticated;/);
  assert.match(mig, /GRANT EXECUTE ON FUNCTION public\.offboard_member_with_handoffs\([^)]*\) TO authenticated, service_role;/);
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.prepare_member_offboard\(uuid\) FROM PUBLIC, anon;/);
  assert.match(mig, /can_by_member\(v_caller, 'manage_member'\)/);
});

test('#1295: orchestrator REUSES park/place (B), nominate (D), admin_offboard_member, detect_orphan', () => {
  const orch = mig.slice(mig.indexOf('FUNCTION public.offboard_member_with_handoffs'));
  assert.match(orch, /public\.park_responsibility_handoff\(/, 'reuses park (Onda B)');
  assert.match(orch, /public\.place_responsibility_handoff\(/, 'reuses place (Onda B)');
  assert.match(orch, /public\.nominate_tribe_successor\(/, 'reuses nominate (Onda D)');
  assert.match(orch, /public\.admin_offboard_member\(p_member_id, p_new_status, p_reason_category, p_reason_detail, NULL\)/, 'finalizes with p_reassign_to NULL');
  assert.match(orch, /public\.detect_orphan_assignees_from_offboards\(p_member_id\)/, 'verifies 0 orphans');
});

test('#1295: detect_orphan is handoff-aware (pending handoff => not orphan)', () => {
  assert.match(mig, /NOT EXISTS \(\s*SELECT 1 FROM public\.responsibility_handoffs h[\s\S]*?h\.status = 'pending'/,
    'orphan detection must exclude items with a pending handoff');
});

test('#1295: all 6 assignment surfaces + tribe_leadership routed in the loop', () => {
  const orch = mig.slice(mig.indexOf('FUNCTION public.offboard_member_with_handoffs'));
  for (const s of ['board_items_assigned', 'cards_owned', 'checklist_items', 'curation_assignments', 'action_items', 'drive_grants']) {
    assert.ok(orch.includes(`'${s}'`), `orchestrator must route ${s}`);
  }
  assert.match(orch, /leader_member_id = p_member_id[\s\S]*?nominate_tribe_successor/, 'tribe leadership routed via nominate');
});

// ── DB-gated (non-destructive) ──
test('#1295 DB: prepare_member_offboard returns inventory + requires_routing', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('prepare_member_offboard', { p_member_id: 'c8b930c3-62ec-4d38-881e-307cd57a44f7' });
  assert.ok(!error, `prepare must not throw: ${error?.message}`);
  assert.ok(!data.error, `prepare returned error: ${JSON.stringify(data.error)}`);
  assert.ok(data.inventory && typeof data.inventory === 'object', 'inventory (7 surfaces) present');
  assert.equal(typeof data.total_owned, 'number', 'total_owned is a number');
  assert.equal(typeof data.requires_routing, 'boolean', 'requires_routing flag present');
});

test('#1295 DB: offboard_member_with_handoffs self-gates (service, no auth.uid => refused)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data } = await sb.rpc('offboard_member_with_handoffs', {
    p_member_id: 'c8b930c3-62ec-4d38-881e-307cd57a44f7', p_new_status: 'alumni', p_reason_category: 'personal_workload',
  });
  assert.match(data?.error || '', /Unauthorized/, `orchestrator must self-gate: ${JSON.stringify(data)}`);
});
