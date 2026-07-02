import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

// ─────────────────────────────────────────────────────────────────────────────
// #1038 — anti-drift guard for the admin LEFT sidebar.
//
// AdminSidebar.tsx keeps its own hardcoded SECTIONS array (it does NOT read the
// SSOT navigation.config.ts — the two use different authority models and are
// largely disjoint sets; a full merge was scoped as a follow-up). Because there
// was no cross-check, pages drifted out of the sidebar unnoticed (chapter-report,
// vep-reconciliation, agenda-viva were in the SSOT but not the sidebar;
// ai-calibration and initiative-kinds were orphans in every nav).
//
// This guard closes the RECURRENCE class at CI: every static /admin/* page file
// must be either wired into AdminSidebar.tsx OR listed below with a reason.
// It is pure static file analysis (no DB, no live state) so it never flakes.
// ─────────────────────────────────────────────────────────────────────────────

const SIDEBAR = 'src/components/admin/AdminSidebar.tsx';
const ADMIN_PAGES_DIR = 'src/pages/admin';

// Routes intentionally NOT in the left admin sidebar (reached contextually).
// Adding a new /admin page? Wire it into AdminSidebar.tsx SECTIONS, or add it
// here WITH a reason. This guard fails otherwise.
const BY_DESIGN_NOT_IN_SIDEBAR = new Set([
  '/admin/help',                        // admin-scoped help; the sidebar links the public /help
  '/admin/members/inactive-candidates', // reached from the member-detail / offboarding flow
  '/admin/governance/charters',         // governance sub-page (entered from /admin/governance-v2)
  '/admin/governance/documents',        // governance sub-page
  '/admin/governance/ip-ratification',  // governance sub-page
]);

function walk(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...walk(p));
    else if (name.endsWith('.astro')) out.push(p);
  }
  return out;
}

// src/pages/admin/x/y.astro -> /admin/x/y ; .../index.astro -> parent route
function fileToRoute(file) {
  const norm = file.split('\\').join('/');
  return norm.replace(/^src\/pages/, '').replace(/\.astro$/, '').replace(/\/index$/, '') || '/';
}

test('#1038 every static /admin page is in the sidebar or explicitly allowlisted', () => {
  const nav = readFileSync(SIDEBAR, 'utf8');
  const sidebarHrefs = new Set([...nav.matchAll(/href:\s*'([^']+)'/g)].map(m => m[1]));

  const missing = [];
  for (const f of walk(ADMIN_PAGES_DIR)) {
    if (f.includes('[')) continue; // dynamic route ([id], [chainId]…) — not a nav target
    const route = fileToRoute(f);
    if (sidebarHrefs.has(route)) continue;
    if (BY_DESIGN_NOT_IN_SIDEBAR.has(route)) continue;
    missing.push(route);
  }

  assert.deepEqual(
    missing.sort(),
    [],
    `These /admin pages are neither in ${SIDEBAR} (SECTIONS) nor in BY_DESIGN_NOT_IN_SIDEBAR. ` +
    `Wire each into a sidebar SECTIONS item with the correct permission, or add it to the ` +
    `allowlist with a reason: ${missing.join(', ')}`,
  );
});

test('#1038 sidebar-coverage allowlist has no stale entries', () => {
  // Every allowlisted route must still map to a real page file, else it is dead
  // config that would hide future drift.
  const routes = new Set(walk(ADMIN_PAGES_DIR).map(fileToRoute));
  const stale = [...BY_DESIGN_NOT_IN_SIDEBAR].filter(r => !routes.has(r));
  assert.deepEqual(stale, [], `Stale allowlist entries (page no longer exists): ${stale.join(', ')}`);
});

test('#1038 the five formerly-drifted pages are now wired into the sidebar', () => {
  const nav = readFileSync(SIDEBAR, 'utf8');
  const hrefs = new Set([...nav.matchAll(/href:\s*'([^']+)'/g)].map(m => m[1]));
  for (const route of [
    '/admin/chapter-report',
    '/admin/vep-reconciliation',
    '/admin/agenda-viva',
    '/admin/ai-calibration',
    '/admin/initiative-kinds',
  ]) {
    assert.ok(hrefs.has(route), `${route} must be present in ${SIDEBAR}`);
  }
});
