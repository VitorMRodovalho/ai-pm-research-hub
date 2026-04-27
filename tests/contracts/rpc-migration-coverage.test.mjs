/**
 * Track Q-C contract — RPC migration-coverage allowlist.
 *
 * Asserts that every public-schema function in pg_proc has at least one
 * `CREATE [OR REPLACE] FUNCTION public.<name>(` block in
 * supabase/migrations/, EXCEPT for the documented orphan allowlist captured
 * during the p50 audit (docs/audit/RPC_BODY_DRIFT_AUDIT_P50_ORPHAN_LIST.txt).
 *
 * Three failure paths are intentional:
 *   1. NEW orphan: a function exists in DB but no migration defines it AND
 *      it is not in the legacy allowlist. The author either adds a migration
 *      that captures the body, or (after team decision) extends the allowlist
 *      with a comment explaining why.
 *   2. RESOLVED orphan: an allowlisted function is now captured by a
 *      migration. The author removes the name from the allowlist, ratcheting
 *      drift cleanup forward.
 *   3. EXTINCT orphan: an allowlisted function no longer exists in DB. Same
 *      remediation — remove from allowlist.
 *
 * Requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY for the DB-aware
 * assertions. The size-baseline assertion runs offline.
 *
 * Run locally:
 *   SUPABASE_URL=https://…supabase.co SUPABASE_SERVICE_ROLE_KEY=eyJ… \
 *   node --test tests/contracts/rpc-migration-coverage.test.mjs
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const ORPHAN_ALLOWLIST_PATH = resolve(
  ROOT,
  'docs/audit/RPC_BODY_DRIFT_AUDIT_P50_ORPHAN_LIST.txt'
);
const ALLOWLIST_BASELINE_SIZE = 0;
const TABLE_DRIFT_ALLOWLIST_PATH = resolve(
  ROOT,
  'docs/audit/TABLE_DRIFT_ALLOWLIST_P64.txt'
);
// Pacote M / ADR-0029 retroactive retirement: 17 ingestion/release-readiness/
// governance-bundle substrate tables + adjacent tables acknowledged as
// extinct without DROP TABLE migration capture. Going forward this baseline
// must NOT grow — every new entry requires a retirement ADR + PM ack.
const TABLE_DRIFT_BASELINE_SIZE = 17;

function loadAllMigrationsConcat() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => readFileSync(join(MIGRATIONS_DIR, f), 'utf8')).join('\n');
}

function loadAllowlist() {
  const raw = readFileSync(ORPHAN_ALLOWLIST_PATH, 'utf8');
  return new Set(
    raw
      .split('\n')
      .map(s => s.trim())
      .filter(s => s.length > 0 && !s.startsWith('#'))
  );
}

function buildCreateMatcher(name) {
  // CREATE [OR REPLACE] FUNCTION ["public".]"name"(  — case-insensitive,
  // tolerates quoted identifiers, anchored on the trailing paren.
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(
    `\\bCREATE\\s+(OR\\s+REPLACE\\s+)?FUNCTION\\s+"?(public\\.)?"?${escaped}"?\\s*\\(`,
    'i'
  );
}

async function callAuditRpc() {
  const url = `${SUPABASE_URL}/rest/v1/rpc/_audit_list_public_functions`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({}),
  });
  if (!res.ok) {
    throw new Error(`audit RPC failed: ${res.status} ${await res.text()}`);
  }
  return res.json();
}

async function callTablesAuditRpc() {
  const url = `${SUPABASE_URL}/rest/v1/rpc/_audit_list_public_tables`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({}),
  });
  if (!res.ok) {
    throw new Error(`tables audit RPC failed: ${res.status} ${await res.text()}`);
  }
  return res.json();
}

async function callRevokedFnsRlsRefsAuditRpc() {
  const url = `${SUPABASE_URL}/rest/v1/rpc/_audit_list_revoked_secdef_fns_with_rls_refs`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({}),
  });
  if (!res.ok) {
    throw new Error(`revoked-fns RLS-refs audit RPC failed: ${res.status} ${await res.text()}`);
  }
  return res.json();
}

function loadTableDriftAllowlist() {
  const raw = readFileSync(TABLE_DRIFT_ALLOWLIST_PATH, 'utf8');
  return new Set(
    raw
      .split('\n')
      .map(s => s.trim())
      .filter(s => s.length > 0 && !s.startsWith('#'))
  );
}

function buildCreateTableMatcher(name) {
  // CREATE TABLE [IF NOT EXISTS] ["public".]"name" — case-insensitive,
  // tolerates IF NOT EXISTS clause and quoted identifiers.
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(
    `\\bCREATE\\s+TABLE\\s+(IF\\s+NOT\\s+EXISTS\\s+)?"?(public\\.)?"?${escaped}"?\\s*\\(`,
    'i'
  );
}

function buildDropTableMatcher(name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(
    `\\bDROP\\s+TABLE\\s+(IF\\s+EXISTS\\s+)?"?(public\\.)?"?${escaped}"?\\b`,
    'i'
  );
}

function extractCreateTableNames(sql) {
  // Extract all CREATE TABLE [IF NOT EXISTS] [public.]name from the concat'd SQL.
  // Returns Set of table names (deduped).
  const regex = /\bCREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?"?(?:public\.)?"?([a-z_][a-z0-9_]*)"?\s*\(/gi;
  const out = new Set();
  let m;
  while ((m = regex.exec(sql)) !== null) {
    out.add(m[1]);
  }
  return out;
}

test(
  'Track Q-C: no NEW orphan functions vs allowlist',
  { skip: !canRun && skipMsg },
  async () => {
    const rows = await callAuditRpc();
    const allowlist = loadAllowlist();
    const allSQL = loadAllMigrationsConcat();

    const dbNames = new Set(rows.map(r => r.proname));
    const currentOrphans = [...dbNames].filter(n => !buildCreateMatcher(n).test(allSQL));

    const newOrphans = currentOrphans.filter(n => !allowlist.has(n));
    if (newOrphans.length > 0) {
      assert.fail(
        `NEW orphan function(s) detected. Add a CREATE [OR REPLACE] FUNCTION ` +
          `migration that captures the body, or (after team decision) extend ` +
          `the allowlist at ${ORPHAN_ALLOWLIST_PATH}.\n\n` +
          `New orphans:\n  ${newOrphans.sort().join('\n  ')}`
      );
    }
  }
);

test(
  'Track Q-C: allowlist stays in sync (no resolved-or-extinct entries)',
  { skip: !canRun && skipMsg },
  async () => {
    const rows = await callAuditRpc();
    const allowlist = loadAllowlist();
    const allSQL = loadAllMigrationsConcat();

    const dbNames = new Set(rows.map(r => r.proname));

    const stale = [...allowlist].filter(name => {
      const stillInDb = dbNames.has(name);
      const captured = buildCreateMatcher(name).test(allSQL);
      return !stillInDb || captured;
    });

    if (stale.length > 0) {
      assert.fail(
        `Allowlist contains entries that are no longer orphans. Remove them ` +
          `from ${ORPHAN_ALLOWLIST_PATH} (drift cleanup ratcheting down) and ` +
          `update ALLOWLIST_BASELINE_SIZE in this test file:\n\n  ` +
          stale.sort().join('\n  ')
      );
    }
  }
);

test('Track Q-C: allowlist file size matches p52 baseline (empty after Q-A)', () => {
  const allowlist = loadAllowlist();
  assert.equal(
    allowlist.size,
    ALLOWLIST_BASELINE_SIZE,
    `Allowlist size drifted from ${ALLOWLIST_BASELINE_SIZE} to ${allowlist.size}. ` +
      `Q-A drove the allowlist to 0 in p52. Any new orphan must either be ` +
      `captured by a migration (preferred) or added back to the allowlist with ` +
      `a justification AND a corresponding bump of ALLOWLIST_BASELINE_SIZE.`
  );
});

// ============================================================================
// Pacote M Phase 4 / ADR-0029 R2 — Table-level DDL drift detection
//
// Catches the bug class that allowed the ingestion/release-readiness/governance-
// bundle subsystem (14+ tables) to be silently dropped via Supabase Dashboard
// SQL editor or execute_sql MCP without DROP TABLE migration capture. p50 audit
// only covered fn-body drift; tables escaped scrutiny until ADR-0028 Phase 1
// audit surfaced the orphan SECDEF functions referencing missing substrate.
//
// Two failure paths:
//   1. NEW orphan TABLE: in DB, no CREATE TABLE migration AND not in
//      table-drift allowlist. Either author adds the migration capture, or
//      (after team decision) extends the allowlist with rationale.
//   2. EXTINCT TABLE: CREATE TABLE in migration, no DROP TABLE in migration,
//      but absent from live DB → silent drop drift (the ADR-0029 incident
//      pattern). Author either adds DROP TABLE migration, or adds entry to
//      allowlist with retirement-ADR justification.
// ============================================================================

test(
  'Pacote M Phase 4: no NEW orphan tables vs migration capture',
  { skip: !canRun && skipMsg },
  async () => {
    const rows = await callTablesAuditRpc();
    const allSQL = loadAllMigrationsConcat();

    const dbTables = new Set(rows.map(r => r.table_name));
    const newOrphans = [...dbTables].filter(
      n => !buildCreateTableMatcher(n).test(allSQL)
    );

    if (newOrphans.length > 0) {
      assert.fail(
        `NEW orphan table(s) detected — exist in DB but no CREATE TABLE ` +
          `migration captures them. Add a migration via apply_migration ` +
          `(NEVER execute_sql for DDL — see GC-097 + ADR-0029 governance gap). ` +
          `If intentionally outside migration discipline (e.g., introspection ` +
          `view), document and waive explicitly.\n\n` +
          `New orphan tables:\n  ${newOrphans.sort().join('\n  ')}`
      );
    }
  }
);

test(
  'Pacote M Phase 4: no EXTINCT tables (silent drops without DROP TABLE migration)',
  { skip: !canRun && skipMsg },
  async () => {
    const rows = await callTablesAuditRpc();
    const allSQL = loadAllMigrationsConcat();
    const driftAllowlist = loadTableDriftAllowlist();

    const dbTables = new Set(rows.map(r => r.table_name));
    const createdInMigrations = extractCreateTableNames(allSQL);

    // For each table created in migrations: check if it exists in DB OR has a DROP migration.
    const extinctWithoutDrop = [...createdInMigrations].filter(name => {
      if (dbTables.has(name)) return false;  // still exists, not extinct
      if (buildDropTableMatcher(name).test(allSQL)) return false;  // legitimate DROP migration exists
      return true;  // CREATE in migration, no DB row, no DROP migration → silent drift
    });

    const newDrift = extinctWithoutDrop.filter(n => !driftAllowlist.has(n));

    if (newDrift.length > 0) {
      assert.fail(
        `SILENT TABLE DROP detected (the ADR-0029 incident class). Table(s) ` +
          `created via CREATE TABLE migration but absent from live DB AND ` +
          `no DROP TABLE migration captures the removal. Either:\n` +
          `  (a) Add a DROP TABLE migration via apply_migration (preferred), or\n` +
          `  (b) Re-create the table via apply_migration (substrate restore), or\n` +
          `  (c) Extend ${TABLE_DRIFT_ALLOWLIST_PATH} with a retirement ADR ` +
          `justification (similar to ADR-0029) AND bump TABLE_DRIFT_BASELINE_SIZE.\n\n` +
          `New silent drops:\n  ${newDrift.sort().join('\n  ')}`
      );
    }
  }
);

test('Pacote M Phase 4: table-drift allowlist size matches p64 baseline', () => {
  const allowlist = loadTableDriftAllowlist();
  assert.equal(
    allowlist.size,
    TABLE_DRIFT_BASELINE_SIZE,
    `Table-drift allowlist size drifted from ${TABLE_DRIFT_BASELINE_SIZE} to ${allowlist.size}. ` +
      `ADR-0029 acknowledged 17 silent-dropped tables in Pacote M (p64). Any ` +
      `new entry requires a retirement ADR + PM ack + corresponding bump of ` +
      `TABLE_DRIFT_BASELINE_SIZE. Ratcheting DOWN (removal) is allowed only ` +
      `when substrate is restored OR retroactive DROP TABLE migration is added.`
  );
});

// ============================================================================
// p65 Bug B sediment — pg_policy precondition contract for REVOKE migrations
//
// Catches the bug class that caused the p64 production incident: REVOKE EXECUTE
// FROM authenticated on a SECDEF function that is referenced inside an RLS
// policy expression. RLS evaluates in the caller's role context — the policy
// requires EXECUTE on the function regardless of SECDEF, so REVOKE silently
// breaks PostgREST table reads for authenticated users.
//
// The original p64 audit chain checked frontend `.rpc()` + EF source +
// `pg_proc.prosrc` SECDEF caller chain + migration history but missed the
// `pg_policy` reference scan. 48 RLS policies (every `*_v4_org_scope`) call
// `auth_org()` directly; 13 RLS policies call `can_by_member()` directly.
// REVOKE'ing both broke ~8 hours of authenticated PostgREST reads silently.
//
// Helper `_audit_list_revoked_secdef_fns_with_rls_refs()` (migration
// 20260427003953) returns SECDEF fns where:
//   1. authenticated EXECUTE is revoked (pg_catalog.has_function_privilege)
//   2. AND the function name appears in pg_policies.qual or .with_check via
//      word-boundary regex `\m(public\.)?<fn>\(`
//
// Word-boundary anchor `\m` is critical — without it, `can(` matches `rls_can(`
// and `can_by_member(` producing false-positives across the V4 authority
// helper family (verified during p65 retro-scan).
// ============================================================================

test(
  'p65 Bug B: SECDEF fns REVOKE\'d from authenticated must not appear in RLS policies',
  { skip: !canRun && skipMsg },
  async () => {
    const matches = await callRevokedFnsRlsRefsAuditRpc();

    if (Array.isArray(matches) && matches.length > 0) {
      const summary = matches
        .map(
          r =>
            `  - ${r.qualified_name}(${r.args || ''}) → ${r.table_name}.${r.policy_name} [${r.policy_clause}]`
        )
        .join('\n');
      assert.fail(
        `p64 incident class detected: ${matches.length} SECDEF function(s) REVOKE'd ` +
          `from authenticated but referenced in RLS policies. These will silently ` +
          `break PostgREST table reads for authenticated users.\n\n` +
          `To fix, either:\n` +
          `  (a) Restore GRANT EXECUTE ON FUNCTION public.<fn>(<args>) TO authenticated, anon;\n` +
          `  (b) Refactor the policy to call a SECDEF wrapper (e.g., rls_can, ` +
          `can_by_member) that itself retains the authenticated grant.\n\n` +
          `See:\n` +
          `  - hotfix migrations 20260426232108 (auth_org) + 20260426232200 (can_by_member)\n` +
          `  - docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md § "Charter amendment — pg_policy precondition (added p65)"\n\n` +
          `Matches:\n${summary}`
      );
    }
  }
);
