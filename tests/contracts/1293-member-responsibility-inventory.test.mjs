/**
 * Contract: #1293 [EPIC #1020 Onda A] get_member_responsibility_inventory — read-only
 * inventory of the 7 ownership surfaces a member holds, the foundation of the
 * responsibility-handoff protocol (#1020).
 *
 * Migration: supabase/migrations/20260805000404_1293_member_responsibility_inventory.sql
 *
 * Invariants under test:
 *  Static (always):
 *   - SECURITY DEFINER + STABLE (read-only).
 *   - gate: manage_platform (can_by_member) OR service_role; anon path revoked.
 *   - confidential gate (rls_can_see_initiative, ADR-0105) on the initiative-linked surfaces.
 *   - grants: REVOKE FROM PUBLIC, anon + GRANT authenticated, service_role.
 *   - all 7 surfaces referenced by their source column.
 *  DB-gated (single-source, data-driven — RPC counts must equal an independent live
 *  query of the same filters; NO hardcoded cohort numbers so the assertion survives data drift):
 *   - each of the 7 surface counts equals the direct PostgREST count.
 *   - no surface silently absent (all 7 keys present).
 *   - total_items equals the sum of the surfaces.
 *   - a nonexistent member returns {error:'Member not found'}.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000404_1293_member_responsibility_inventory.sql');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const OPEN_STATUS_EXCLUDE = ['done', 'archived'];
const CURATION_ACTIVE = ['curation_pending', 'leader_review'];

test('#1293: migration defines get_member_responsibility_inventory(uuid), SECURITY DEFINER + STABLE', () => {
  assert.ok(existsSync(MIG), 'migration file present');
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.get_member_responsibility_inventory\(p_member_id uuid\)/);
  assert.match(mig, /SECURITY DEFINER/);
  assert.match(mig, /\bSTABLE\b/);
});

test('#1293: gate is manage_platform OR service_role', () => {
  assert.match(mig, /can_by_member\(v_caller, 'manage_platform'\)/);
  assert.match(mig, /'service_role'/);
  assert.match(mig, /requires manage_platform permission/);
});

test('#1293: confidential gate (rls_can_see_initiative, ADR-0105) on initiative-linked surfaces', () => {
  const gates = mig.match(/public\.rls_can_see_initiative\(pb\.initiative_id\)/g) || [];
  // board_items_assigned, cards_owned, checklist, curation, drive_grants = 5 board-linked surfaces
  assert.ok(gates.length >= 5, `expected the confidential gate on >=5 initiative-linked surfaces (found ${gates.length})`);
});

test('#1293: grants — revoked from PUBLIC/anon, granted to authenticated + service_role', () => {
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.get_member_responsibility_inventory\(uuid\) FROM PUBLIC, anon;/);
  assert.match(mig, /GRANT EXECUTE ON FUNCTION public\.get_member_responsibility_inventory\(uuid\) TO authenticated, service_role;/);
});

test('#1293: all 7 ownership surfaces referenced by their source column', () => {
  assert.match(mig, /bi\.assignee_id = p_member_id/, 'surface 1: board_items.assignee_id');
  assert.match(mig, /bi\.created_by = p_member_id/, 'surface 2: board_items.created_by');
  assert.match(mig, /c\.assigned_to = p_member_id/, 'surface 3: board_item_checklists.assigned_to');
  assert.match(mig, /t\.leader_member_id = p_member_id/, 'surface 4: tribes.leader_member_id');
  assert.match(mig, /bi\.reviewer_id = p_member_id/, 'surface 5: board_items.reviewer_id (curation)');
  assert.match(mig, /a\.assignee_id = p_member_id/, 'surface 6: meeting_action_items.assignee_id');
  assert.match(mig, /g\.grantee_member_id = p_member_id/, 'surface 7: drive_curation_grants.grantee_member_id');
});

// ── DB-gated: single-source parity — the RPC (service-role path) must match a live
//    independent query of the same filters. Fixture member chosen dynamically. ──
test('#1293 DB: surface counts equal an independent live query (data-driven)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  // pick, at runtime, the member with the most open board assignments (a real, multi-surface owner)
  const { data: top } = await sb
    .from('board_items').select('assignee_id')
    .not('assignee_id', 'is', null)
    .not('status', 'in', `(${OPEN_STATUS_EXCLUDE.join(',')})`)
    .limit(2000);
  assert.ok(top && top.length, 'expected at least one open assigned board_item to pick a fixture');
  const tally = {};
  for (const r of top) tally[r.assignee_id] = (tally[r.assignee_id] || 0) + 1;
  const memberId = Object.entries(tally).sort((a, b) => b[1] - a[1])[0][0];

  const { data: inv, error } = await sb.rpc('get_member_responsibility_inventory', { p_member_id: memberId });
  assert.ok(!error, `RPC must not throw: ${error?.message}`);
  assert.ok(!inv.error, `RPC returned an error for a real member: ${JSON.stringify(inv.error)}`);

  // all 7 surfaces present (no silent absence)
  const s = inv.surfaces;
  for (const key of ['board_items_assigned', 'cards_owned', 'checklist_items', 'tribe_leadership',
                     'curation_assignments', 'action_items', 'drive_grants']) {
    assert.ok(s[key] && typeof s[key].count === 'number', `surface ${key} must be present with a count`);
  }

  const countOf = async (q) => (await q).count ?? 0;
  const cx = (t) => sb.from(t).select('*', { count: 'exact', head: true });

  const expected = {
    board_items_assigned: await countOf(cx('board_items').eq('assignee_id', memberId).not('status', 'in', `(${OPEN_STATUS_EXCLUDE.join(',')})`)),
    cards_owned:          await countOf(cx('board_items').eq('created_by', memberId).not('status', 'in', `(${OPEN_STATUS_EXCLUDE.join(',')})`)),
    checklist_items:      await countOf(cx('board_item_checklists').eq('assigned_to', memberId).eq('is_completed', false)),
    tribe_leadership:     await countOf(cx('tribes').eq('leader_member_id', memberId).eq('is_active', true)),
    curation_assignments: await countOf(cx('board_items').eq('reviewer_id', memberId).in('curation_status', CURATION_ACTIVE)),
    action_items:         await countOf(cx('meeting_action_items').eq('assignee_id', memberId).eq('status', 'open')),
    drive_grants:         await countOf(cx('drive_curation_grants').eq('grantee_member_id', memberId).is('revoked_at', null)),
  };

  let sum = 0;
  for (const [key, exp] of Object.entries(expected)) {
    assert.equal(s[key].count, exp, `surface ${key}: RPC ${s[key].count} != live query ${exp} (member ${memberId})`);
    assert.equal(s[key].items.length, exp, `surface ${key}: items[] length ${s[key].items.length} != count ${exp}`);
    sum += exp;
  }
  assert.equal(inv.total_items, sum, `total_items ${inv.total_items} != sum of surfaces ${sum}`);
});

test('#1293 DB: nonexistent member returns {error:"Member not found"}', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_member_responsibility_inventory', {
    p_member_id: '00000000-0000-0000-0000-000000000000',
  });
  assert.ok(!error, `RPC should return a JSON error object, not throw: ${error?.message}`);
  assert.equal(data?.error, 'Member not found', `expected not-found, got: ${JSON.stringify(data)}`);
});
