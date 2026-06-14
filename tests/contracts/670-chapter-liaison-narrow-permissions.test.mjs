import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const middleware = readFileSync(resolve(ROOT, 'src/middleware/index.ts'), 'utf8');

test('#670 middleware does not treat chapter_liaison as broad admin role', () => {
  const adminRolesMatch = middleware.match(/const ADMIN_ROLES = new Set\(\[([^\]]+)\]\)/);
  assert.ok(adminRolesMatch, 'ADMIN_ROLES set must be declared in middleware');
  assert.equal(adminRolesMatch[1].includes('"chapter_liaison"'), false, 'chapter_liaison must not be in broad ADMIN_ROLES');
});

test('#670 middleware allowlists only chapter_liaison read admin routes', () => {
  assert.match(middleware, /const CHAPTER_LIAISON_ADMIN_PATHS = new Set/);
  for (const path of [
    '/admin/analytics',
    '/admin/chapter-report',
    '/admin/cycle-report',
    '/admin/partnerships',
    '/admin/portfolio',
    '/admin/report',
    '/admin/sustainability',
  ]) {
    assert.ok(middleware.includes(path), `missing chapter_liaison route allowlist entry: ${path}`);
  }

  for (const denied of [
    '/admin/selection',
    '/admin/settings',
    '/admin/comms',
    '/admin/campaigns',
    '/admin/blog',
    '/admin/tribes',
  ]) {
    assert.equal(middleware.includes(`"${denied}"`), false, `chapter_liaison allowlist must not include ${denied}`);
  }
});

test('#670 middleware permits chapter_liaison by operational_role or designation only on allowlisted routes', () => {
  assert.match(middleware, /member\?\.operational_role === "chapter_liaison"/);
  assert.match(middleware, /designations\.includes\("chapter_liaison"\)/);
  assert.match(middleware, /hasChapterLiaisonAdminAccess\(member, canonicalPath\)/);
});
