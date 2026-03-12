/**
 * W96 Contract Test: Navigation Visibility
 * Validates that nav items with lgpdSensitive flag and specific allowedDesignations
 * are only visible/accessible to the correct tier and designation combinations.
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

function getItemAccessibility(item, tier, designations, isLoggedIn, operationalRole) {
  if (item.requiresAuth && !isLoggedIn) {
    return { visible: false, enabled: false };
  }
  const meetsMinTier = TIER_RANK[tier] >= TIER_RANK[item.minTier];
  const hasDesig = item.allowedDesignations.some(d => designations.includes(d));
  const hasOpRole = item.allowedOperationalRoles.includes(operationalRole || '');
  const enabled = meetsMinTier || hasDesig || hasOpRole;
  if (item.lgpdSensitive && !enabled) {
    return { visible: false, enabled: false };
  }
  if (isLoggedIn && item.requiresAuth) {
    return { visible: true, enabled };
  }
  return { visible: enabled, enabled };
}

// Extract all nav item keys
const navItemKeys = [...NAV_CONFIG.matchAll(/key:\s*'([^']+)'/g)].map(m => m[1]);
const lgpdItems = navItemKeys.map(parseNavItem).filter(i => i.lgpdSensitive);

// ─── Test profiles ───
const PROFILES = {
  visitor: { tier: 'visitor', isLoggedIn: false, designations: [], operationalRole: '' },
  researcher: { tier: 'member', isLoggedIn: true, designations: [], operationalRole: 'researcher' },
  tribe_leader: { tier: 'leader', isLoggedIn: true, designations: [], operationalRole: 'tribe_leader' },
  admin: { tier: 'admin', isLoggedIn: true, designations: [], operationalRole: 'manager' },
  superadmin: { tier: 'superadmin', isLoggedIn: true, designations: [], operationalRole: 'manager' },
  comms_member: { tier: 'member', isLoggedIn: true, designations: ['comms_member'], operationalRole: 'researcher' },
  curator: { tier: 'observer', isLoggedIn: true, designations: ['curator'], operationalRole: 'researcher' },
  co_gp: { tier: 'observer', isLoggedIn: true, designations: ['co_gp'], operationalRole: 'researcher' },
};

// ─── LGPD items must be invisible to visitor, researcher, tribe_leader ───

for (const item of lgpdItems) {
  test(`LGPD item "${item.key}" is invisible to visitor`, () => {
    const result = getItemAccessibility(item, 'visitor', [], false, '');
    assert.equal(result.visible, false, `${item.key} should be invisible to visitor`);
  });

  test(`LGPD item "${item.key}" is invisible to researcher`, () => {
    const result = getItemAccessibility(item, 'member', [], true, 'researcher');
    assert.equal(result.visible, false, `${item.key} should be invisible to researcher`);
  });

  test(`LGPD item "${item.key}" is invisible to tribe_leader (no designation)`, () => {
    const result = getItemAccessibility(item, 'leader', [], true, 'tribe_leader');
    assert.equal(result.visible, false, `${item.key} should be invisible to tribe_leader without designation`);
  });
}

// ─── admin/selection ───

test('admin-selection visible only to admin+ tier', () => {
  const item = parseNavItem('admin-selection');
  for (const [name, profile] of Object.entries(PROFILES)) {
    const result = getItemAccessibility(item, profile.tier, profile.designations, profile.isLoggedIn, profile.operationalRole);
    const shouldSee = TIER_RANK[profile.tier] >= TIER_RANK['admin'];
    assert.equal(result.visible, shouldSee, `admin-selection visibility for ${name}: expected ${shouldSee}`);
  }
});

// ─── admin/comms (requires admin OR comms_leader/comms_member designation) ───

test('admin-comms visible to admin and comms_member designation', () => {
  const item = parseNavItem('admin-comms');

  // Should see: admin, superadmin, comms_member
  const shouldSee = ['admin', 'superadmin', 'comms_member'];
  for (const [name, profile] of Object.entries(PROFILES)) {
    const result = getItemAccessibility(item, profile.tier, profile.designations, profile.isLoggedIn, profile.operationalRole);
    const expected = shouldSee.includes(name);
    assert.equal(result.visible && result.enabled, expected,
      `admin-comms access for ${name}: expected ${expected}, got visible=${result.visible} enabled=${result.enabled}`);
  }
});

// ─── admin/comms-ops ───

test('admin-comms-ops visible to admin and comms_member designation', () => {
  const item = parseNavItem('admin-comms-ops');

  const shouldSee = ['admin', 'superadmin', 'comms_member'];
  for (const [name, profile] of Object.entries(PROFILES)) {
    const result = getItemAccessibility(item, profile.tier, profile.designations, profile.isLoggedIn, profile.operationalRole);
    const expected = shouldSee.includes(name);
    assert.equal(result.visible && result.enabled, expected,
      `admin-comms-ops access for ${name}: expected ${expected}`);
  }
});

// ─── allowedDesignations are respected ───

test('webinars requires leader tier OR comms/curator/facilitator designation/role', () => {
  const item = parseNavItem('webinars');

  // tribe_leader should access (meets minTier=leader)
  const tl = getItemAccessibility(item, 'leader', [], true, 'tribe_leader');
  assert.ok(tl.enabled, 'tribe_leader should access webinars');

  // researcher without designation should NOT
  const res = getItemAccessibility(item, 'member', [], true, 'researcher');
  assert.equal(res.enabled, false, 'plain researcher should not access webinars');

  // comms_member should access via designation
  const comms = getItemAccessibility(item, 'member', ['comms_member'], true, 'researcher');
  assert.ok(comms.enabled, 'comms_member designation should grant webinars access');

  // facilitator should access via operationalRole
  const fac = getItemAccessibility(item, 'member', [], true, 'facilitator');
  assert.ok(fac.enabled, 'facilitator role should grant webinars access');
});

test('publications requires leader tier OR curator/comms designation/communicator role', () => {
  const item = parseNavItem('publications');

  const curator = getItemAccessibility(item, 'observer', ['curator'], true, 'researcher');
  assert.ok(curator.enabled, 'curator should access publications');

  const communicator = getItemAccessibility(item, 'member', [], true, 'communicator');
  assert.ok(communicator.enabled, 'communicator role should access publications');

  const researcher = getItemAccessibility(item, 'member', [], true, 'researcher');
  assert.equal(researcher.enabled, false, 'plain researcher cannot access publications');
});

// ─── Superadmin can access everything ───

test('superadmin can access all authenticated routes', () => {
  const superadmin = PROFILES.superadmin;
  for (const key of navItemKeys) {
    const item = parseNavItem(key);
    if (!item.requiresAuth) continue;
    const result = getItemAccessibility(item, superadmin.tier, superadmin.designations, superadmin.isLoggedIn, superadmin.operationalRole);
    assert.ok(result.enabled, `superadmin must be able to access ${key}`);
  }
});
