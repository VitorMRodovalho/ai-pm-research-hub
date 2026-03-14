/**
 * W129 Contract Tests: Persona QA Audit
 * Validates RPC column fixes, auth patterns, and persona access control.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();

function readFile(relPath) {
  return readFileSync(resolve(ROOT, relPath), 'utf8');
}

// ═══════════════════════════════════════════════════
// BUG-1 FIX: workspace.astro auth pattern
// ═══════════════════════════════════════════════════

test('workspace.astro uses nav:member event listener (not waitForAuth polling)', () => {
  const content = readFile('src/pages/workspace.astro');
  assert.ok(content.includes("nav:member"), 'Must use nav:member event listener');
  assert.ok(!content.includes('function waitForAuth'), 'Must not use old waitForAuth polling pattern');
});

test('workspace.astro checks session directly as fallback', () => {
  const content = readFile('src/pages/workspace.astro');
  assert.ok(content.includes('sb.auth.getSession'), 'Must check session directly as fallback');
  assert.ok(content.includes("sb.rpc('get_member_by_auth')"), 'Must call get_member_by_auth RPC');
});

test('workspace.astro checks navGetMember first', () => {
  const content = readFile('src/pages/workspace.astro');
  assert.ok(content.includes('navGetMember'), 'Must check navGetMember for already-loaded member');
});

test('workspace.astro auth pattern matches attendance.astro pattern', () => {
  const workspace = readFile('src/pages/workspace.astro');
  const attendance = readFile('src/pages/attendance.astro');
  // Both should use the same 3-step auth pattern
  assert.ok(workspace.includes("nav:member"), 'workspace must use nav:member');
  assert.ok(attendance.includes("nav:member"), 'attendance must use nav:member');
  assert.ok(workspace.includes('navGetMember'), 'workspace must check navGetMember');
  assert.ok(attendance.includes('navGetMember'), 'attendance must check navGetMember');
  assert.ok(workspace.includes('getSession'), 'workspace must check getSession');
  assert.ok(attendance.includes('getSession'), 'attendance must check getSession');
});

// ═══════════════════════════════════════════════════
// BUG-2 FIX: exec_tribe_dashboard no certifications
// ═══════════════════════════════════════════════════

test('W129 migration exists', () => {
  assert.ok(
    existsSync(resolve(ROOT, 'supabase/migrations/20260319100032_w129_column_fixes.sql')),
    'W129 column fix migration must exist'
  );
});

test('W129 migration fixes exec_tribe_dashboard (removes m.certifications)', () => {
  const content = readFile('supabase/migrations/20260319100032_w129_column_fixes.sql');
  // The fixed function should have cpmai_certified but NOT m.certifications
  const funcBody = extractFunctionBody(content, 'exec_tribe_dashboard');
  assert.ok(funcBody, 'exec_tribe_dashboard must exist in migration');
  assert.ok(funcBody.includes('cpmai_certified'), 'Must still have cpmai_certified');
  assert.ok(!funcBody.includes("m.certifications"), 'Must NOT reference m.certifications');
});

test('W129 migration fixes exec_chapter_dashboard (a.present = true)', () => {
  const content = readFile('supabase/migrations/20260319100032_w129_column_fixes.sql');
  const funcBody = extractFunctionBody(content, 'exec_chapter_dashboard');
  assert.ok(funcBody, 'exec_chapter_dashboard must exist in migration');
  assert.ok(funcBody.includes('a.present = true'), 'Must use a.present = true');
  // The only reference to a.status should be in the comment
  const lines = funcBody.split('\n').filter(l => !l.trim().startsWith('--'));
  const nonCommentBody = lines.join('\n');
  assert.ok(!nonCommentBody.includes("a.status = 'present'"), 'Must NOT have a.status = present in non-comment SQL');
});

test('W129 migration fixes exec_chapter_comparison (a2.present = true)', () => {
  const content = readFile('supabase/migrations/20260319100032_w129_column_fixes.sql');
  const funcBody = extractFunctionBody(content, 'exec_chapter_comparison');
  assert.ok(funcBody, 'exec_chapter_comparison must exist in migration');
  assert.ok(funcBody.includes('a2.present = true'), 'Must use a2.present = true');
  assert.ok(!funcBody.includes("a2.status = 'present'"), 'Must NOT reference a2.status');
});

// ═══════════════════════════════════════════════════
// Navigation access control
// ═══════════════════════════════════════════════════

test('navigation.config.ts defines access tiers for all admin routes', () => {
  const content = readFile('src/lib/navigation.config.ts');
  const adminRoutes = [
    '/admin', '/admin/analytics', '/admin/comms', '/admin/curatorship',
    '/report', '/admin/chapter-report', '/admin/tribes',
    '/admin/partnerships', '/admin/sustainability', '/admin/selection',
  ];
  for (const route of adminRoutes) {
    assert.ok(
      content.includes(route),
      `Navigation config must define ${route}`
    );
  }
});

test('navigation.config.ts has minTier for each nav item', () => {
  const content = readFile('src/lib/navigation.config.ts');
  // Every navigation item should specify a minTier
  const itemMatches = content.match(/minTier:\s*'[^']+'/g);
  assert.ok(itemMatches && itemMatches.length >= 10, `Must have at least 10 minTier definitions, found ${itemMatches?.length || 0}`);
});

// ═══════════════════════════════════════════════════
// Persona access boundaries
// ═══════════════════════════════════════════════════

test('public pages do not require authentication in their source', () => {
  const publicPages = ['index.astro', 'about.astro', 'privacy.astro'];
  for (const page of publicPages) {
    const content = readFile(`src/pages/${page}`);
    // Public pages should NOT have auth gates that block rendering
    assert.ok(
      !content.includes("waitForAuth") || content.includes('visitor'),
      `${page} should not block on auth`
    );
  }
});

test('admin pages exist for GP journey', () => {
  const adminPages = [
    'src/pages/admin/index.astro',
    'src/pages/admin/analytics.astro',
    'src/pages/admin/cycle-report.astro',
    'src/pages/admin/partnerships.astro',
    'src/pages/admin/sustainability.astro',
    'src/pages/admin/selection.astro',
  ];
  for (const page of adminPages) {
    assert.ok(existsSync(resolve(ROOT, page)), `${page} must exist`);
  }
});

test('workspace.astro has auth gate UI for unauthenticated users', () => {
  const content = readFile('src/pages/workspace.astro');
  assert.ok(content.includes('wk-auth-gate') || content.includes('authGate'), 'Must have auth gate element');
  assert.ok(content.includes('hidden'), 'Must use hidden class for auth gate toggle');
});

// ═══════════════════════════════════════════════════
// RPC column safety
// ═══════════════════════════════════════════════════

test('no migration references attendance.status as text column', () => {
  // Check the latest versions of functions that were fixed
  const w129 = readFile('supabase/migrations/20260319100032_w129_column_fixes.sql');
  // exec_chapter_dashboard
  const chapterFunc = extractFunctionBody(w129, 'exec_chapter_dashboard');
  const chapterLines = chapterFunc.split('\n').filter(l => !l.trim().startsWith('--'));
  for (const line of chapterLines) {
    assert.ok(
      !line.includes("a.status = 'present'"),
      `exec_chapter_dashboard must not use a.status = 'present': ${line.trim()}`
    );
  }
  // exec_chapter_comparison
  const compFunc = extractFunctionBody(w129, 'exec_chapter_comparison');
  assert.ok(!compFunc.includes("a2.status = 'present'"), 'exec_chapter_comparison must not use a2.status');
});

test('exec_tribe_dashboard uses present boolean not status text', () => {
  const w129 = readFile('supabase/migrations/20260319100032_w129_column_fixes.sql');
  const func = extractFunctionBody(w129, 'exec_tribe_dashboard');
  // Should use a.present = true for attendance filtering
  assert.ok(func.includes('a.present = true'), 'Must use a.present = true');
});

// ═══════════════════════════════════════════════════
// Persona journey test file
// ═══════════════════════════════════════════════════

test('Playwright persona journey test file exists', () => {
  assert.ok(
    existsSync(resolve(ROOT, 'tests/persona-journeys.spec.ts')),
    'tests/persona-journeys.spec.ts must exist'
  );
});

test('Persona journey tests cover all persona types', () => {
  const content = readFile('tests/persona-journeys.spec.ts');
  const personas = ['VISITOR', 'RESEARCHER', 'TRIBE_LEADER', 'SPONSOR', 'GP'];
  for (const p of personas) {
    assert.ok(content.includes(p), `Must test ${p} persona`);
  }
});

test('Persona journey tests cover all critical routes', () => {
  const content = readFile('tests/persona-journeys.spec.ts');
  const routes = [
    '/', '/about', '/privacy', '/workspace', '/attendance',
    '/admin', '/admin/tribe/',
  ];
  for (const route of routes) {
    assert.ok(content.includes(route), `Must test route ${route}`);
  }
});

// ═══════════════════════════════════════════════════
// Helper
// ═══════════════════════════════════════════════════

function extractFunctionBody(sql, funcName) {
  const regex = new RegExp(
    `CREATE OR REPLACE FUNCTION[^(]*${funcName}\\b[\\s\\S]*?\\$\\$([\\s\\S]*?)\\$\\$`,
    'i'
  );
  const match = sql.match(regex);
  return match ? match[1] : '';
}
