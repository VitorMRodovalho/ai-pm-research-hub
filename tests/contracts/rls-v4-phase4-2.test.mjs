/**
 * Domain Model V4 — Fase 4.2 — RLS MEMBER_CHECK decoupling
 *
 * Static analysis contract test for migration 20260427040000.
 * Decouples 23 SELECT policies from legacy `get_my_member_record()`:
 *   20 MEMBER_CHECK  → rls_is_member()
 *    2 GHOST_CHECK   → NOT rls_is_member()
 *    1 ROLE_GATE missed in Fase 4.1 → rls_is_superadmin() + rls_can('manage_member')
 *
 * Validates:
 *   1. `rls_is_member()` helper function exists with correct shape
 *   2. All 20 MEMBER_CHECK policies use rls_is_member()
 *   3. Both GHOST_CHECK policies use `NOT rls_is_member()` + public filter
 *   4. broadcast_log_read_admin uses V4 helpers (Fase 4.1 miss correction)
 *   5. No policy in this migration references get_my_member_record directly
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function findMigration(pattern) {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.includes(pattern));
  assert.ok(files.length > 0, `Migration matching "${pattern}" must exist`);
  return readFileSync(resolve(MIGRATIONS_DIR, files[0]), 'utf8');
}

test('Phase 4.2 migration: helper function', async (t) => {
  const sql = findMigration('v4_phase4_2_rls_member_check');

  await t.test('creates rls_is_member() function', () => {
    assert.match(sql, /CREATE OR REPLACE FUNCTION public\.rls_is_member\(\)/i);
  });

  await t.test('rls_is_member is STABLE SECURITY DEFINER', () => {
    const start = sql.indexOf('CREATE OR REPLACE FUNCTION public.rls_is_member');
    const end = sql.indexOf('COMMENT ON FUNCTION public.rls_is_member');
    assert.ok(start >= 0 && end > start, 'rls_is_member definition must be found');
    const fnBlock = sql.substring(start, end);
    assert.match(fnBlock, /STABLE/i);
    assert.match(fnBlock, /SECURITY DEFINER/i);
  });

  await t.test('rls_is_member reads from public.members + auth.uid()', () => {
    const start = sql.indexOf('CREATE OR REPLACE FUNCTION public.rls_is_member');
    const end = sql.indexOf('COMMENT ON FUNCTION public.rls_is_member');
    const fnBlock = sql.substring(start, end);
    assert.match(fnBlock, /EXISTS\s*\(\s*SELECT 1 FROM public\.members m\s*WHERE m\.auth_id = auth\.uid\(\)\s*\)/i);
  });

  await t.test('rls_is_member granted to authenticated', () => {
    assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.rls_is_member\(\) TO authenticated/i);
  });
});

test('Phase 4.2 migration: MEMBER_CHECK policies (20)', async (t) => {
  const sql = findMigration('v4_phase4_2_rls_member_check');

  const memberCheckPolicies = [
    { table: 'attendance', policy: 'attendance_read_members' },
    { table: 'board_item_assignments', policy: 'assignments_read_members' },
    { table: 'board_item_checklists', policy: 'checklists_read_members' },
    { table: 'board_item_tag_assignments', policy: 'tag_assignments_read_members' },
    { table: 'board_items', policy: 'board_items_read_members' },
    { table: 'change_requests', policy: 'cr_read_members' },
    { table: 'course_progress', policy: 'course_progress_read_members' },
    { table: 'event_audience_rules', policy: 'audience_rules_read_members' },
    { table: 'event_invited_members', policy: 'invited_read_members' },
    { table: 'event_tag_assignments', policy: 'event_tags_read_members' },
    { table: 'events', policy: 'events_read_members' },
    { table: 'gamification_points', policy: 'gamification_read_members' },
    { table: 'members', policy: 'members_read_by_members' },
    { table: 'partner_entities', policy: 'partners_read_members' },
    { table: 'project_boards', policy: 'project_boards_read_members' },
    { table: 'publication_submission_authors', policy: 'sub_authors_read_members' },
    { table: 'publication_submission_events', policy: 'sub_events_read_members' },
    { table: 'publication_submissions', policy: 'submissions_read_members' },
    { table: 'webinar_lifecycle_events', policy: 'wle_read_members' },
    { table: 'webinars', policy: 'webinars_read_members' },
  ];

  for (const { table, policy } of memberCheckPolicies) {
    await t.test(`${table}.${policy}: uses rls_is_member()`, () => {
      const idx = sql.indexOf(`CREATE POLICY "${policy}" ON public.${table}`);
      assert.ok(idx >= 0, `Policy ${policy} on ${table} must be created`);
      const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
      assert.match(block, /public\.rls_is_member\(\)/);
    });
  }

  await t.test('members_read_by_members preserves is_active = true clause', () => {
    const idx = sql.indexOf('CREATE POLICY "members_read_by_members"');
    const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
    assert.match(block, /is_active = true/);
    assert.match(block, /public\.rls_is_member\(\)/);
  });
});

test('Phase 4.2 migration: GHOST_CHECK policies (2)', async (t) => {
  const sql = findMigration('v4_phase4_2_rls_member_check');

  await t.test('events_read_ghost: NOT rls_is_member() + public types', () => {
    const idx = sql.indexOf('CREATE POLICY "events_read_ghost"');
    const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
    assert.match(block, /NOT public\.rls_is_member\(\)/);
    assert.match(block, /type = ANY \(ARRAY\['geral'/);
    assert.match(block, /'webinar'/);
  });

  await t.test('webinars_read_ghost: NOT rls_is_member() + public statuses', () => {
    const idx = sql.indexOf('CREATE POLICY "webinars_read_ghost"');
    const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
    assert.match(block, /NOT public\.rls_is_member\(\)/);
    assert.match(block, /status = ANY \(ARRAY\['confirmed'/);
    assert.match(block, /'completed'/);
  });
});

test('Phase 4.2 migration: Fase 4.1 miss correction', async (t) => {
  const sql = findMigration('v4_phase4_2_rls_member_check');

  await t.test('broadcast_log_read_admin: uses V4 helpers', () => {
    const idx = sql.indexOf('CREATE POLICY "broadcast_log_read_admin"');
    assert.ok(idx >= 0, 'broadcast_log_read_admin must be rewritten');
    const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
    assert.match(block, /rls_is_superadmin\(\)/);
    assert.match(block, /rls_can\('manage_member'\)/);
    assert.doesNotMatch(block, /operational_role/);
    assert.doesNotMatch(block, /get_my_member_record/);
  });
});

test('Phase 4.2 migration invariants', async (t) => {
  const sql = findMigration('v4_phase4_2_rls_member_check');

  await t.test('NOTIFY pgrst present', () => {
    assert.match(sql, /NOTIFY pgrst, 'reload schema'/);
  });

  await t.test('BEGIN + COMMIT wrap', () => {
    assert.match(sql, /^\s*BEGIN;/m);
    assert.match(sql, /^\s*COMMIT;/m);
  });

  await t.test('Rollback block preserved in comments', () => {
    assert.match(sql, /ROLLBACK: Original policy definitions/i);
  });

  await t.test('No active CREATE POLICY block references get_my_member_record', () => {
    const rollbackStart = sql.indexOf('-- ROLLBACK:');
    const activeSql = rollbackStart > 0 ? sql.substring(0, rollbackStart) : sql;
    const policyBlocks = activeSql.match(/CREATE POLICY[\s\S]*?;/g) || [];
    assert.ok(policyBlocks.length >= 23, `Expected ≥23 CREATE POLICY blocks, got ${policyBlocks.length}`);
    for (const block of policyBlocks) {
      assert.doesNotMatch(block, /get_my_member_record/,
        `Policy should not reference get_my_member_record: ${block.substring(0, 120)}`);
    }
  });

  await t.test('No active CREATE POLICY block references operational_role', () => {
    const rollbackStart = sql.indexOf('-- ROLLBACK:');
    const activeSql = rollbackStart > 0 ? sql.substring(0, rollbackStart) : sql;
    const policyBlocks = activeSql.match(/CREATE POLICY[\s\S]*?;/g) || [];
    for (const block of policyBlocks) {
      assert.doesNotMatch(block, /operational_role/,
        `Policy should not reference operational_role: ${block.substring(0, 120)}`);
    }
  });

  await t.test('Expected count: 23 DROP + 23 CREATE pairs', () => {
    const rollbackStart = sql.indexOf('-- ROLLBACK:');
    const activeSql = rollbackStart > 0 ? sql.substring(0, rollbackStart) : sql;
    const drops = activeSql.match(/DROP POLICY IF EXISTS/g) || [];
    const creates = activeSql.match(/CREATE POLICY/g) || [];
    assert.equal(drops.length, 23, `Expected 23 DROPs, got ${drops.length}`);
    assert.equal(creates.length, 23, `Expected 23 CREATEs, got ${creates.length}`);
  });
});
