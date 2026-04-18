/**
 * ADR-0016 D6 — Static contract: approval_chains/approval_signoffs SELECT
 * policies must NOT use `USING (true)` after the tighten migration.
 *
 * Gap this test closes: IP-1 base migration created scaffolding policies
 * `approval_chains_read_all_auth` and `approval_signoffs_read_all_auth` with
 * `USING (true)` (world-authenticated-open). Platform-guardian (2026-04-20 p32)
 * flagged this; IP-2 migration `20260430030000_ip2_tighten_approval_rls.sql`
 * replaces them with visibility-scoped policies. A regression (adding a new
 * migration that reintroduces USING (true) on these tables' SELECT) would
 * re-open the subsystem. This test catches that statically.
 *
 * Why static: invariants are dynamic DB checks; this is about migration
 * authorship intent. A CREATE POLICY added later can't hide behind "it'll
 * be caught if someone tests it" — the signature must be visible in diff.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const MIGRATIONS_DIR = resolve(process.cwd(), 'supabase/migrations');

// Effective from the tighten migration itself. Earlier migrations (IP-1 base)
// legitimately contain USING (true) because the tighten wasn't written yet.
const CUTOVER = '20260430030000';

const PROTECTED_TABLES = ['approval_chains', 'approval_signoffs'];

function listMigrations() {
  return readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort();
}

function isAfterCutover(filename) {
  const version = filename.match(/^(\d{14})/)?.[1];
  return version && version >= CUTOVER;
}

/**
 * Strips SQL line comments (-- ...) from source to avoid matching
 * CREATE POLICY statements that appear inside rollback instructions.
 */
function stripSqlLineComments(sql) {
  return sql
    .split('\n')
    .map((line) => {
      const commentIdx = line.indexOf('--');
      return commentIdx >= 0 ? line.slice(0, commentIdx) : line;
    })
    .join('\n');
}

/**
 * Finds CREATE POLICY ... ON <table> FOR SELECT ... ; blocks.
 * Returns array of { table, policyName, rawBlock }. The USING clause is
 * tested by searching for `USING (true)` within rawBlock — nested parens
 * in real scoped predicates make reliable clause extraction unworthwhile.
 */
function extractSelectPolicies(sql, tablesOfInterest) {
  const sqlStripped = stripSqlLineComments(sql);
  const policies = [];
  const regex = /CREATE\s+POLICY\s+(\w+)\s+ON\s+(?:public\.)?(\w+)\s+FOR\s+SELECT[\s\S]*?;/gi;
  let m;
  while ((m = regex.exec(sqlStripped)) !== null) {
    const [rawBlock, policyName, table] = m;
    if (tablesOfInterest.includes(table)) {
      policies.push({ policyName, table, rawBlock });
    }
  }
  return policies;
}

function hasUsingTrue(rawBlock) {
  // `USING (true)` with optional whitespace/newlines. Matches only bare-true,
  // not scoped predicates that happen to contain `true` as part of a larger expr.
  return /USING\s*\(\s*true\s*\)/i.test(rawBlock);
}

test('ADR-0016 D6: tighten migration exists and defines scoped policies', () => {
  const files = listMigrations();
  const tightenFile = files.find((f) => f === '20260430030000_ip2_tighten_approval_rls.sql');
  assert.ok(tightenFile, 'Expected migration 20260430030000_ip2_tighten_approval_rls.sql to exist');

  const sql = readFileSync(join(MIGRATIONS_DIR, tightenFile), 'utf8');

  // Must drop the old open policies
  assert.match(
    sql,
    /DROP\s+POLICY\s+IF\s+EXISTS\s+approval_chains_read_all_auth/i,
    'Tighten migration must DROP the old approval_chains_read_all_auth policy',
  );
  assert.match(
    sql,
    /DROP\s+POLICY\s+IF\s+EXISTS\s+approval_signoffs_read_all_auth/i,
    'Tighten migration must DROP the old approval_signoffs_read_all_auth policy',
  );

  // Must create the new scoped policies
  assert.match(
    sql,
    /CREATE\s+POLICY\s+approval_chains_read_scoped\s+ON\s+public\.approval_chains/i,
    'Tighten migration must CREATE approval_chains_read_scoped policy',
  );
  assert.match(
    sql,
    /CREATE\s+POLICY\s+approval_signoffs_read_scoped\s+ON\s+public\.approval_signoffs/i,
    'Tighten migration must CREATE approval_signoffs_read_scoped policy',
  );
});

test('ADR-0016 D6: no migration after cutover re-introduces USING (true) on approval_* SELECT', () => {
  const files = listMigrations().filter(isAfterCutover);
  const violations = [];

  for (const file of files) {
    const sql = readFileSync(join(MIGRATIONS_DIR, file), 'utf8');
    const policies = extractSelectPolicies(sql, PROTECTED_TABLES);

    for (const p of policies) {
      if (hasUsingTrue(p.rawBlock)) {
        violations.push(
          `${file} → CREATE POLICY ${p.policyName} ON ${p.table} FOR SELECT USING (true) — ` +
            'ADR-0016 D6 forbids world-authenticated-open on approval_chains/approval_signoffs',
        );
      }
    }
  }

  assert.deepEqual(
    violations,
    [],
    'Found migrations re-introducing USING (true) on approval_* SELECT policies:\n' +
      violations.join('\n'),
  );
});

test('ADR-0016 D6: current tighten migration uses can_by_member + visibility-scoped predicates', () => {
  const sql = readFileSync(
    join(MIGRATIONS_DIR, '20260430030000_ip2_tighten_approval_rls.sql'),
    'utf8',
  );
  const policies = extractSelectPolicies(sql, PROTECTED_TABLES);

  assert.equal(policies.length, 2, 'Expected exactly 2 CREATE POLICY ... FOR SELECT (chains + signoffs)');

  for (const p of policies) {
    // Must reference can_by_member (admin branch).
    assert.match(
      p.rawBlock,
      /can_by_member\s*\([^)]*manage_member/,
      `${p.policyName}: must include can_by_member('manage_member') admin branch`,
    );
    // Must reference self-signer / ratificador / active-doc scoping.
    assert.ok(
      /signer_id|approval_signoffs|member_document_signatures/i.test(p.rawBlock),
      `${p.policyName}: must reference signer_id/approval_signoffs/member_document_signatures for visibility scoping`,
    );
    assert.ok(
      !hasUsingTrue(p.rawBlock),
      `${p.policyName}: must NOT use USING (true) — found world-open pattern`,
    );
  }
});
