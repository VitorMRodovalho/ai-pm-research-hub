/**
 * W110 Contract Test: KPI Portfolio Health
 * Validates that exec_portfolio_health RPC and the home's goal block are aligned.
 * - #2553 (D9, GP 20/10/2026): the home renders the goals from exec_portfolio_health on the server;
 *   src/data/kpis.ts (static headline values) is gone, so no target can disagree with the database
 * - exec_portfolio_health must return all 9 metric_keys
 * - portfolio_kpi_targets must have targets for all 9 metrics
 * - Quarterly decomposition must exist
 * - Color thresholds are consistent (green >= target, yellow >= warning, red < warning)
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const KPI_FILE = resolve(ROOT, 'src/data/kpis.ts');
const KPI_SECTION = resolve(ROOT, 'src/components/sections/KpiSection.astro');
const HOME_DATA = resolve(ROOT, 'src/lib/publicHomeData.ts');

// ─── Helpers ───

function loadAllMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => ({
    name: f,
    content: readFileSync(join(MIGRATIONS_DIR, f), 'utf8'),
  }));
}

const migrations = loadAllMigrations();
// p171 TIER C — strip SQL line comments antes de regex matching. Rollback notes
// nos headers de migrations frequentemente citam `CREATE OR REPLACE FUNCTION …`
// dentro de comments, e o regex lazy do body pode latchar nessas ocorrências
// e estender o match through migration boundaries até encontrar um $tag$…$tag$
// de RPC diferente. Mesmo padrão de role-ladder-parity.test.mjs (sediment p165).
const stripSqlLineComments = (sql) => sql.replace(/--[^\n]*/g, '');
const allSQL = migrations.map(m => stripSqlLineComments(m.content)).join('\n');

// p171 TIER C — Helper to find FUNCTION body by name, ignoring DO blocks.
// Pattern: CREATE OR REPLACE FUNCTION X(args) ... AS $TAG$ body $TAG$
// Captures tag name so DO blocks (with $$ delimiter) não conflict.
function findFunctionBody(funcName, sql) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi'
  );
  const matches = [...sql.matchAll(regex)];
  if (matches.length === 0) return null;
  return matches[matches.length - 1][2];
}

// Expected 9 metric_keys in exec_portfolio_health (from GP-Sponsor agreement)
const EXPECTED_METRICS = [
  'chapters_participating',
  'partner_entities',
  'certification_trail',
  'cpmai_certified',
  'articles_published',
  'webinars_completed',
  'ia_pilots',
  'meeting_hours',
  'impact_hours',
];

// ─── Test 1: no static KPI list (#2553 D9) ───

test('src/data/kpis.ts no longer exists: the home has no static goal value', () => {
  assert.ok(!existsSync(KPI_FILE), 'src/data/kpis.ts is back: a static target can disagree with exec_portfolio_health again');
});

// ─── Test 2: the home's goals come from exec_portfolio_health, label included ───

test('the goal block reads exec_portfolio_health on the server, with the label from the database', () => {
  const homeData = readFileSync(HOME_DATA, 'utf8');
  assert.match(homeData, /const rows = await rpc<unknown\[\]>\('exec_portfolio_health'\);/);
  assert.match(homeData, /label: String\(r\.label\?\.\[l\] \?\? r\.label\?\.pt \?\? r\.metric_key \?\? ''\),\s+current: isNum\(r\.current\) \? r\.current : null,\s+target: isNum\(r\.target\) && r\.target > 0 \? r\.target : null,/);
  const section = readFileSync(KPI_SECTION, 'utf8');
  assert.match(section, /const goals = await loadHomeGoals\(lang\);/);
  assert.match(section, /\{goals\.map\(\(g\) => \{/);
});

// ─── Test 3: exec_portfolio_health function exists ───

test('exec_portfolio_health RPC exists in migrations', () => {
  const exists = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(?:public\.)?exec_portfolio_health/i.test(allSQL);
  assert.ok(exists, 'exec_portfolio_health function not found in migrations');
});

// ─── Test 4: exec_portfolio_health is SECURITY DEFINER ───

test('exec_portfolio_health is SECURITY DEFINER', () => {
  const match = allSQL.match(/exec_portfolio_health[\s\S]*?SECURITY\s+DEFINER/i);
  assert.ok(match, 'exec_portfolio_health must be SECURITY DEFINER');
});

// ─── Test 5: All 9 metric_keys are computed in exec_portfolio_health ───

test('exec_portfolio_health computes all 9 expected metric_keys', () => {
  // p171 TIER C — findFunctionBody anchored em FUNCTION declaration (vs DO blocks)
  const body = findFunctionBody('exec_portfolio_health', allSQL);
  assert.ok(body, 'exec_portfolio_health body not found');

  for (const key of EXPECTED_METRICS) {
    const found = body.includes(`'${key}'`);
    assert.ok(found, `metric_key '${key}' not found in exec_portfolio_health body`);
  }
});

// ─── Test 6: portfolio_kpi_targets table has seed data for all 9 metrics ───

test('portfolio_kpi_targets is seeded with all 9 metrics for cycle3-2026', () => {
  for (const key of EXPECTED_METRICS) {
    const pattern = new RegExp(`'${key}'`, 'i');
    const found = allSQL.match(new RegExp(`INSERT\\s+INTO\\s+(?:public\\.)?portfolio_kpi_targets[\\s\\S]*?${key}`, 'i'));
    assert.ok(found, `portfolio_kpi_targets missing seed for '${key}'`);
  }
});

// ─── Test 7: Quarterly targets table exists ───

test('portfolio_kpi_quarterly_targets table is created in migrations', () => {
  const exists = /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:public\.)?portfolio_kpi_quarterly_targets/i.test(allSQL);
  assert.ok(exists, 'portfolio_kpi_quarterly_targets table not found in migrations');
});

// ─── Test 8: no metric is dropped or hand-mapped on the way to the screen ───

test('the goal block renders every row exec_portfolio_health returns, without a per-metric map', () => {
  const homeData = readFileSync(HOME_DATA, 'utf8');
  const section = readFileSync(KPI_SECTION, 'utf8');
  // a hand-written metric -> label map is how a metric silently disappeared before (static list of 9)
  for (const key of EXPECTED_METRICS) {
    assert.ok(!section.includes(key), `KpiSection.astro names '${key}': goals must come from the RPC, not a map`);
  }
  // #2553 D9: no value filter either; a goal whose computation fails stays on screen as "data unavailable"
  const loader = homeData.match(/export async function loadHomeGoals[\s\S]*?return goals\.length \? goals : null;/)?.[0] ?? '';
  assert.ok(loader, 'loadHomeGoals not found');
  assert.doesNotMatch(loader, /\.filter\(/, 'a filter in loadHomeGoals would silently drop a goal');
});

// ─── Test 9: Color thresholds use green/yellow/red status ───

test('exec_portfolio_health uses green/yellow/red status classification', () => {
  // p171 TIER C — findFunctionBody anchored em FUNCTION declaration (vs DO blocks)
  const body = findFunctionBody('exec_portfolio_health', allSQL);
  assert.ok(body, 'exec_portfolio_health body not found');

  assert.ok(body.includes("'green'"), 'exec_portfolio_health must use green status');
  assert.ok(body.includes("'yellow'"), 'exec_portfolio_health must use yellow status');
  assert.ok(body.includes("'red'"), 'exec_portfolio_health must use red status');
});
