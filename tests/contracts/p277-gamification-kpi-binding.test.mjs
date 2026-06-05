/**
 * Contract: p277 — gamification/global-goal KPI quick wins
 * (metric-disparity gamification probe, 2026-05-29).
 *
 * GI-5: src/data/kpis.ts chapters card carried a FALSE "Superada" (surpassedFromGoal:'8')
 *   while the live distinct-chapter count is 7 (< target 8). Removed the false claim and
 *   aligned the headline to the target (8), matching the target-as-headline convention used
 *   by every other card.
 * GI-3 (audit D10): exec_portfolio_health(p_cycle_code DEFAULT 'cycle3-2026') returned [] when
 *   passed the live cycles.is_current code ('cycle_3') because portfolio_kpi_targets is seeded
 *   only for 'cycle3-2026' (parallel namespaces). Made the cycle resolution resilient: a code
 *   with no targets falls back to the most-recently-created cycle_code that has targets, so the
 *   KPI grid can never silently zero out.
 *
 * Migration: supabase/migrations/20260805000057_p277_exec_portfolio_health_resilient_cycle.sql
 * Cross-ref: docs/audit/METRIC_DISPARITY_AUDIT_2026-05-28.md (GI-3/GI-5) · ADR-0100 window-source invariant.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATION_FILE = resolve(ROOT, 'supabase/migrations/20260805000057_p277_exec_portfolio_health_resilient_cycle.sql');
const KPIS_FILE = resolve(ROOT, 'src/data/kpis.ts');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const mig = existsSync(MIGRATION_FILE) ? readFileSync(MIGRATION_FILE, 'utf8') : '';
const kpis = existsSync(KPIS_FILE) ? readFileSync(KPIS_FILE, 'utf8') : '';

// ===================================================================
// GI-5 — kpis.ts false "Superada"
// ===================================================================

test('p277 GI-5: chapters KPI no longer claims a false "Superada"', () => {
  // pick the KPIS[] array entry (has both value: and the label), not the interface comment line
  const chaptersLine = kpis.split('\n').find((l) => l.includes('data.kpi.chapters') && l.includes('value:')) || '';
  assert.ok(chaptersLine, 'chapters KPI entry must exist');
  assert.ok(!/surpassedFromGoal/.test(chaptersLine), 'chapters must NOT carry surpassedFromGoal (live 7 < target 8 — not surpassed)');
  assert.match(chaptersLine, /value:\s*'8'/, 'chapters headline must align to the target (8), matching the target-as-headline convention');
});

test('p277 GI-5 forward-defense: no KPI claims surpassed below its goal (chapters specifically)', () => {
  // The only surpassedFromGoal that existed was the false chapters one. Lock it out.
  assert.ok(
    !/data\.kpi\.chapters[^\n]*surpassedFromGoal/.test(kpis) && !/surpassedFromGoal[^\n]*data\.kpi\.chapters/.test(kpis),
    'chapters must never re-introduce a surpassedFromGoal while live < target'
  );
});

// ===================================================================
// GI-3 — exec_portfolio_health resilient cycle resolution
// ===================================================================

test('p277 GI-3: migration file exists + same-signature CREATE OR REPLACE + default preserved', () => {
  assert.ok(existsSync(MIGRATION_FILE), `Migration must exist at ${MIGRATION_FILE}`);
  assert.match(mig, /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.exec_portfolio_health\(p_cycle_code text DEFAULT 'cycle3-2026'/i, 'same signature + default preserved');
  assert.ok(!/DROP\s+FUNCTION/i.test(mig), 'no DROP (same signature)');
  assert.match(mig, /SECURITY DEFINER/i);
  assert.match(mig, /SET search_path TO 'public', 'pg_temp'/i);
  assert.match(mig, /NOTIFY\s+pgrst/i);
});

test('p277 GI-3: resilient cycle resolution falls back to a cycle_code that has targets', () => {
  assert.match(mig, /v_cycle_code\s*:=\s*NULLIF\(trim\(p_cycle_code\),\s*''\)/i, 'must normalize the requested code');
  assert.match(mig, /NOT\s+EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+public\.portfolio_kpi_targets\s+WHERE\s+cycle_code\s*=\s*v_cycle_code\s*\)/i, 'must detect a code with no targets');
  assert.match(mig, /SELECT\s+cycle_code\s+INTO\s+v_cycle_code[\s\S]*?FROM\s+public\.portfolio_kpi_targets[\s\S]*?ORDER\s+BY\s+MAX\(created_at\)\s+DESC\s+LIMIT\s+1/i, 'fallback = most-recently-created cycle_code with targets');
  // the FOR loop must iterate on the RESOLVED code, not the raw param
  assert.match(mig, /FROM\s+public\.portfolio_kpi_targets\s+WHERE\s+cycle_code\s*=\s*v_cycle_code\s+ORDER\s+BY\s+display_order/i, 'loop must use the resolved v_cycle_code');
});

// ===================================================================
// DB-gated — live behavior
// ===================================================================

test('p277 GI-3 DB: default + current-cycle-namespace + bogus codes all return the full metric set (never empty)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const def = await sb.rpc('exec_portfolio_health');
  assert.ok(!def.error, `default call should not error: ${def.error?.message}`);
  const n = (def.data || []).length;
  assert.ok(n > 0, 'default must return a non-empty metric set');
  // 'cycle_3' is the live cycles.is_current code that has NO targets — must fall back, not return []
  const cyc3 = await sb.rpc('exec_portfolio_health', { p_cycle_code: 'cycle_3' });
  assert.equal((cyc3.data || []).length, n, "passing cycles.is_current code ('cycle_3') must fall back to the full set, not empty");
  const bogus = await sb.rpc('exec_portfolio_health', { p_cycle_code: 'bogus-xyz' });
  assert.equal((bogus.data || []).length, n, 'an unknown code must fall back to the full set, not empty');
});
