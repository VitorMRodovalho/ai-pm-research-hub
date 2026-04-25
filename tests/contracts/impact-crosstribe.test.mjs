/**
 * W118 + W119 Contract Tests: Impact Narrative + Cross-Tribe Comparison
 * Static analysis — reads migration files, UI files, and verifies structure.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function loadAllMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => ({
    name: f,
    content: readFileSync(join(MIGRATIONS_DIR, f), 'utf8'),
  }));
}

const migrations = loadAllMigrations();
const allSQL = migrations.map(m => m.content).join('\n');

function findFunctionBody(funcName) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  // Match both $$ and $function$ delimiters
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?(\\$\\w*\\$)([\\s\\S]*?)\\1`,
    'gi'
  );
  const matches = [...allSQL.matchAll(regex)];
  if (matches.length === 0) return null;
  return matches[matches.length - 1][2];
}

// ═══════════════════════════════════════════════════
// W118: Impact Narrative Public Page
// ═══════════════════════════════════════════════════

test('get_public_impact_data RPC exists', () => {
  const body = findFunctionBody('get_public_impact_data');
  assert.ok(body, 'get_public_impact_data not found in migrations');
});

test('get_public_impact_data is SECURITY DEFINER', () => {
  const match = allSQL.match(/get_public_impact_data[\s\S]*?SECURITY\s+DEFINER/i);
  assert.ok(match, 'get_public_impact_data must be SECURITY DEFINER');
});

test('get_public_impact_data does NOT require auth (public)', () => {
  const body = findFunctionBody('get_public_impact_data');
  assert.ok(body);
  // Should NOT have auth.uid() check — it's public
  assert.ok(!body.includes('auth.uid()'), 'get_public_impact_data must be public (no auth.uid check)');
});

test('get_public_impact_data is granted to anon', () => {
  assert.ok(
    /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+.*get_public_impact_data.*TO\s+anon/i.test(allSQL),
    'get_public_impact_data must be granted to anon'
  );
});

test('get_public_impact_data returns all required fields', () => {
  const body = findFunctionBody('get_public_impact_data');
  assert.ok(body);
  const fields = ['chapters', 'active_members', 'tribes', 'articles_published', 'impact_hours',
                   'webinars', 'recent_publications', 'tribes_summary', 'chapters_summary', 'partners', 'timeline'];
  for (const f of fields) {
    assert.ok(body.includes(`'${f}'`), `get_public_impact_data must include ${f}`);
  }
});

test('get_public_impact_data does not expose PII', () => {
  const body = findFunctionBody('get_public_impact_data');
  assert.ok(body);
  // Should not select email, phone, auth_id
  assert.ok(!body.includes('.email'), 'Must not include email in public data');
  assert.ok(!body.includes('.phone'), 'Must not include phone in public data');
  assert.ok(!body.includes('.auth_id'), 'Must not include auth_id in public data');
});

test('get_public_impact_data timeline has 4 entries', () => {
  const body = findFunctionBody('get_public_impact_data');
  assert.ok(body);
  const timelineEntries = body.match(/jsonb_build_object\(\s*'year'/g);
  assert.ok(timelineEntries && timelineEntries.length >= 4, 'Timeline must have at least 4 entries');
});

test('/about page exists', () => {
  assert.ok(existsSync(resolve(ROOT, 'src/pages/about.astro')), '/about page must exist');
});

test('/about page uses ImpactPageIsland', () => {
  const content = readFileSync(resolve(ROOT, 'src/pages/about.astro'), 'utf8');
  assert.ok(content.includes('ImpactPageIsland'), 'about page must use ImpactPageIsland');
  assert.ok(content.includes('client:load'), 'ImpactPageIsland must have client:load');
});

test('ImpactPageIsland has all sections', () => {
  const path = resolve(ROOT, 'src/components/islands/ImpactPageIsland.tsx');
  assert.ok(existsSync(path), 'ImpactPageIsland.tsx must exist');
  const content = readFileSync(path, 'utf8');
  assert.ok(content.includes('AnimatedCounter'), 'Must have animated counters');
  assert.ok(content.includes('timeline'), 'Must have timeline section');
  assert.ok(content.includes('mission') || content.includes('Mission'), 'Must have mission section');
  assert.ok(content.includes('tribes_summary'), 'Must have tribes grid');
  assert.ok(content.includes('recent_publications'), 'Must have publications preview');
  assert.ok(content.includes('chapters_summary'), 'Must have chapters section');
});

test('/about page has SEO meta tags', () => {
  const content = readFileSync(resolve(ROOT, 'src/pages/about.astro'), 'utf8');
  assert.ok(content.includes('og:title'), 'Must have Open Graph title');
  assert.ok(content.includes('og:description'), 'Must have Open Graph description');
  assert.ok(content.includes('schema.org') || content.includes('ResearchOrganization'), 'Must have Schema.org markup');
});

test('ImpactPageIsland supports i18n (pt-BR, en-US, es-LATAM)', () => {
  const content = readFileSync(resolve(ROOT, 'src/components/islands/ImpactPageIsland.tsx'), 'utf8');
  assert.ok(content.includes('pt-BR'), 'Must support pt-BR');
  assert.ok(content.includes('en-US'), 'Must support en-US');
  assert.ok(content.includes('es-LATAM'), 'Must support es-LATAM');
});

// ═══════════════════════════════════════════════════
// W119: Cross-Tribe Comparison
// ═══════════════════════════════════════════════════

test('exec_cross_tribe_comparison RPC exists', () => {
  const body = findFunctionBody('exec_cross_tribe_comparison');
  assert.ok(body, 'exec_cross_tribe_comparison not found');
});

test('exec_cross_tribe_comparison gated via can_by_member(manage_platform)', () => {
  // V4 (ADR-0011 cleanup 2026-04-26): replaces V3 role-list assertion.
  // can_by_member() respects is_superadmin and grants manage_platform to
  // volunteer × {manager, deputy_manager, co_gp} — original V3 audience.
  const body = findFunctionBody('exec_cross_tribe_comparison');
  assert.ok(body);
  assert.ok(/auth\.uid\(\)/i.test(body), 'Must check auth.uid()');
  assert.ok(/RAISE\s+EXCEPTION/i.test(body), 'Must RAISE EXCEPTION on unauthorized');
  assert.ok(/can_by_member\s*\([^)]*['"]manage_platform['"]/i.test(body),
    'Must call can_by_member with manage_platform action');
});

test('exec_cross_tribe_comparison returns tribe metrics', () => {
  const body = findFunctionBody('exec_cross_tribe_comparison');
  assert.ok(body);
  const metrics = ['member_count', 'attendance_rate', 'total_cards', 'cards_completed', 'total_xp', 'total_hours', 'meetings_count', 'days_since_last_meeting'];
  for (const m of metrics) {
    assert.ok(body.includes(`'${m}'`), `Must include ${m} metric`);
  }
});

test('detect_operational_alerts RPC exists', () => {
  const body = findFunctionBody('detect_operational_alerts');
  assert.ok(body, 'detect_operational_alerts not found');
});

test('detect_operational_alerts requires GP/DM/superadmin', () => {
  const body = findFunctionBody('detect_operational_alerts');
  assert.ok(body);
  assert.ok(/auth\.uid\(\)/i.test(body), 'Must check auth.uid()');
  assert.ok(/RAISE\s+EXCEPTION/i.test(body), 'Must RAISE EXCEPTION on unauthorized');
});

test('detect_operational_alerts checks 5 alert types', () => {
  const body = findFunctionBody('detect_operational_alerts');
  assert.ok(body);
  const types = ['tribe_no_meeting', 'member_absence_streak', 'tribe_stagnant_production', 'onboarding_overdue', 'kpi_at_risk'];
  for (const t of types) {
    assert.ok(body.includes(t), `Must detect ${t} alert type`);
  }
});

test('detect_operational_alerts returns severity breakdown', () => {
  const body = findFunctionBody('detect_operational_alerts');
  assert.ok(body);
  assert.ok(body.includes('by_severity'), 'Must return by_severity breakdown');
  assert.ok(body.includes("'high'"), 'Must include high severity');
  assert.ok(body.includes("'medium'"), 'Must include medium severity');
  assert.ok(body.includes("'low'"), 'Must include low severity');
});

test('/admin/tribes page exists', () => {
  assert.ok(existsSync(resolve(ROOT, 'src/pages/admin/tribes.astro')), '/admin/tribes page must exist');
});

test('/admin/tribes uses CrossTribeIsland', () => {
  const content = readFileSync(resolve(ROOT, 'src/pages/admin/tribes.astro'), 'utf8');
  assert.ok(content.includes('CrossTribeIsland'), 'Must use CrossTribeIsland');
  assert.ok(content.includes('client:load'), 'Must have client:load');
});

test('CrossTribeIsland has ranking charts and sortable table', () => {
  const path = resolve(ROOT, 'src/components/islands/CrossTribeIsland.tsx');
  assert.ok(existsSync(path), 'CrossTribeIsland.tsx must exist');
  const content = readFileSync(path, 'utf8');
  assert.ok(content.includes('BarChart'), 'Must have BarChart for rankings');
  assert.ok(content.includes('sortBy') || content.includes('SortHeader'), 'Must have sortable table');
  assert.ok(content.includes('detect_operational_alerts'), 'Must load alerts');
  assert.ok(content.includes('exec_cross_tribe_comparison'), 'Must load cross-tribe data');
});

test('AdminNav has cross-tribes entry', () => {
  const content = readFileSync(resolve(ROOT, 'src/components/nav/AdminNav.astro'), 'utf8');
  assert.ok(content.includes('cross-tribes'), 'AdminNav must have cross-tribes entry');
  assert.ok(content.includes('/admin/tribes'), 'AdminNav must link to /admin/tribes');
});

test('navigation.config has admin-cross-tribes entry', () => {
  const content = readFileSync(resolve(ROOT, 'src/lib/navigation.config.ts'), 'utf8');
  assert.ok(content.includes('admin-cross-tribes'), 'navigation.config must have admin-cross-tribes');
});

test('workspace has alerts section for GP', () => {
  const content = readFileSync(resolve(ROOT, 'src/pages/workspace.astro'), 'utf8');
  assert.ok(content.includes('wk-alerts'), 'workspace must have wk-alerts section');
  assert.ok(content.includes('detect_operational_alerts'), 'workspace must call detect_operational_alerts');
});

test('i18n keys exist for cross-tribes and about', () => {
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const content = readFileSync(resolve(ROOT, `src/i18n/${lang}.ts`), 'utf8');
    assert.ok(content.includes('nav.adminCrossTribes'), `${lang} must have nav.adminCrossTribes`);
  }
});
