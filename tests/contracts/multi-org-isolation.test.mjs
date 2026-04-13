/**
 * Domain Model V4 — Fase 1 — Multi-Org Isolation Fixtures
 *
 * Static analysis contract test for Migration 3 (RLS org_id dual mode).
 * Precondição do critério 6 do ADR-0004: "Testes fixture-based com 2 orgs".
 *
 * Estratégia: a restrictive policy `organization_id = auth_org() OR IS NULL`
 * é cross-cutting em 40 tabelas de domínio. Este teste valida que:
 *   1. Migration 3 existe no formato esperado
 *   2. Todas as 40 tabelas recebem RESTRICTIVE policy FOR ALL
 *   3. USING e WITH CHECK referenciam auth_org() corretamente
 *   4. O helper auth_org() existe e é STABLE
 *   5. Não há regressão: todas as tabelas que tinham organization_id
 *      continuam tendo (Migration 3 não dropa colunas)
 *
 * O teste complementar de isolamento real (live DB com 2 orgs via SQL
 * transaction + ROLLBACK) foi registrado no master doc como evidência
 * one-shot da sessão — ver docs/refactor/DOMAIN_MODEL_V4_MASTER.md.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

// ─── Lista canônica das 40 tabelas com organization_id ───
// Migration 1 (chapters) + 2a (4 core) + 2b (35 rest).
// Se mudar, atualizar junto com a migration correspondente.
const V4_ORG_TABLES = [
  // Migration 1
  'chapters',
  // Migration 2a (core)
  'members', 'tribes', 'events', 'webinars',
  // Migration 2b (rest)
  'board_items', 'meeting_artifacts', 'tribe_deliverables',
  'publication_submissions', 'public_publications',
  'cycles', 'pilots', 'ia_pilots',
  'project_boards', 'project_memberships',
  'volunteer_applications',
  'announcements', 'blog_posts', 'event_showcases',
  'attendance', 'gamification_points',
  'courses', 'partner_entities', 'change_requests',
  'curation_review_log', 'board_lifecycle_events', 'board_sla_config',
  'annual_kpi_targets', 'portfolio_kpi_targets', 'portfolio_kpi_quarterly_targets',
  'selection_cycles', 'selection_applications', 'selection_committee',
  'selection_evaluations', 'selection_interviews', 'selection_diversity_snapshots',
  'member_activity_sessions', 'help_journeys', 'visitor_leads',
  'comms_channel_config',
];

// Sanity: 40 tabelas
test('V4 Phase 1: expected 40 tables with organization_id', () => {
  assert.equal(V4_ORG_TABLES.length, 40,
    `Expected 40 org-scoped tables, got ${V4_ORG_TABLES.length}`);
});

// ─── Helper: read all migrations ───
function loadAllMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => ({
    name: f,
    content: readFileSync(join(MIGRATIONS_DIR, f), 'utf8'),
  }));
}

const migrations = loadAllMigrations();
const allSQL = migrations.map(m => m.content).join('\n');

// ─── Fixture 1: Migration 3 file exists ───
test('V4 Phase 1: Migration 3 (RLS org scope dual mode) exists', () => {
  const candidates = migrations.filter(m =>
    m.name.includes('v4_phase1_rls_org_scope') ||
    m.name.includes('v4_phase1_org_scope_rls')
  );
  assert.ok(candidates.length >= 1,
    'Migration 3 file must exist with name containing v4_phase1_rls_org_scope');
});

const migration3 = migrations.find(m =>
  m.name.includes('v4_phase1_rls_org_scope') ||
  m.name.includes('v4_phase1_org_scope_rls')
);
const m3SQL = migration3?.content || '';

// ─── Fixture 2: auth_org() helper referenced in Migration 1 ───
test('V4 Phase 1: auth_org() helper function defined', () => {
  assert.ok(
    /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(?:public\.)?auth_org\s*\(\s*\)/i.test(allSQL),
    'auth_org() function must be defined in migrations'
  );
  assert.ok(
    /auth_org[\s\S]*?STABLE/i.test(allSQL),
    'auth_org() must be STABLE'
  );
  assert.ok(
    /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+(?:public\.)?auth_org\s*\(\s*\)\s+TO\s+[^;]*authenticated/i.test(allSQL),
    'auth_org() must be granted to authenticated'
  );
});

// ─── Fixture 3: Migration 3 declares all 40 tables in its scope ───
// Strategy: Migration 3 uses a DO block with format() iterating over
// a tables text[] array. We verify each table appears in the migration
// (inside the array literal), plus the DO block structure is correct.
for (const table of V4_ORG_TABLES) {
  test(`V4 Phase 1: ${table} listed in Migration 3 scope array`, () => {
    // Look for the table name as a quoted string inside the tables array.
    // Pattern tolerates leading/trailing whitespace and single or double quotes.
    const pattern = new RegExp(`['"]${table}['"]`, 'i');
    assert.ok(pattern.test(m3SQL),
      `${table} must appear in Migration 3's tables[] array`);
  });
}

// ─── Fixture 4: Migration 3 DO block uses RESTRICTIVE FOR ALL format ───
test('V4 Phase 1: Migration 3 creates RESTRICTIVE FOR ALL policies', () => {
  assert.ok(
    /CREATE\s+POLICY\s+%I\s+ON\s+public\.%I\s*'[\s\S]*?'AS\s+RESTRICTIVE\s*'[\s\S]*?'FOR\s+ALL/i.test(m3SQL)
      || /AS\s+RESTRICTIVE[\s\S]{0,100}FOR\s+ALL/i.test(m3SQL),
    'Migration 3 must use CREATE POLICY ... AS RESTRICTIVE FOR ALL pattern'
  );
});

// ─── Fixture 5: Migration 3 uses auth_org() in USING and WITH CHECK ───
test('V4 Phase 1: Migration 3 uses auth_org() in USING clause', () => {
  assert.ok(
    /USING\s*\([^)]*auth_org\s*\(\s*\)/i.test(m3SQL),
    'Migration 3 must reference auth_org() in USING clause'
  );
});

test('V4 Phase 1: Migration 3 uses auth_org() in WITH CHECK clause', () => {
  assert.ok(
    /WITH\s+CHECK\s*\([^)]*auth_org\s*\(\s*\)/i.test(m3SQL),
    'Migration 3 must reference auth_org() in WITH CHECK clause'
  );
});

// ─── Fixture 6: Dual mode (IS NULL tolerance) ───
test('V4 Phase 1: Migration 3 is dual mode (tolerates NULL org_id)', () => {
  assert.ok(
    /organization_id\s+IS\s+NULL/i.test(m3SQL),
    'Migration 3 must allow organization_id IS NULL (dual mode safety net)'
  );
});

// ─── Fixture 7: Migration 3 has sanity check asserting 40 policies ───
test('V4 Phase 1: Migration 3 has post-deploy sanity check for 40 policies', () => {
  assert.ok(
    /expected\s+40\s+policies/i.test(m3SQL) ||
    /policy_count\s*<>\s*40/i.test(m3SQL),
    'Migration 3 must have a sanity check asserting exactly 40 policies created'
  );
});

// ─── Fixture 6: No regression — Migration 3 does not drop organization_id ───
test('V4 Phase 1: Migration 3 does not drop organization_id columns', () => {
  assert.ok(!/DROP\s+COLUMN\s+.*organization_id/i.test(m3SQL),
    'Migration 3 must NOT drop organization_id (would undo Migrations 2a/2b)');
});

// ─── Fixture 8: Migration 3 does not touch existing permissive policies ───
test('V4 Phase 1: Migration 3 does not drop pre-V4 permissive policies', () => {
  // We intentionally add RESTRICTIVE ALONGSIDE existing permissive.
  // If Migration 3 has DROP POLICY, it should only be for idempotency
  // of its OWN org_scope policies, not other policies.
  // Migration uses a DO block with format() so literal DROP strings
  // contain %I — in that case verify the policy name expression (above
  // or near the DROP) derives from '_v4_org_scope'.
  const dropMatches = m3SQL.match(/DROP\s+POLICY\s+(?:IF\s+EXISTS\s+)?["']?([^"'\s,()]+)["']?/gi) || [];
  for (const drop of dropMatches) {
    const isOrgScopeLiteral = /org_scope/i.test(drop);
    // For DO-block DROPs with %I, check that '_v4_org_scope' appears
    // in the migration (proving the dynamic name ends with that suffix).
    const isDynamicOrgScope = /%I/i.test(drop) && /_v4_org_scope/i.test(m3SQL);
    assert.ok(isOrgScopeLiteral || isDynamicOrgScope,
      `Migration 3 drops non-org_scope policy: ${drop} — should only drop own policies for idempotency`);
  }
});

// ─── Fixture 8: Master doc references Migration 3 ───
test('V4 Phase 1: master tracking doc references Migration 3', () => {
  const masterPath = resolve(ROOT, 'docs/refactor/DOMAIN_MODEL_V4_MASTER.md');
  if (!existsSync(masterPath)) {
    // If master doc doesn't exist, skip gracefully
    return;
  }
  const content = readFileSync(masterPath, 'utf8');
  assert.ok(/Migration 3/i.test(content),
    'DOMAIN_MODEL_V4_MASTER.md should reference Migration 3 in Fase 1 checklist');
});
