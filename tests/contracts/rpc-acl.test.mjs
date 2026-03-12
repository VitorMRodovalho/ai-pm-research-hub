/**
 * W96 Contract Test: RPC ACL
 * Validates that LGPD-sensitive RPCs have proper tier checks in their SQL definitions.
 * This is a static analysis test — it reads the migration files and verifies
 * that the RPCs include appropriate permission guards.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

// Load all migration SQL files
function loadAllMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => ({
    name: f,
    content: readFileSync(join(MIGRATIONS_DIR, f), 'utf8'),
  }));
}

const migrations = loadAllMigrations();
const allSQL = migrations.map(m => m.content).join('\n');

// Helper: find the SQL body of a function definition
function findFunctionBody(funcName) {
  // Match CREATE OR REPLACE FUNCTION public.funcName(...) ... $$ body $$;
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?\\$\\$([\\s\\S]*?)\\$\\$`,
    'gi'
  );
  const matches = [...allSQL.matchAll(regex)];
  if (matches.length === 0) return null;
  // Return the last definition (most recent CREATE OR REPLACE)
  return matches[matches.length - 1][1];
}

// ─── LGPD-sensitive RPCs must have tier checks ───

const LGPD_RPCS = [
  'admin_get_member_details',
  'admin_list_members_with_pii',
];

for (const rpcName of LGPD_RPCS) {
  test(`RPC ${rpcName} exists and is SECURITY DEFINER`, () => {
    const body = findFunctionBody(rpcName);
    assert.ok(body, `RPC ${rpcName} not found in migrations`);

    // Check it's SECURITY DEFINER (bypasses RLS, so MUST have internal checks)
    const funcDef = allSQL.match(new RegExp(`${rpcName}[\\s\\S]*?SECURITY\\s+DEFINER`, 'i'));
    assert.ok(funcDef, `RPC ${rpcName} must be SECURITY DEFINER`);
  });

  test(`RPC ${rpcName} checks caller tier before returning data`, () => {
    const body = findFunctionBody(rpcName);
    assert.ok(body, `RPC ${rpcName} not found`);

    // Must check is_superadmin or operational_role
    const checksAdmin = /is_superadmin\s*=\s*true/i.test(body) || /operational_role\s+IN\s*\(/i.test(body);
    assert.ok(checksAdmin, `RPC ${rpcName} must check admin tier (is_superadmin or operational_role)`);

    // Must raise exception on unauthorized access
    const raisesException = /RAISE\s+EXCEPTION/i.test(body);
    assert.ok(raisesException, `RPC ${rpcName} must RAISE EXCEPTION on unauthorized access`);
  });

  test(`RPC ${rpcName} denies non-admin callers (has explicit tier gate)`, () => {
    const body = findFunctionBody(rpcName);
    assert.ok(body);

    // Must have a pattern like: IF NOT (...admin check...) THEN RAISE EXCEPTION
    const hasGate = /IF\s+NOT\s*\(/i.test(body) && /RAISE\s+EXCEPTION\s+'Access denied/i.test(body);
    assert.ok(hasGate, `RPC ${rpcName} must have explicit IF NOT (admin) THEN RAISE EXCEPTION gate`);
  });
}

// ─── Curation RPCs must have designation checks ───

const CURATION_RPCS = [
  'submit_curation_review',
  'assign_curation_reviewer',
  'get_curation_dashboard',
];

for (const rpcName of CURATION_RPCS) {
  test(`Curation RPC ${rpcName} checks curator/manager designation`, () => {
    const body = findFunctionBody(rpcName);
    assert.ok(body, `RPC ${rpcName} not found in migrations`);

    const checksCurator = /curator/i.test(body) || /designations/i.test(body);
    const checksRole = /operational_role/i.test(body) || /is_superadmin/i.test(body);
    assert.ok(checksCurator || checksRole,
      `RPC ${rpcName} must check curator designation or admin role`);

    const raisesException = /RAISE\s+EXCEPTION/i.test(body);
    assert.ok(raisesException, `RPC ${rpcName} must RAISE EXCEPTION on unauthorized access`);
  });
}

// ─── Assignment RPCs must have permission checks ───

const ASSIGNMENT_RPCS = [
  'assign_member_to_item',
  'unassign_member_from_item',
];

for (const rpcName of ASSIGNMENT_RPCS) {
  test(`Assignment RPC ${rpcName} requires tribe_leader or manager`, () => {
    const body = findFunctionBody(rpcName);
    assert.ok(body, `RPC ${rpcName} not found`);

    const checksRole = /tribe_leader|manager|deputy_manager/i.test(body);
    assert.ok(checksRole, `RPC ${rpcName} must check tribe_leader/manager role`);

    const raisesException = /RAISE\s+EXCEPTION/i.test(body);
    assert.ok(raisesException, `RPC ${rpcName} must RAISE EXCEPTION on unauthorized access`);
  });
}

// ─── Members table must have RLS enabled ───

test('members table has RLS enabled', () => {
  const hasRLS = /ALTER\s+TABLE\s+(?:public\.)?members\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i.test(allSQL);
  assert.ok(hasRLS, 'members table must have RLS enabled in migrations');
});

// ─── Members policies exist ───

test('members table has SELECT policies for own/admin/tribe_leader', () => {
  const hasOwnPolicy = /members_select_own/i.test(allSQL);
  const hasAdminPolicy = /members_select_admin/i.test(allSQL);
  const hasTribePolicy = /members_select_tribe_leader/i.test(allSQL);
  assert.ok(hasOwnPolicy, 'members must have members_select_own policy');
  assert.ok(hasAdminPolicy, 'members must have members_select_admin policy');
  assert.ok(hasTribePolicy, 'members must have members_select_tribe_leader policy');
});

// ─── get_board_members does NOT expose PII ───

test('get_board_members returns only safe fields (no email/phone)', () => {
  const body = findFunctionBody('get_board_members');
  assert.ok(body, 'get_board_members not found');

  const hasEmail = /\.email/i.test(body);
  const hasPhone = /\.phone/i.test(body);
  assert.equal(hasEmail, false, 'get_board_members must NOT return email');
  assert.equal(hasPhone, false, 'get_board_members must NOT return phone');
});

// ─── Junction tables have RLS ───

test('board_item_assignments has RLS enabled', () => {
  const has = /ALTER\s+TABLE\s+board_item_assignments\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i.test(allSQL);
  assert.ok(has, 'board_item_assignments must have RLS enabled');
});

test('board_sla_config has RLS enabled', () => {
  const has = /ALTER\s+TABLE\s+board_sla_config\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i.test(allSQL);
  assert.ok(has, 'board_sla_config must have RLS enabled');
});
