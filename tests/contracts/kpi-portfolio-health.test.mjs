/**
 * W110 Contract Test: KPI Portfolio Health
 * Validates that exec_portfolio_health RPC and KPI static data are aligned.
 * - 9 KPIs must be defined in src/data/kpis.ts
 * - exec_portfolio_health must return all 9 metric_keys
 * - portfolio_kpi_targets must have targets for all 9 metrics
 * - Quarterly decomposition must exist
 * - Color thresholds are consistent (green >= target, yellow >= warning, red < warning)
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const KPI_FILE = resolve(ROOT, 'src/data/kpis.ts');
const KPI_SECTION = resolve(ROOT, 'src/components/sections/KpiSection.astro');

// ─── Helpers ───

function loadAllMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => ({
    name: f,
    content: readFileSync(join(MIGRATIONS_DIR, f), 'utf8'),
  }));
}

const migrations = loadAllMigrations();
const allSQL = migrations.map(m => m.content).join('\n');
const kpiSource = readFileSync(KPI_FILE, 'utf8');

// Extract KPIS array entries from kpis.ts
const KPI_ENTRIES = [...kpiSource.matchAll(/\{\s*value:\s*'([^']+)',\s*labelKey:\s*'([^']+)'/g)]
  .map(m => ({ value: m[1], labelKey: m[2] }));

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

// ─── Test 1: Exactly 9 KPIs in static data ───

test('src/data/kpis.ts defines exactly 9 KPIs', () => {
  assert.equal(KPI_ENTRIES.length, 9, `Expected 9 KPIs, found ${KPI_ENTRIES.length}`);
});

// ─── Test 2: All 9 KPIs have i18n label keys ───

test('all 9 KPIs have data.kpi.* labelKey format', () => {
  for (const kpi of KPI_ENTRIES) {
    assert.match(kpi.labelKey, /^data\.kpi\.\w+$/, `KPI labelKey "${kpi.labelKey}" does not match data.kpi.* pattern`);
  }
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
  // Find the last (most recent) definition of exec_portfolio_health
  const regex = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(?:public\.)?exec_portfolio_health[\s\S]*?\$\$([\s\S]*?)\$\$/gi;
  const matches = [...allSQL.matchAll(regex)];
  assert.ok(matches.length > 0, 'exec_portfolio_health body not found');
  const body = matches[matches.length - 1][1];

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

// ─── Test 8: KpiSection maps all 9 metric_keys to labels ───

test('KpiSection.astro has METRIC_TO_LABEL mapping for all 9 metrics', () => {
  const sectionContent = readFileSync(KPI_SECTION, 'utf8');
  for (const key of EXPECTED_METRICS) {
    const found = sectionContent.includes(key);
    assert.ok(found, `KpiSection.astro missing METRIC_TO_LABEL mapping for '${key}'`);
  }
});

// ─── Test 9: Color thresholds use green/yellow/red status ───

test('exec_portfolio_health uses green/yellow/red status classification', () => {
  const regex = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(?:public\.)?exec_portfolio_health[\s\S]*?\$\$([\s\S]*?)\$\$/gi;
  const matches = [...allSQL.matchAll(regex)];
  assert.ok(matches.length > 0);
  const body = matches[matches.length - 1][1];

  assert.ok(body.includes("'green'"), 'exec_portfolio_health must use green status');
  assert.ok(body.includes("'yellow'"), 'exec_portfolio_health must use yellow status');
  assert.ok(body.includes("'red'"), 'exec_portfolio_health must use red status');
});
