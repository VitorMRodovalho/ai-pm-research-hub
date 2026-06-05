/**
 * #483 contract test — current_cycle_active must be false for terminal member_status
 *
 * Bug: offboarding (admin_offboard_member) flipped member_status -> alumni/inactive,
 * is_active -> false, role, designations -> '{}' but NEVER cleared
 * current_cycle_active (CCA). The sync_member_status_consistency() BEFORE-trigger
 * coerced is_active/role/designations on the same UPDATE OF member_status, yet left
 * CCA untouched. 3 offboarded members (Andressa Martins, Maria Luiza, Herlon)
 * carried CCA=true, contradicting "active in the current cycle" and feeding the
 * get_gamification_leaderboard / get_public_leaderboard cohort's CCA=true branch.
 *
 * Fix (migration 20260805000117):
 *   - extend the B-trigger to also reset current_cycle_active=false for
 *     observer/alumni/inactive (covers every path touching member_status).
 *   - one-time DML to clear the already-drifted rows.
 *
 * Why static + DB-gated (not behavioural): the trigger is BEFORE UPDATE OF
 * member_status and its CCA clause is trivially correct by inspection; per house
 * convention we assert the migration body statically + the live data invariant
 * (no terminal-status member carries CCA=true). The DB-gated invariant is the
 * CI-time equivalent of the deferred check_schema_invariants() B2 row.
 *
 * NOT in scope (routed to #419/#421): the leaderboard cohort gate lacks an
 * is_active filter, so offboarded members WITH current-cycle points still surface
 * via the `OR EXISTS current-cycle points` branch. This fix only addresses the
 * CCA drift, not that predicate.
 *
 * Cross-ref: #483, #419/#421 (canonical "active now" predicate), #482 (founder muting).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const FIX_FILE = '20260805000117_483_reset_current_cycle_active_on_terminal_status.sql';
const FIX = readFileSync(join(MIGRATIONS_DIR, FIX_FILE), 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── (A) static: the fix migration redeclares the trigger + adds the CCA reset clause ──
test('#483: fix migration redeclares sync_member_status_consistency', () => {
  assert.ok(FIX, 'fix migration file present');
  assert.match(FIX, /CREATE OR REPLACE FUNCTION public\.sync_member_status_consistency\(\)/);
});

test('#483: trigger resets current_cycle_active for terminal member_status', () => {
  // the new clause: terminal status -> CCA false
  assert.match(
    FIX,
    /member_status\s+IN\s*\(\s*'observer'\s*,\s*'alumni'\s*,\s*'inactive'\s*\)\s+AND\s+NEW\.current_cycle_active\s*=\s*true\s+THEN\s+NEW\.current_cycle_active\s*:=\s*false/i,
    'trigger body must reset current_cycle_active=false on terminal member_status'
  );
});

test('#483: migration includes a one-time reconciliation UPDATE', () => {
  assert.match(
    FIX,
    /UPDATE\s+public\.members\s+SET\s+current_cycle_active\s*=\s*false\s+WHERE\s+member_status\s+IN\s*\(\s*'observer'\s*,\s*'alumni'\s*,\s*'inactive'\s*\)\s+AND\s+current_cycle_active\s*=\s*true/i,
    'migration must one-time-clear existing terminal-status CCA drift'
  );
});

test('#483: migration is registered (timestamp greater than prior head)', () => {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  const idx = files.indexOf(FIX_FILE);
  assert.ok(idx >= 0, 'fix migration present in migrations dir');
  // sanity: this is among the latest few migrations
  assert.ok(idx >= files.length - 12, 'fix migration is recent (sort order)');
});

// ── (B) DB-gated invariant: no terminal-status member carries current_cycle_active=true ──
test('#483 DB: no terminal-status member has current_cycle_active=true', { skip: !dbGated && skipMsg }, async () => {
  const supa = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await supa
    .from('members')
    .select('id,name,member_status,current_cycle_active')
    .in('member_status', ['observer', 'alumni', 'inactive'])
    .eq('current_cycle_active', true)
    .not('name', 'ilike', '%_synthetic%');
  assert.equal(error, null, error ? `members query failed: ${error.message}` : '');
  // No name carve-out: any terminal-status member with CCA=true is real drift we want to catch.
  // (synthetic test fixtures excluded above to avoid cross-test noise.)
  const drift = data || [];
  assert.equal(
    drift.length,
    0,
    `Expected 0 terminal-status members with current_cycle_active=true; got ${drift.length}: ${drift
      .map((m) => `${m.name} (${m.member_status})`)
      .join(', ')}`
  );
});
