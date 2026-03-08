import test from 'node:test';
import assert from 'node:assert/strict';
import {
  getAccessTier,
  resolveTierFromMember,
  hasMinimumTier,
  canAccessAdminRoute,
} from '../src/lib/admin/constants.ts';

test('getAccessTier resolves expected tier matrix', () => {
  assert.equal(getAccessTier(true, 'guest', []), 'superadmin');
  assert.equal(getAccessTier(false, 'manager', []), 'admin');
  assert.equal(getAccessTier(false, 'deputy_manager', []), 'admin');
  assert.equal(getAccessTier(false, 'guest', ['co_gp']), 'admin');
  assert.equal(getAccessTier(false, 'tribe_leader', []), 'leader');
  assert.equal(getAccessTier(false, 'guest', ['sponsor']), 'observer');
  assert.equal(getAccessTier(false, 'researcher', []), 'member');
  assert.equal(getAccessTier(false, 'guest', []), 'visitor');
});

test('resolveTierFromMember uses member payload safely', () => {
  assert.equal(resolveTierFromMember(null), 'visitor');
  assert.equal(resolveTierFromMember({}), 'visitor');
  assert.equal(resolveTierFromMember({ is_superadmin: true }), 'superadmin');
  assert.equal(resolveTierFromMember({ operational_role: 'tribe_leader', designations: [] }), 'leader');
});

test('hasMinimumTier respects ordered hierarchy', () => {
  assert.equal(hasMinimumTier('admin', 'observer'), true);
  assert.equal(hasMinimumTier('leader', 'admin'), false);
  assert.equal(hasMinimumTier('superadmin', 'admin'), true);
  assert.equal(hasMinimumTier('member', 'member'), true);
});

test('canAccessAdminRoute enforces route-level minimum tiers', () => {
  const superadmin = { is_superadmin: true, operational_role: 'guest', designations: [] };
  const admin = { is_superadmin: false, operational_role: 'manager', designations: [] };
  const leader = { is_superadmin: false, operational_role: 'tribe_leader', designations: [] };
  const observer = { is_superadmin: false, operational_role: 'guest', designations: ['sponsor'] };
  const member = { is_superadmin: false, operational_role: 'researcher', designations: [] };

  assert.equal(canAccessAdminRoute(superadmin, 'admin_member_edit'), true);
  assert.equal(canAccessAdminRoute(admin, 'admin_analytics'), true);
  assert.equal(canAccessAdminRoute(admin, 'admin_manage_actions'), true);
  assert.equal(canAccessAdminRoute(leader, 'admin_manage_actions'), false);
  assert.equal(canAccessAdminRoute(observer, 'admin_panel'), true);
  assert.equal(canAccessAdminRoute(member, 'admin_panel'), false);
  assert.equal(canAccessAdminRoute(member, 'admin_analytics'), false);
});

