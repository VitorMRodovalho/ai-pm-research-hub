/**
 * W96 Contract Test: Route ACL
 * Validates that every route in navigation.config.ts respects its minTier
 * and lgpdSensitive flag for all tier levels.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const NAV_CONFIG = readFileSync(resolve(ROOT, 'src/lib/navigation.config.ts'), 'utf8');

const TIER_RANK = {
  visitor: 0,
  member: 1,
  observer: 2,
  leader: 3,
  admin: 4,
  superadmin: 5,
};

const ALL_TIERS = Object.keys(TIER_RANK);

function extractItemBlock(key) {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(`\\{\\s*key:\\s*'${escaped}'[\\s\\S]*?\\}`, 'm');
  const match = NAV_CONFIG.match(regex);
  if (!match) throw new Error(`Nav item not found: ${key}`);
  return match[0];
}

function readStringProp(block, name) {
  const match = block.match(new RegExp(`${name}:\\s*'([^']+)'`));
  return match ? match[1] : '';
}

function readBooleanProp(block, name, fallback = false) {
  const match = block.match(new RegExp(`${name}:\\s*(true|false)`));
  return match ? match[1] === 'true' : fallback;
}

function readArrayProp(block, name) {
  const match = block.match(new RegExp(`${name}:\\s*\\[([^\\]]*)\\]`));
  if (!match) return [];
  return match[1].split(',').map(e => e.trim().replace(/^'|'$/g, '')).filter(Boolean);
}

function parseNavItem(key) {
  const block = extractItemBlock(key);
  return {
    key,
    href: readStringProp(block, 'href'),
    minTier: readStringProp(block, 'minTier'),
    requiresAuth: readBooleanProp(block, 'requiresAuth'),
    lgpdSensitive: readBooleanProp(block, 'lgpdSensitive'),
    allowedDesignations: readArrayProp(block, 'allowedDesignations'),
    allowedOperationalRoles: readArrayProp(block, 'allowedOperationalRoles'),
  };
}

function canAccess(item, profile) {
  if (item.requiresAuth && !profile.isLoggedIn) return false;
  const meetsMinTier = TIER_RANK[profile.tier] >= TIER_RANK[item.minTier];
  const hasDesig = item.allowedDesignations.some(d => profile.designations.includes(d));
  const hasOpRole = item.allowedOperationalRoles.includes(profile.operationalRole || '');
  const enabled = meetsMinTier || hasDesig || hasOpRole;
  if (item.lgpdSensitive && !enabled) return false;
  return enabled;
}

// Extract all nav item keys from config
const navItemKeys = [...NAV_CONFIG.matchAll(/key:\s*'([^']+)'/g)].map(m => m[1]);

// ─── Auth-required routes must deny unauthenticated access ───

test('all auth-required routes deny unauthenticated visitors', () => {
  const unauthenticatedVisitor = { tier: 'visitor', isLoggedIn: false, designations: [], operationalRole: '' };
  for (const key of navItemKeys) {
    const item = parseNavItem(key);
    if (item.requiresAuth) {
      assert.equal(canAccess(item, unauthenticatedVisitor), false,
        `Route ${key} (${item.href}) should deny unauthenticated visitors`);
    }
  }
});

// ─── LGPD-sensitive routes must be invisible to low-tier users ───

test('LGPD-sensitive routes are inaccessible to researchers', () => {
  const researcher = { tier: 'member', isLoggedIn: true, designations: [], operationalRole: 'researcher' };
  const lgpdRoutes = navItemKeys.map(parseNavItem).filter(i => i.lgpdSensitive);
  assert.ok(lgpdRoutes.length >= 3, `Expected ≥3 LGPD routes, found ${lgpdRoutes.length}`);
  for (const item of lgpdRoutes) {
    assert.equal(canAccess(item, researcher), false,
      `LGPD route ${item.key} (${item.href}) should deny researcher tier`);
  }
});

test('LGPD-sensitive routes are inaccessible to tribe leaders without designation', () => {
  const leader = { tier: 'leader', isLoggedIn: true, designations: [], operationalRole: 'tribe_leader' };
  const lgpdRoutes = navItemKeys.map(parseNavItem).filter(i => i.lgpdSensitive);
  for (const item of lgpdRoutes) {
    assert.equal(canAccess(item, leader), false,
      `LGPD route ${item.key} should deny tribe_leader without designation`);
  }
});

test('LGPD-sensitive routes are accessible to admin tier', () => {
  const admin = { tier: 'admin', isLoggedIn: true, designations: [], operationalRole: 'manager' };
  const lgpdRoutes = navItemKeys.map(parseNavItem).filter(i => i.lgpdSensitive);
  for (const item of lgpdRoutes) {
    assert.equal(canAccess(item, admin), true,
      `LGPD route ${item.key} should allow admin tier`);
  }
});

// ─── Every route respects its declared minTier ───

test('every route with minTier blocks users below that tier (without qualifying designation)', () => {
  for (const key of navItemKeys) {
    const item = parseNavItem(key);
    if (!item.requiresAuth) continue; // skip public routes

    const minRank = TIER_RANK[item.minTier];
    // Test all tiers below minTier
    for (const tier of ALL_TIERS) {
      if (TIER_RANK[tier] >= minRank) continue;
      const profile = { tier, isLoggedIn: true, designations: [], operationalRole: '' };
      // Should be denied (unless they have a qualifying designation/role, which we don't provide)
      assert.equal(canAccess(item, profile), false,
        `Route ${key} (minTier=${item.minTier}) should deny tier=${tier}`);
    }
  }
});

// ─── Specific LGPD route checks ───

test('admin/selection requires admin tier and is LGPD-sensitive', () => {
  const item = parseNavItem('admin-selection');
  assert.equal(item.minTier, 'admin');
  assert.equal(item.lgpdSensitive, true);
  assert.equal(item.requiresAuth, true);
});

test('admin/comms requires admin tier and is LGPD-sensitive', () => {
  const item = parseNavItem('admin-comms');
  assert.equal(item.minTier, 'admin');
  assert.equal(item.lgpdSensitive, true);
  assert.equal(item.requiresAuth, true);
});

test('admin/comms-ops requires admin tier and is LGPD-sensitive', () => {
  const item = parseNavItem('admin-comms-ops');
  assert.equal(item.minTier, 'admin');
  assert.equal(item.lgpdSensitive, true);
  assert.equal(item.requiresAuth, true);
});

test('admin/settings requires superadmin', () => {
  const item = parseNavItem('admin-settings');
  assert.equal(item.minTier, 'superadmin');
  const admin = { tier: 'admin', isLoggedIn: true, designations: [], operationalRole: 'manager' };
  assert.equal(canAccess(item, admin), false, 'admin/settings should deny non-superadmin');
  const superadmin = { tier: 'superadmin', isLoggedIn: true, designations: [], operationalRole: 'manager' };
  assert.equal(canAccess(item, superadmin), true, 'admin/settings should allow superadmin');
});

// ─── Designation override tests ───

test('comms_member can access admin-comms despite being member tier', () => {
  const commsMember = { tier: 'member', isLoggedIn: true, designations: ['comms_member'], operationalRole: 'researcher' };
  const item = parseNavItem('admin-comms');
  assert.equal(canAccess(item, commsMember), true, 'comms_member designation should grant access to admin-comms');
});

test('curator can access admin-analytics via designation', () => {
  const curator = { tier: 'observer', isLoggedIn: true, designations: ['curator'], operationalRole: 'researcher' };
  const item = parseNavItem('admin-analytics');
  assert.equal(canAccess(item, curator), true, 'curator designation should grant access to analytics');
});
