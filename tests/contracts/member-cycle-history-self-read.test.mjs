/**
 * GAP-181.B contract test — member_cycle_history self-read RLS scope.
 *
 * Static analysis tripwire over migration files. Validates:
 *   1. A `mch_self_read` policy exists in some migration with the canonical
 *      shape: FOR SELECT TO authenticated, USING member_id maps to
 *      auth.uid() via members.auth_id.
 *   2. The pre-existing `mch_superadmin_write` policy is NOT dropped in any
 *      later migration (cross-member visibility for superadmins preserved).
 *
 * Why this matters:
 *   - Pre-p188 the table had only mch_superadmin_write (polcmd=ALL). Non-
 *     superadmin members holding GRANT SELECT had every read blocked by
 *     RLS, so gamification.astro:1012 + profile.astro:367 rendered "0 cycles"
 *     silently. This is a pre-existing bug (the table was defined with
 *     strict superadmin-only RLS) that was made visible during V4 audit.
 *   - p188 added mch_self_read with strict self-scope (member_id IN
 *     SELECT id FROM members WHERE auth_id = auth.uid()).
 *   - If a future migration drops the self-read policy OR weakens the scope
 *     (e.g., to all-members like course_progress), this test fails the build.
 *   - notes column may contain admin-authored context; relaxing scope would
 *     surface that data unintentionally.
 *
 * Scope: static analysis on migration text. Fast, no DB env required.
 * Live behavior was verified in p188 session via MCP execute_sql JWT-
 * simulated tests (Sarah JWT: own_visible=4, sees_other_member=0).
 *
 * Origin: handoff p188 direction B1 (GAP-181.B closure).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const MIGRATIONS_DIR = resolve(process.cwd(), 'supabase/migrations');

function loadMigrations() {
  return readdirSync(MIGRATIONS_DIR)
    .filter(f => f.endsWith('.sql'))
    .sort()
    .map(f => ({ name: f, content: readFileSync(join(MIGRATIONS_DIR, f), 'utf8') }));
}

const migrations = loadMigrations();

test('GAP-181.B: mch_self_read policy exists with canonical shape', () => {
  const matches = migrations
    .map(m => {
      // Match CREATE POLICY mch_self_read ... ON public.member_cycle_history ... ;
      const re = /CREATE\s+POLICY\s+["`]?mch_self_read["`]?\s+ON\s+(?:public\.)?member_cycle_history[\s\S]*?;/gi;
      const found = m.content.match(re);
      return found ? { name: m.name, body: found[0] } : null;
    })
    .filter(Boolean);

  assert.ok(matches.length > 0,
    'No CREATE POLICY mch_self_read found in any migration. ' +
    'p188 GAP-181.B fix may have been removed — non-superadmin members would lose ' +
    'read access to own member_cycle_history rows (gamification + profile would render "0 cycles").');

  // Inspect the latest (last in sort order) definition
  const latest = matches[matches.length - 1];

  assert.match(
    latest.body,
    /FOR\s+SELECT/i,
    `mch_self_read in ${latest.name} must be FOR SELECT (read-only). Got: ${latest.body}`
  );

  assert.match(
    latest.body,
    /TO\s+authenticated/i,
    `mch_self_read in ${latest.name} must target the authenticated role. Got: ${latest.body}`
  );

  // Verify the USING clause derives caller's member_id via auth.uid() lookup
  assert.match(
    latest.body,
    /member_id\s+IN\s*\(\s*SELECT\s+id\s+FROM\s+(?:public\.)?members\s+WHERE\s+auth_id\s*=\s*auth\.uid\(\)\s*\)/i,
    `mch_self_read in ${latest.name} must scope to caller's own rows via ` +
    `member_id IN (SELECT id FROM members WHERE auth_id = auth.uid()). ` +
    `Relaxing this scope would surface other members' notes/cycles. Got: ${latest.body}`
  );
});

test('GAP-181.B: mch_superadmin_write policy NOT dropped (cross-member visibility preserved)', () => {
  const dropMatches = migrations
    .map(m => {
      const re = /DROP\s+POLICY\s+(?:IF\s+EXISTS\s+)?["`]?mch_superadmin_write["`]?\s+ON\s+(?:public\.)?member_cycle_history/gi;
      return re.test(m.content) ? m.name : null;
    })
    .filter(Boolean);

  // A drop is acceptable only if it is followed by a re-CREATE in the same
  // or later migration. Find the latest drop and verify the policy is
  // recreated somewhere AFTER it.
  if (dropMatches.length > 0) {
    const latestDrop = dropMatches[dropMatches.length - 1];
    const recreate = migrations
      .filter(m => m.name >= latestDrop)
      .some(m => /CREATE\s+POLICY\s+["`]?mch_superadmin_write["`]?\s+ON\s+(?:public\.)?member_cycle_history/i.test(m.content));

    assert.ok(recreate,
      `DROP POLICY mch_superadmin_write found in ${latestDrop} but no later ` +
      `CREATE POLICY for the same name. Superadmin cross-member visibility would be lost.`);
  }

  // Sanity: at least one CREATE POLICY mch_superadmin_write exists somewhere
  const hasCreate = migrations.some(m =>
    /CREATE\s+POLICY\s+["`]?mch_superadmin_write["`]?\s+ON\s+(?:public\.)?member_cycle_history/i.test(m.content)
  );
  assert.ok(hasCreate,
    'No CREATE POLICY mch_superadmin_write found in any migration. ' +
    'Superadmin write/cross-member-read access to member_cycle_history would be missing.');
});
