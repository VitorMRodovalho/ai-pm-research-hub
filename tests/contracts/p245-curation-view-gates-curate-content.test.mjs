/**
 * Contract: #245 (root cause #185) — curation-queue VIEW RPCs must gate additively on curate_content.
 *
 * The 3 view RPCs (get_curation_dashboard, list_curation_pending_board_items, list_pending_curation)
 * gated solely on write_board / write. A pure curator's authority is designation-derived
 * (`curator` designation → curate_content) and does NOT include write_board, so curators with
 * operational_role <> manager (Roberto Macêdo, Sarah Rodovalho) were denied at the RPC layer even
 * though the client gate (hasPermission 'admin.curation' via curator designation) let them through.
 *
 * Migration 20260805000098 makes the gate ADDITIVE: curate_content OR (existing write_board/write).
 *   - STATIC: each RPC's gate now includes a curate_content OR-arm.
 *   - BEHAVIOURAL: the unblocked population exists (curate_content=true, write_board=false) AND the
 *     existing write_board population still passes (zero-regression). The review action
 *     submit_curation_review already gates on participate_in_governance_review (curators hold it).
 *
 * Asserted as RELATIONSHIPS (capability sets), not hardcoded names, so it survives roster growth.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000098_245_curation_view_gates_curate_content.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
// #185 Item-2: list_curation_board (the 4th, previously-ungated curation reader) gated 2026-06-05.
const MIG185 = resolve(ROOT, 'supabase/migrations/20260805000112_185_gate_list_curation_board.sql');
const mig185Raw = existsSync(MIG185) ? readFileSync(MIG185, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const client = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
const can = async (sb, id, action) => {
  const { data, error } = await sb.rpc('can_by_member', { p_member_id: id, p_action: action });
  assert.ifError(error);
  return data === true;
};

// ── STATIC ──────────────────────────────────────────────────────────────────────
test('#245 static: migration 098 exists', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000098 exists');
});

test('#245 static: get_curation_dashboard gates curate_content OR write_board', () => {
  assert.match(migRaw,
    /CREATE OR REPLACE FUNCTION public\.get_curation_dashboard[\s\S]*?can_by_member\(v_member_id, 'curate_content'\)[\s\S]{0,80}OR[\s\S]{0,80}can_by_member\(v_member_id, 'write_board'\)/,
    'get_curation_dashboard gate is additive (curate_content OR write_board)');
});

test('#245 static: list_curation_pending_board_items gates curate_content OR write_board', () => {
  assert.match(migRaw,
    /CREATE OR REPLACE FUNCTION public\.list_curation_pending_board_items[\s\S]*?can_by_member\(v_member_id, 'curate_content'\)[\s\S]{0,80}OR[\s\S]{0,80}can_by_member\(v_member_id, 'write_board'\)/,
    'list_curation_pending_board_items gate is additive');
});

test('#245 static: list_pending_curation gates curate_content OR write', () => {
  assert.match(migRaw,
    /CREATE OR REPLACE FUNCTION public\.list_pending_curation[\s\S]*?can_by_member\(v_member_id, 'curate_content'\)[\s\S]{0,80}OR[\s\S]{0,80}can_by_member\(v_member_id, 'write'\)/,
    'list_pending_curation gate is additive');
});

test('#245 static: no view RPC reverts to a write_board-ONLY gate (regression guard)', () => {
  // The bare "IF NOT can_by_member(v_member_id, 'write_board') THEN" (no curate_content OR-arm) is forbidden.
  assert.doesNotMatch(migRaw, /IF NOT public\.can_by_member\(v_member_id, 'write_board'\) THEN/,
    'no curation view RPC may gate on write_board alone');
});

test('#245 static: no view RPC narrows to a curate_content-ONLY gate (symmetric guard)', () => {
  // The symmetric failure: dropping the write_board/write OR-arm would silently lock out the
  // existing privileged population (tribe_leaders/managers). A bare curate_content-only gate is forbidden.
  assert.doesNotMatch(migRaw, /IF NOT public\.can_by_member\(v_member_id, 'curate_content'\) THEN/,
    'no curation view RPC may gate on curate_content alone (must keep the write_board/write OR-arm)');
});

test('#185 Item-2 static: migration 112 exists and gates list_curation_board', () => {
  assert.ok(existsSync(MIG185), 'migration 20260805000112 exists');
  assert.match(mig185Raw,
    /CREATE OR REPLACE FUNCTION public\.list_curation_board[\s\S]*?can_by_member\(v_member_id, 'curate_content'\)[\s\S]{0,80}OR[\s\S]{0,80}can_by_member\(v_member_id, 'write_board'\)/,
    'list_curation_board gate is additive (curate_content OR write_board)');
  assert.match(mig185Raw, /RAISE EXCEPTION 'Not authenticated'/,
    'list_curation_board raises when caller is not a member');
});

test('#185 Item-2 static: list_curation_board does not narrow to a single-capability gate', () => {
  assert.doesNotMatch(mig185Raw, /IF NOT public\.can_by_member\(v_member_id, 'curate_content'\) THEN/,
    'list_curation_board must keep the write_board OR-arm (no curate_content-only narrowing)');
  assert.doesNotMatch(mig185Raw, /IF NOT public\.can_by_member\(v_member_id, 'write_board'\) THEN/,
    'list_curation_board must keep the curate_content OR-arm (no write_board-only gate)');
});

// ── BEHAVIOURAL (DB-gated) ────────────────────────────────────────────────────────
test('#185 Item-2 behavioural: list_curation_board denies an unauthenticated caller (leak closed)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    // Service-role => auth.uid() is NULL => v_member_id IS NULL => 'Not authenticated' fires.
    // Pre-fix this RPC had NO gate and returned all hub_resources rows to any caller.
    const { error } = await sb.rpc('list_curation_board');
    assert.ok(error, 'list_curation_board must now gate (was ungated)');
    assert.match(String(error.message || ''), /Not authenticated|Curatorship access required/,
      `expected the curation gate to fire, got: ${JSON.stringify(error)}`);
  });

test('#245 behavioural: the unblocked population exists (curate_content=true, write_board=false)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    const { data, error } = await sb.from('members')
      .select('id, name, designations, operational_role')
      .eq('member_status', 'active')
      .contains('designations', ['curator']);
    assert.ifError(error);
    assert.ok(Array.isArray(data) && data.length > 0, 'at least one active curator-designation member');

    let pureCurators = 0;
    for (const m of data) {
      const curate = await can(sb, m.id, 'curate_content');
      const wboard = await can(sb, m.id, 'write_board');
      assert.equal(curate, true, `${m.name} (curator designation) must have curate_content`);
      if (curate && !wboard) pureCurators++;
    }
    assert.ok(pureCurators >= 1,
      `expected >= 1 pure curator (curate_content w/o write_board) that the fix unblocks, got ${pureCurators}`);
  });

test('#245 behavioural: review action submit_curation_review is reachable by curators (gov_review)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    const { data, error } = await sb.from('members')
      .select('id, name')
      .eq('member_status', 'active')
      .contains('designations', ['curator']);
    assert.ifError(error);
    for (const m of data) {
      assert.equal(await can(sb, m.id, 'participate_in_governance_review'), true,
        `curator ${m.name} must hold participate_in_governance_review (so submit_curation_review accepts them)`);
    }
  });

test('#245 behavioural: existing write_board population still passes (zero-regression)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    const { data, error } = await sb.from('members')
      .select('id, name')
      .eq('member_status', 'active')
      .eq('operational_role', 'tribe_leader')
      .limit(3);
    assert.ifError(error);
    assert.ok(Array.isArray(data) && data.length > 0, 'has active tribe_leaders to sample');
    for (const m of data) {
      // additive gate = curate_content OR write_board; tribe_leaders keep access via write_board
      const passes = (await can(sb, m.id, 'curate_content')) || (await can(sb, m.id, 'write_board'));
      assert.equal(passes, true, `tribe_leader ${m.name} must still pass the additive curation gate`);
    }
  });

test('#245 behavioural: gate still CLOSES for members lacking both capabilities (not fail-open)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    // write_board is broadly held (tribe-membership engagements grant it); curate_content is narrow.
    // The denial set = active members with NEITHER capability (no tribe engagement + not a curator).
    // Grounded 2026-06-03: 15 of 50 active members are denied. Sampling 40 of 50 (ordered) guarantees
    // >= 5 denied remain in the sample, so the >= 1 assertion is robust to roster drift.
    const { data, error } = await sb.from('members')
      .select('id, name')
      .eq('member_status', 'active')
      .order('id')
      .limit(40);
    assert.ifError(error);
    assert.ok(Array.isArray(data) && data.length > 0, 'has active members to sample');
    let denied = 0;
    for (const m of data) {
      const passes = (await can(sb, m.id, 'curate_content')) || (await can(sb, m.id, 'write_board'));
      if (!passes) denied++;
    }
    assert.ok(denied >= 1,
      `gate must DENY members lacking both curate_content and write_board (not fail-open); ${denied}/${data.length} denied`);
  });
