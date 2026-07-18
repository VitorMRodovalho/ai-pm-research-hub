/**
 * Contract: #1419 — get_governance_dashboard read gate is AUTHORITATIVE, not bare rls_is_member().
 *
 * #1408 (defense-in-depth of #1397) narrowed the CR *approval* read surface
 * (get_cr_approval_status + the cr_approvals SELECT policy) to rls_is_authoritative_member().
 * get_governance_dashboard was still gated on the broad rls_is_member() (row-existence only,
 * no is_active filter), so any member row — inactive/offboarded members and pre-onboarding
 * guests — could read the FULL body of every pending change request plus the quorum stats.
 * This is the RPC-body analog of the policy sweep in 20260805000246_rls_phase2_authoritative_member.sql
 * (which left function bodies untouched).
 *
 * Fix (migration 20260805000464): swap the single guard rls_is_member() -> rls_is_authoritative_member()
 * and return 'not_authorized'. Verified live (impersonated): guest -> {error:'not_authorized'};
 * authoritative member -> full dashboard, can_approve preserved.
 *
 * Asserts (static, always run) + forward-defense (no later migration reverts the guard).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const FIX = '20260805000464_1419_governance_dashboard_authoritative_gate.sql';
const FIX_FILE = resolve(MIGRATIONS_DIR, FIX);

// Extract the CREATE OR REPLACE FUNCTION ... $function$ ... $function$ block for the dashboard.
function dashboardBlock(body) {
  const re = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.get_governance_dashboard\s*\([\s\S]*?\$function\$[\s\S]*?\$function\$/i;
  return body.match(re)?.[0] || '';
}

test('1419: fix migration exists', () => {
  assert.ok(existsSync(FIX_FILE), `migration must exist at ${FIX_FILE}`);
});

test('1419: dashboard guard uses rls_is_authoritative_member (not bare rls_is_member)', () => {
  const block = dashboardBlock(readFileSync(FIX_FILE, 'utf8'));
  assert.ok(block, 'get_governance_dashboard CREATE OR REPLACE block must be present');
  assert.match(block, /IF\s+NOT\s+public\.rls_is_authoritative_member\(\)\s+THEN/i,
    'guard must gate on rls_is_authoritative_member()');
  // bare rls_is_member() must not appear (rls_is_authoritative_member matches on a different name)
  assert.doesNotMatch(block, /[^_]rls_is_member\s*\(/i,
    'guard must not keep the broad bare rls_is_member()');
  assert.match(block, /'not_authorized'/, 'unauthorized callers must get the not_authorized code');
});

test('1419: dashboard still serves CR bodies + quorum (no accidental content strip)', () => {
  const block = dashboardBlock(readFileSync(FIX_FILE, 'utf8'));
  for (const field of ['pending_crs', 'proposed_changes', 'quorum_needed', 'my_vote', 'can_approve']) {
    assert.match(block, new RegExp(`'${field}'`),
      `dashboard must still return ${field} (narrowing is a gate change, not a payload change)`);
  }
});

function subsequentMigrations() {
  const all = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  const idx = all.indexOf(FIX);
  assert.ok(idx >= 0, 'fix migration must be in the registry');
  return all.slice(idx + 1).map((f) => ({ name: f, body: readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8') }));
}

test('1419: no later migration reverts the dashboard guard to bare rls_is_member()', () => {
  const offenders = [];
  for (const m of subsequentMigrations()) {
    const block = dashboardBlock(m.body);
    if (block && /[^_]rls_is_member\s*\(/i.test(block) && !/rls_is_authoritative_member/i.test(block)) {
      offenders.push(m.name);
    }
  }
  assert.equal(offenders.length, 0,
    `get_governance_dashboard must keep the authoritative gate. Offenders: ${offenders.join(', ')}`);
});
