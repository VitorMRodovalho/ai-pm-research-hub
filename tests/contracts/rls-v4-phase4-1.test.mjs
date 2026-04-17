/**
 * Domain Model V4 — Fase 4.1 — RLS Legacy Policy Sweep
 *
 * Static analysis contract test for the second-pass RLS migration.
 * Fase 4 (20260415010000) rewrote 36 policies. A 2026-04-17 audit surfaced
 * 42 additional role-gating policies still referencing operational_role.
 * Fase 4.1 migration 20260427030000 sweeps those.
 *
 * Validates:
 *   1. Migration file exists and has expected structure
 *   2. All 42 expected policies use V4 helpers (rls_can / rls_is_superadmin / rls_can_for_tribe)
 *   3. No policy block in the migration references operational_role directly
 *   4. Rollback block preserved in comments
 *   5. NOTIFY pgrst present
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

test('Phase 4.1 migration: RLS legacy policy sweep', async (t) => {
  const sql = findMigration('v4_phase4_1_rls_legacy_policies');

  // ───────── Category A: Superadmin-only ─────────
  const superadminOnly = [
    { table: 'admin_links', policy: 'admin_links_delete' },
    { table: 'admin_links', policy: 'admin_links_insert' },
    { table: 'admin_links', policy: 'admin_links_update' },
    { table: 'communication_templates', policy: 'templates_manage' },
    { table: 'taxonomy_tags', policy: 'taxonomy_tags_manage' },
    { table: 'webinars', policy: 'webinars_delete' },
    { table: 'members', policy: 'members_delete_superadmin' },
  ];

  for (const { table, policy } of superadminOnly) {
    await t.test(`${table}.${policy}: uses rls_is_superadmin() only`, () => {
      const re = new RegExp(
        `CREATE POLICY "${policy}" ON public\\.${table}[\\s\\S]*?public\\.rls_is_superadmin\\(\\)[\\s\\S]*?;`
      );
      assert.match(sql, re);
    });
  }

  // ───────── Category B: Admin + co_gp → manage_member ─────────
  const manageMember = [
    'admin_links_select',
    'members_insert_admin',
    'members_select_admin',
    'members_update_admin',
    'project_memberships_write',
    'Admins can insert pilots',
    'vep_opportunities_insert_admin',
    'trello_import_log_admin',
    'data_quality_audit_snapshots_write_mgmt',
    'ingestion_remediation_escalation_write_mgmt',
    'ingestion_source_controls_read_mgmt',
    'ingestion_source_controls_write_mgmt',
    'ingestion_source_sla_write_mgmt',
    'tribe_continuity_overrides_write_mgmt',
    'tribe_lineage_write_mgmt',
    'release_readiness_policies_write_mgmt',
    'webinars_insert_v2',
  ];

  for (const policy of manageMember) {
    await t.test(`${policy}: uses rls_can('manage_member')`, () => {
      const idx = sql.indexOf(`CREATE POLICY "${policy}"`);
      assert.ok(idx >= 0, `Policy ${policy} must be created`);
      const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
      assert.match(block, /rls_can\('manage_member'\)/);
    });
  }

  // ───────── Category C: Admin + chapter_liaison/sponsor → + manage_partner ─────────
  const managePartnerTables = [
    'data_quality_audit_snapshots_read_mgmt',
    'ingestion_remediation_escalation_read_mgmt',
    'ingestion_source_sla_read_mgmt',
    'release_readiness_policies_read_mgmt',
  ];

  for (const policy of managePartnerTables) {
    await t.test(`${policy}: includes rls_can('manage_partner')`, () => {
      const idx = sql.indexOf(`CREATE POLICY "${policy}"`);
      assert.ok(idx >= 0, `Policy ${policy} must be created`);
      const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
      assert.match(block, /rls_can\('manage_member'\)/);
      assert.match(block, /rls_can\('manage_partner'\)/);
    });
  }

  // ───────── Category D + E + F: Leader-level → write ─────────
  const writeLevel = [
    'assignments_write_leaders',
    'checklists_write_leaders',
    'tag_assignments_write_leaders',
    'audience_rules_manage_leaders',
    'invited_manage_leaders',
    'event_tags_manage_leaders',
    'board_lifecycle_events_read_mgmt',
    'board_lifecycle_events_write_mgmt',
    'templates_select',
  ];

  for (const policy of writeLevel) {
    await t.test(`${policy}: uses rls_can('write')`, () => {
      const idx = sql.indexOf(`CREATE POLICY "${policy}"`);
      assert.ok(idx >= 0, `Policy ${policy} must be created`);
      const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
      assert.match(block, /rls_can\('write'\)/);
    });
  }

  // ───────── Category G: Tribe-scoped ─────────
  await t.test('broadcast_log_read_tribe_leader: uses rls_can_for_tribe', () => {
    const idx = sql.indexOf('CREATE POLICY "broadcast_log_read_tribe_leader"');
    const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
    assert.match(block, /rls_can_for_tribe\('write', broadcast_log\.tribe_id\)/);
  });

  await t.test('meeting_artifacts_manage: uses rls_can_for_tribe', () => {
    const idx = sql.indexOf('CREATE POLICY "meeting_artifacts_manage"');
    const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
    assert.match(block, /rls_can_for_tribe\('write', meeting_artifacts\.tribe_id\)/);
  });

  await t.test('meeting_artifacts_select: includes is_published + write gate', () => {
    const idx = sql.indexOf('CREATE POLICY "meeting_artifacts_select"');
    const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
    assert.match(block, /is_published = true/);
    assert.match(block, /rls_can\('write'\)/);
  });

  await t.test('members_select_tribe_leader: uses rls_can_for_tribe', () => {
    const idx = sql.indexOf('CREATE POLICY "members_select_tribe_leader"');
    const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
    assert.match(block, /rls_can_for_tribe\('write', members\.tribe_id\)/);
  });

  // ───────── Category H + I: Sponsor / Stakeholder ─────────
  await t.test('cr_approvals_insert_sponsors: uses rls_can(\'manage_partner\')', () => {
    const idx = sql.indexOf('CREATE POLICY "cr_approvals_insert_sponsors"');
    const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
    assert.match(block, /rls_can\('manage_partner'\)/);
  });

  await t.test('members_select_stakeholder: uses rls_can(\'manage_partner\')', () => {
    const idx = sql.indexOf('CREATE POLICY "members_select_stakeholder"');
    const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
    assert.match(block, /rls_can\('manage_partner'\)/);
  });

  // ───────── Category J: Curation ─────────
  await t.test('curation_review_log_write: uses write_board', () => {
    const idx = sql.indexOf('CREATE POLICY "curation_review_log_write"');
    const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
    assert.match(block, /rls_can\('manage_member'\)/);
    assert.match(block, /rls_can\('write_board'\)/);
  });

  // ───────── Category K: Selection ─────────
  const selectionPolicies = [
    'admin_read_membership_snapshots',
    'admin_read_selection_rankings',
  ];

  for (const policy of selectionPolicies) {
    await t.test(`${policy}: covers manage_member + manage_partner + write_board`, () => {
      const idx = sql.indexOf(`CREATE POLICY "${policy}"`);
      const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
      assert.match(block, /rls_can\('manage_member'\)/);
      assert.match(block, /rls_can\('manage_partner'\)/);
      assert.match(block, /rls_can\('write_board'\)/);
    });
  }

  // ───────── Category L: Comms (comms_member preserved inline) ─────────
  await t.test('comms_media_items_read: preserves comms_member designation check', () => {
    const idx = sql.indexOf('CREATE POLICY "comms_media_items_read"');
    const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
    assert.match(block, /rls_can\('write'\)/);
    assert.match(block, /'comms_member' = ANY/);
  });

  await t.test('comms_media_items_write: uses rls_can(\'write\') (no comms_member)', () => {
    const idx = sql.indexOf('CREATE POLICY "comms_media_items_write"');
    const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
    assert.match(block, /rls_can\('write'\)/);
  });

  await t.test('comms_metrics_admin_read: preserves comms_member', () => {
    const idx = sql.indexOf('CREATE POLICY "comms_metrics_admin_read"');
    const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
    assert.match(block, /rls_can\('write'\)/);
    assert.match(block, /'comms_member' = ANY/);
  });

  // ───────── Category M: Webinars UPDATE ─────────
  await t.test('webinars_update_v2: preserves organizer/co_manager check', () => {
    const idx = sql.indexOf('CREATE POLICY "webinars_update_v2"');
    const block = sql.substring(idx, sql.indexOf(';', idx) + 1);
    assert.match(block, /rls_can\('manage_member'\)/);
    assert.match(block, /organizer_id = \(SELECT m\.id FROM public\.members m/);
    assert.match(block, /= ANY\(webinars\.co_manager_ids\)/);
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Migration invariants
// ═══════════════════════════════════════════════════════════════════════════
test('Fase 4.1 migration invariants', async (t) => {
  const sql = findMigration('v4_phase4_1_rls_legacy_policies');

  await t.test('NOTIFY pgrst present', () => {
    assert.match(sql, /NOTIFY pgrst, 'reload schema'/);
  });

  await t.test('BEGIN + COMMIT wrap', () => {
    assert.match(sql, /^\s*BEGIN;/m);
    assert.match(sql, /^\s*COMMIT;/m);
  });

  await t.test('Rollback block preserved in comments', () => {
    assert.match(sql, /ROLLBACK: Original policy definitions/i);
    assert.match(sql, /CATEGORY A: Superadmin-only/);
    assert.match(sql, /CATEGORY G: Tribe-scoped/);
  });

  await t.test('No CREATE POLICY block references operational_role directly', () => {
    // Match non-comment CREATE POLICY blocks (exclude rollback block inside /* ... */)
    const rollbackStart = sql.indexOf('-- ROLLBACK:');
    const activeSql = rollbackStart > 0 ? sql.substring(0, rollbackStart) : sql;
    const policyBlocks = activeSql.match(/CREATE POLICY[\s\S]*?;/g) || [];
    assert.ok(policyBlocks.length >= 42, `Expected ≥42 CREATE POLICY blocks, got ${policyBlocks.length}`);
    for (const block of policyBlocks) {
      assert.doesNotMatch(block, /operational_role/,
        `Policy should not reference operational_role: ${block.substring(0, 100)}`);
    }
  });

  await t.test('Expected count: 42 DROP + ≥42 CREATE pairs', () => {
    const rollbackStart = sql.indexOf('-- ROLLBACK:');
    const activeSql = rollbackStart > 0 ? sql.substring(0, rollbackStart) : sql;
    const drops = activeSql.match(/DROP POLICY IF EXISTS/g) || [];
    const creates = activeSql.match(/CREATE POLICY/g) || [];
    assert.ok(drops.length >= 42, `Expected ≥42 DROPs, got ${drops.length}`);
    assert.ok(creates.length >= 42, `Expected ≥42 CREATEs, got ${creates.length}`);
  });
});
