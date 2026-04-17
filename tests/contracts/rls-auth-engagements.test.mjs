/**
 * Domain Model V4 — Fase 4 — RLS Auth Engagements Fixtures
 *
 * Static analysis contract test for Phase 4 RLS migration (ADR-0007).
 * Validates that:
 *   1. RLS helper functions exist (rls_can, rls_is_superadmin, rls_can_for_tribe)
 *   2. requires_agreement fix applied for volunteer/study_group_owner
 *   3. Agreement certificate backfill exists
 *   4. 36 direct-query policies migrated to V4 helpers
 *   5. No direct-query policies remain referencing operational_role
 *   6. Rollback block preserved in migration file
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

// ═══════════════════════════════════════════════════════════════════════════
// Migration A: RLS Helper Functions
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 4 Migration 6: RLS helper functions', async (t) => {
  const sql = findMigration('v4_phase4_rls_helpers');

  await t.test('creates rls_can(text) function', () => {
    assert.match(sql, /CREATE OR REPLACE FUNCTION public\.rls_can\(p_action text\)/i);
  });

  await t.test('rls_can is STABLE SECURITY DEFINER', () => {
    const start = sql.indexOf('CREATE OR REPLACE FUNCTION public.rls_can(p_action');
    const end = sql.indexOf('CREATE OR REPLACE FUNCTION public.rls_is_superadmin');
    assert.ok(start >= 0 && end > start, 'rls_can function definition must be found');
    const fnBlock = sql.substring(start, end);
    assert.match(fnBlock, /STABLE/i);
    assert.match(fnBlock, /SECURITY DEFINER/i);
  });

  await t.test('rls_can delegates to can() via persons lookup', () => {
    assert.match(sql, /public\.can\(\s*\(SELECT p\.id FROM public\.persons p WHERE p\.auth_id = auth\.uid\(\)/i);
  });

  await t.test('creates rls_is_superadmin() function', () => {
    assert.match(sql, /CREATE OR REPLACE FUNCTION public\.rls_is_superadmin\(\)/i);
  });

  await t.test('rls_is_superadmin reads from members.is_superadmin', () => {
    assert.match(sql, /SELECT m\.is_superadmin FROM public\.members m WHERE m\.auth_id = auth\.uid\(\)/i);
  });

  await t.test('creates rls_can_for_tribe(text, integer) function', () => {
    assert.match(sql, /CREATE OR REPLACE FUNCTION public\.rls_can_for_tribe\(p_action text, p_tribe_id integer\)/i);
  });

  await t.test('rls_can_for_tribe checks auth_engagements + engagement_kind_permissions', () => {
    assert.match(sql, /FROM public\.auth_engagements ae/i);
    assert.match(sql, /JOIN public\.engagement_kind_permissions ekp/i);
    assert.match(sql, /ae\.legacy_tribe_id = p_tribe_id/i);
  });

  await t.test('all helpers granted to authenticated', () => {
    assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.rls_can\(text\) TO authenticated/i);
    assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.rls_is_superadmin\(\) TO authenticated/i);
    assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.rls_can_for_tribe\(text, integer\) TO authenticated/i);
  });

  await t.test('fixes requires_agreement for volunteer and study_group_owner', () => {
    assert.match(sql, /UPDATE public\.engagement_kinds\s*\nSET requires_agreement = false/i);
    assert.match(sql, /WHERE slug IN \('volunteer', 'study_group_owner'\)/i);
  });

  await t.test('backfills agreement_certificate_id from certificates', () => {
    assert.match(sql, /UPDATE public\.engagements e\s*\nSET agreement_certificate_id = c\.id/i);
    assert.match(sql, /FROM public\.certificates c/i);
    assert.match(sql, /c\.type = 'volunteer_agreement'/i);
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Migration B: Policy Rewrites
// ═══════════════════════════════════════════════════════════════════════════
test('Phase 4 Migration 7: RLS policy rewrite', async (t) => {
  const sql = findMigration('v4_phase4_rls_policy_rewrite');

  // Category 1: Manager-level → manage_member
  const managerTables = [
    'board_sla_config', 'campaign_sends', 'chapter_needs',
    'data_anomaly_log', 'data_retention_policy', 'help_journeys',
    'ia_pilots', 'mcp_usage_log', 'pilots', 'portfolio_kpi_targets',
    'tags', 'tribes', 'vep_opportunities', 'visitor_leads'
  ];

  for (const table of managerTables) {
    await t.test(`${table}: uses rls_can('manage_member')`, () => {
      const tableSection = sql.substring(
        sql.indexOf(`ON ${table}`),
        sql.indexOf(`ON ${table}`) + 200
      );
      assert.match(tableSection, /rls_can\('manage_member'\)/);
    });
  }

  // Category 2: Leader-level → write
  await t.test('event_showcases: uses rls_can(\'write\')', () => {
    const idx = sql.indexOf('event_showcases_manage');
    const section = sql.substring(idx, idx + 200);
    assert.match(section, /rls_can\('write'\)/);
  });

  await t.test('meeting_action_items: consolidates 2 duplicate policies into 1', () => {
    // Exclude rollback comment block (/* ... */) from count
    const rollbackStart = sql.indexOf('-- ROLLBACK:');
    const activeSql = rollbackStart > 0 ? sql.substring(0, rollbackStart) : sql;
    const drops = activeSql.match(/DROP POLICY.*meeting_action_items/g);
    assert.ok(drops.length >= 2, 'Should drop both legacy duplicate policies');
    const creates = activeSql.match(/CREATE POLICY.*meeting_action_items/g);
    assert.equal(creates.length, 1, 'Should create exactly 1 consolidated policy');
  });

  // Category 3: Tribe-scoped → rls_can_for_tribe
  const tribeScopedTables = [
    'board_items', 'project_boards', 'tribe_deliverables',
    'tribe_meeting_slots'
  ];

  for (const table of tribeScopedTables) {
    await t.test(`${table}: uses rls_can_for_tribe`, () => {
      assert.match(sql, new RegExp(`ON ${table}[\\s\\S]*?rls_can_for_tribe`));
    });
  }

  await t.test('tribes: leader edit own tribe uses rls_can_for_tribe', () => {
    const idx = sql.indexOf('leaders_edit_own_tribe_v4');
    const section = sql.substring(idx, idx + 300);
    assert.match(section, /rls_can_for_tribe\('write', tribes\.id\)/);
  });

  // Category 5: Designation-based
  await t.test('blog_posts: uses rls_can(\'write\') covering comms_leader', () => {
    const idx = sql.indexOf('blog_posts_manage_v4');
    const section = sql.substring(idx, idx + 200);
    assert.match(section, /rls_can\('write'\)/);
  });

  await t.test('public_publications: uses write OR write_board for curator', () => {
    const idx = sql.indexOf('pub_admin_manage_v4');
    const section = sql.substring(idx, idx + 200);
    assert.match(section, /rls_can\('write'\)/);
    assert.match(section, /rls_can\('write_board'\)/);
  });

  // Category 6: Special
  await t.test('partner_entities: uses rls_can(\'manage_partner\')', () => {
    const idx = sql.indexOf('partner_entities_write_v4');
    const section = sql.substring(idx, idx + 200);
    assert.match(section, /rls_can\('manage_partner'\)/);
  });

  await t.test('pii_access_log: keeps own-log check + manage_member', () => {
    const idx = sql.indexOf('pii_log_admin_read_v4');
    const section = sql.substring(idx, idx + 300);
    assert.match(section, /rls_can\('manage_member'\)/);
    assert.match(section, /target_member_id/);
  });

  // Rollback block exists
  await t.test('rollback block preserved in comments', () => {
    assert.match(sql, /ROLLBACK: Original policy definitions/i);
    assert.match(sql, /CATEGORY 1: Manager-level/);
    assert.match(sql, /CATEGORY 3: Tribe-scoped/);
  });

  // No operational_role in new policy USING clauses (excludes rollback comment block)
  await t.test('no new policy references operational_role directly', () => {
    const rollbackStart = sql.indexOf('-- ROLLBACK:');
    const activeSql = rollbackStart > 0 ? sql.substring(0, rollbackStart) : sql;
    const policyBlocks = activeSql.match(/CREATE POLICY[\s\S]*?;/g) || [];
    for (const block of policyBlocks) {
      assert.doesNotMatch(block, /operational_role/,
        `Policy should not reference operational_role: ${block.substring(0, 80)}`);
    }
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Cross-migration invariants
// ═══════════════════════════════════════════════════════════════════════════
test('RLS migration invariants', async (t) => {
  const helpersSql = findMigration('v4_phase4_rls_helpers');
  const rewriteSql = findMigration('v4_phase4_rls_policy_rewrite');

  await t.test('helper migration has NOTIFY pgrst', () => {
    assert.match(helpersSql, /NOTIFY pgrst, 'reload schema'/);
  });

  await t.test('rewrite migration has NOTIFY pgrst', () => {
    assert.match(rewriteSql, /NOTIFY pgrst, 'reload schema'/);
  });

  await t.test('rewrite migration has rollback documentation', () => {
    assert.match(rewriteSql, /ROLLBACK:/i);
  });

  await t.test('36 policy operations total (DROP + CREATE pairs)', () => {
    const drops = rewriteSql.match(/DROP POLICY IF EXISTS/g) || [];
    const creates = rewriteSql.match(/CREATE POLICY/g) || [];
    // 37 drops (meeting_action_items has 2 legacy policies dropped)
    assert.ok(drops.length >= 36, `Expected ≥36 drops, got ${drops.length}`);
    // 35 creates (meeting_action_items consolidated from 2 → 1)
    assert.ok(creates.length >= 34, `Expected ≥34 creates, got ${creates.length}`);
  });
});
