/**
 * Contract: #1446 — get_selection_dashboard(NULL) defaults to the current OPEN cycle,
 * not the most-recently-created row.
 *
 * Bug: the default-cycle resolution used `ORDER BY created_at DESC LIMIT 1`. A historical
 * cycle re-imported later (cycle2-2025 imported 2026-07-13, status=closed) got a newer
 * created_at than the only open cycle (cycle4-2026, created 2026-05-09) and hijacked the
 * default, so /admin/selection, GpActionTodayWidget and the MCP surface opened on the wrong
 * cycle. Fix (migration 20260805000468): `ORDER BY (status = 'open') DESC, created_at DESC`.
 * Verified live (impersonated): no-arg -> cycle4-2026 (open); stats structure + app count
 * unchanged for an explicit cycle; deterministic within a snapshot.
 *
 * Asserts (static, always run) + forward-defense (no later migration reverts the default).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const FIX = '20260805000468_1446_selection_dashboard_default_open_cycle.sql';
const FIX_FILE = resolve(MIGRATIONS_DIR, FIX);

// Extract the CREATE OR REPLACE FUNCTION ... $function$ ... $function$ block for the dashboard.
function dashboardBlock(body) {
  const re = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.get_selection_dashboard\s*\([\s\S]*?\$function\$[\s\S]*?\$function\$/i;
  return body.match(re)?.[0] || '';
}

// Isolate the ELSE branch of the default-cycle resolution (the only line that changes).
function defaultElseBranch(block) {
  const re = /ELSE\s*(?:--[^\n]*\n\s*)*SELECT\s+id\s+INTO\s+v_cycle_id\s+FROM\s+public\.selection_cycles[\s\S]*?LIMIT\s+1\s*;/i;
  return block.match(re)?.[0] || '';
}

test('1446: fix migration exists', () => {
  assert.ok(existsSync(FIX_FILE), `migration must exist at ${FIX_FILE}`);
});

test('1446: default-cycle ELSE prefers the OPEN cycle, not bare created_at DESC', () => {
  const block = dashboardBlock(readFileSync(FIX_FILE, 'utf8'));
  assert.ok(block, 'get_selection_dashboard CREATE OR REPLACE block must be present');
  const elseBranch = defaultElseBranch(block);
  assert.ok(elseBranch, 'default-cycle ELSE branch must be present');
  // Must order by open-status first.
  assert.match(elseBranch, /ORDER\s+BY\s+\(\s*status\s*=\s*'open'\s*\)\s+DESC\s*,\s*created_at\s+DESC/i,
    "default must be ORDER BY (status = 'open') DESC, created_at DESC");
  // The bare newest-created default must be gone from the ELSE branch.
  assert.doesNotMatch(elseBranch, /ORDER\s+BY\s+created_at\s+DESC\s+LIMIT\s+1/i,
    'the bare created_at-only default must not survive');
});

test('1446: dashboard payload not accidentally stripped (gate change, not a payload change)', () => {
  const block = dashboardBlock(readFileSync(FIX_FILE, 'utf8'));
  for (const field of ['cycle', 'applications', 'stats', 'total', 'approved', 'shadow_vep_count']) {
    assert.match(block, new RegExp(`'${field}'`),
      `dashboard must still return ${field}`);
  }
});

function subsequentMigrations() {
  const all = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  const idx = all.indexOf(FIX);
  assert.ok(idx >= 0, 'fix migration must be in the registry');
  return all.slice(idx + 1).map((f) => ({ name: f, body: readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8') }));
}

test('1446: no later migration reverts the default to bare created_at DESC', () => {
  const offenders = [];
  for (const m of subsequentMigrations()) {
    const block = dashboardBlock(m.body);
    if (!block) continue;
    const elseBranch = defaultElseBranch(block);
    if (elseBranch && /ORDER\s+BY\s+created_at\s+DESC\s+LIMIT\s+1/i.test(elseBranch)
        && !/\(\s*status\s*=\s*'open'\s*\)/i.test(elseBranch)) {
      offenders.push(m.name);
    }
  }
  assert.equal(offenders.length, 0,
    `get_selection_dashboard must keep the open-cycle-preferring default. Offenders: ${offenders.join(', ')}`);
});
