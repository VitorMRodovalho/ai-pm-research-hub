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
  if (!match) throw new Error(`Nav item not found for key ${key}`);
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
  return match[1]
    .split(',')
    .map((entry) => entry.trim().replace(/^'|'$/g, ''))
    .filter(Boolean);
}

function parseNavItem(key) {
  const block = extractItemBlock(key);
  return {
    key,
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
  const hasDesig = item.allowedDesignations.some((d) => profile.designations.includes(d));
  const hasOperationalRole = item.allowedOperationalRoles.includes(profile.operationalRole || '');
  const enabled = meetsMinTier || hasDesig || hasOperationalRole;
  if (item.lgpdSensitive && !enabled) return false;
  return enabled;
}

test('guest cannot access publications nor admin surfaces', () => {
  const guest = { tier: 'visitor', isLoggedIn: false, designations: [], operationalRole: 'guest' };
  const publications = parseNavItem('publications');
  const admin = parseNavItem('admin');
  const adminComms = parseNavItem('admin-comms');
  const adminPortfolio = parseNavItem('admin-portfolio');
  assert.equal(canAccess(publications, guest), false);
  assert.equal(canAccess(admin, guest), false);
  assert.equal(canAccess(adminComms, guest), false);
  assert.equal(canAccess(adminPortfolio, guest), false);
});

test('researcher can access own-tribe route but not global publications board', () => {
  const researcher = { tier: 'member', isLoggedIn: true, designations: [], operationalRole: 'researcher' };
  const myTribe = parseNavItem('my-tribe');
  const publications = parseNavItem('publications');
  assert.equal(canAccess(myTribe, researcher), true);
  assert.equal(canAccess(publications, researcher), false);
});

test('leadership/comms/curator profiles can access operational surfaces', () => {
  const leadership = { tier: 'leader', isLoggedIn: true, designations: [], operationalRole: 'tribe_leader' };
  const commsMember = { tier: 'member', isLoggedIn: true, designations: ['comms_member'], operationalRole: 'researcher' };
  const curator = { tier: 'observer', isLoggedIn: true, designations: ['curator'], operationalRole: 'researcher' };

  const webinars = parseNavItem('webinars');
  const publications = parseNavItem('publications');
  const adminCommsOps = parseNavItem('admin-comms-ops');

  assert.equal(canAccess(webinars, leadership), true);
  assert.equal(canAccess(webinars, commsMember), true);
  assert.equal(canAccess(publications, curator), true);
  assert.equal(canAccess(adminCommsOps, commsMember), true);
});
