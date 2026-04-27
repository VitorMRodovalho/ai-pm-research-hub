import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

// We test the permission logic directly
import {
  hasPermission,
  setSimulation,
  clearSimulation,
  getEffectivePermissions,
  TIER_PERMISSIONS,
  DESIGNATION_PERMISSIONS,
  TIER_LABELS,
  DESIGNATION_LABELS,
} from '../src/lib/permissions.ts';

// ── Types sanity ──
describe('permissions types', () => {
  it('all 11 tiers defined', () => {
    assert.equal(Object.keys(TIER_PERMISSIONS).length, 11);
  });

  it('all 8 designations defined', () => {
    assert.equal(Object.keys(DESIGNATION_PERMISSIONS).length, 8);
  });

  it('tier labels cover all tiers', () => {
    for (const tier of Object.keys(TIER_PERMISSIONS)) {
      assert.ok(TIER_LABELS[tier], `Missing label for tier: ${tier}`);
      assert.ok(TIER_LABELS[tier].pt, `Missing pt label for tier: ${tier}`);
    }
  });

  it('designation labels cover all designations', () => {
    for (const d of Object.keys(DESIGNATION_PERMISSIONS)) {
      assert.ok(DESIGNATION_LABELS[d], `Missing label for designation: ${d}`);
    }
  });
});

// ── hasPermission real mode ──
describe('hasPermission (real mode)', () => {
  it('superadmin has all permissions', () => {
    const member = { is_superadmin: true, operational_role: 'guest' };
    assert.ok(hasPermission(member, 'admin.access'));
    assert.ok(hasPermission(member, 'system.global_config'));
    assert.ok(hasPermission(member, 'board.delete_item'));
  });

  it('manager has admin.access', () => {
    const member = { operational_role: 'manager' };
    assert.ok(hasPermission(member, 'admin.access'));
    assert.ok(hasPermission(member, 'admin.analytics'));
  });

  it('researcher does NOT have admin.access', () => {
    const member = { operational_role: 'researcher' };
    assert.ok(!hasPermission(member, 'admin.access'));
  });

  it('researcher has board.view_own_tribe', () => {
    const member = { operational_role: 'researcher' };
    assert.ok(hasPermission(member, 'board.view_own_tribe'));
  });

  it('visitor has NO permissions', () => {
    const member = { operational_role: 'visitor' };
    assert.ok(!hasPermission(member, 'admin.access'));
    assert.ok(!hasPermission(member, 'workspace.access'));
    assert.ok(!hasPermission(member, 'board.view_own_tribe'));
  });

  it('designation adds permissions: researcher + curator gets admin.curation', () => {
    const member = { operational_role: 'researcher', designations: ['curator'] };
    assert.ok(hasPermission(member, 'admin.curation'));
    assert.ok(hasPermission(member, 'content.curate'));
  });

  it('curator gets admin.governance.view (governance dashboard access) without admin.access', () => {
    // Bug A (p65): curator needs to see Governança item in admin sidebar to read
    // pending IP ratification chains, signoffs status, comments — without relying
    // on email magic links. admin.governance.view is the surgical gate.
    const member = { operational_role: 'researcher', designations: ['curator'] };
    assert.ok(hasPermission(member, 'admin.governance.view'),
      'curator must have admin.governance.view (Bug A — Sarah governance flow)');
    assert.ok(!hasPermission(member, 'admin.access'),
      'curator must NOT have admin.access (would expose admin-only items)');
  });

  it('manager has admin.governance.view (preserves access after gate switch)', () => {
    const member = { operational_role: 'manager' };
    assert.ok(hasPermission(member, 'admin.governance.view'));
  });

  it('deputy_manager designation adds admin.access to tribe_leader', () => {
    const member = { operational_role: 'tribe_leader', designations: ['deputy_manager'] };
    assert.ok(hasPermission(member, 'admin.access'));
    assert.ok(hasPermission(member, 'admin.analytics'));
    assert.ok(hasPermission(member, 'admin.governance.view'));
  });
});

// ── hasPermission simulation mode ──
describe('hasPermission (simulation mode)', () => {
  it('simulation overrides real permissions', () => {
    const member = { is_superadmin: true, operational_role: 'manager' };

    // Before simulation: superadmin has everything
    assert.ok(hasPermission(member, 'admin.access'));

    // Start simulation as visitor
    setSimulation({ active: true, tier: 'visitor', designations: [], tribe_id: null });
    assert.ok(!hasPermission(member, 'admin.access'));
    assert.ok(!hasPermission(member, 'workspace.access'));

    clearSimulation();
  });

  it('simulation as researcher shows correct permissions', () => {
    const member = { is_superadmin: true, operational_role: 'manager' };

    setSimulation({ active: true, tier: 'researcher', designations: [], tribe_id: 3 });
    assert.ok(!hasPermission(member, 'admin.access'));
    assert.ok(hasPermission(member, 'workspace.access'));
    assert.ok(hasPermission(member, 'board.view_own_tribe'));
    assert.ok(!hasPermission(member, 'board.view_all'));

    clearSimulation();
  });

  it('simulation with designation adds permissions', () => {
    const member = { is_superadmin: true, operational_role: 'manager' };

    setSimulation({ active: true, tier: 'researcher', designations: ['curator'], tribe_id: null });
    assert.ok(hasPermission(member, 'admin.curation'));
    assert.ok(hasPermission(member, 'content.curate'));
    assert.ok(!hasPermission(member, 'admin.access'));

    clearSimulation();
  });
});

// ── getEffectivePermissions ──
describe('getEffectivePermissions', () => {
  it('returns correct count for researcher', () => {
    const member = { operational_role: 'researcher' };
    const perms = getEffectivePermissions(member);
    assert.ok(perms.length > 0);
    assert.ok(perms.includes('workspace.access'));
    assert.ok(!perms.includes('admin.access'));
  });

  it('superadmin gets all unique permissions', () => {
    const member = { is_superadmin: true, operational_role: 'guest' };
    const perms = getEffectivePermissions(member);
    // Should have no duplicates
    assert.equal(perms.length, new Set(perms).size);
    assert.ok(perms.length > 30);
  });
});
