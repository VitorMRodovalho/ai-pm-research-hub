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
import { loadLatestCaptures, diffLiveVsCaptures } from '../helpers/rpc-body-drift-parser.mjs';

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
// Phase C body-hash drift allowlist — p175 baseline (one entry per
// drifted function key `name@normalized_args`). Ratchet DOWN as drift
// is captured via apply_migration in Phase B/D bucket sessions.
const BODY_DRIFT_ALLOWLIST_PATH = resolve(
  ROOT,
  'docs/audit/RPC_BODY_DRIFT_ALLOWLIST_P175.txt'
);
const BODY_DRIFT_BASELINE_SIZE = 0;
// Pacote M / ADR-0029 retroactive retirement: 17 ingestion/release-readiness/
// governance-bundle substrate tables + adjacent tables acknowledged as
// extinct without DROP TABLE migration capture. p174 (2026-05-17): +4 from
// same era surfaced when CI gate activated. Going forward this baseline must
// NOT grow — every new entry requires a retirement ADR + PM ack.
const TABLE_DRIFT_BASELINE_SIZE = 22;

const TABLE_ORPHAN_ALLOWLIST_PATH = resolve(
  ROOT,
  'docs/audit/TABLE_ORPHAN_ALLOWLIST_P174.txt'
);
// p174 baseline: 35 pre-migration-discipline tables surfaced when CI gate
// activated. Ratchet down by capturing via apply_migration in dedicated
// sessions. See `docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md` p174 section.
const TABLE_ORPHAN_ALLOWLIST_BASELINE_SIZE = 35;

// ADR-0097 / WATCH-185 — schema_migrations drift baselines (p224).
// Three orthogonal drift classes with separate allowlists + ratchets.
const MIGRATION_FILE_DRIFT_BASELINE_PATH = resolve(
  ROOT,
  'docs/audit/MIGRATION_FILE_DRIFT_BASELINE_P224.txt'
);
// p224 baseline: 694 versions tracked in supabase_migrations.schema_migrations
// without a corresponding local .sql file. Origin: pre-GC-097 era
// apply_migration without manual file sync.
const MIGRATION_FILE_DRIFT_BASELINE_SIZE = 694;

const MIGRATION_ORPHAN_LOCAL_BASELINE_PATH = resolve(
  ROOT,
  'docs/audit/MIGRATION_ORPHAN_LOCAL_BASELINE_P224.txt'
);
// p224 baseline: 15 local .sql files without corresponding row in
// supabase_migrations.schema_migrations. 3 clusters: p64 (3) + p125-E1/E2/p126-E3 (11) + TAP CPMAI R00 seed (1).
const MIGRATION_ORPHAN_LOCAL_BASELINE_SIZE = 15;

const MIGRATION_EMPTY_STATEMENTS_BASELINE_PATH = resolve(
  ROOT,
  'docs/audit/MIGRATION_EMPTY_STATEMENTS_BASELINE_P224.txt'
);
// p224 baseline: 41 rows in schema_migrations where statements is NULL OR
// empty array '{}'. Two sub-categories:
//   - 39 with statements IS NULL (true NULL — never recorded)
//   - 2 with statements = '{}' (empty array — `supabase migration repair`
//     set body to empty array instead of populating from local file; bug
//     pattern documented in ADR-0097 sediment section). Affected:
//     20260721000000 + 20260722000000.
// Cross-cut with missing-file baseline: 12 ALSO missing local file
// (truly lost — body only in pg_proc); 29 with local file (cosmetic).
const MIGRATION_EMPTY_STATEMENTS_BASELINE_SIZE = 41;

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

async function callBodiesAuditRpc() {
  const url = `${SUPABASE_URL}/rest/v1/rpc/_audit_list_public_function_bodies`;
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
    throw new Error(`bodies audit RPC failed: ${res.status} ${await res.text()}`);
  }
  return res.json();
}

async function callSchemaMigrationsAuditRpc() {
  // schema_migrations has ~1784 rows (p224 baseline). PostgREST default
  // limit is 1000, so we must explicitly request more. Using `Range`
  // header with `Range-Unit: items` to fetch all rows (canonical
  // PostgREST pattern for unbounded RPC result sets).
  const url = `${SUPABASE_URL}/rest/v1/rpc/_audit_list_schema_migrations`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Range-Unit': 'items',
      Range: '0-9999',
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({}),
  });
  if (!res.ok && res.status !== 206) {
    throw new Error(`schema_migrations audit RPC failed: ${res.status} ${await res.text()}`);
  }
  return res.json();
}

function loadBodyDriftAllowlist() {
  const raw = readFileSync(BODY_DRIFT_ALLOWLIST_PATH, 'utf8');
  return new Set(
    raw
      .split('\n')
      .map(s => s.trim())
      .filter(s => s.length > 0 && !s.startsWith('#'))
  );
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

function loadTableOrphanAllowlist() {
  const raw = readFileSync(TABLE_ORPHAN_ALLOWLIST_PATH, 'utf8');
  return new Set(
    raw
      .split('\n')
      .map(s => s.trim())
      .filter(s => s.length > 0 && !s.startsWith('#'))
  );
}

function loadMigrationFileDriftBaseline() {
  const raw = readFileSync(MIGRATION_FILE_DRIFT_BASELINE_PATH, 'utf8');
  return new Set(
    raw
      .split('\n')
      .map(s => s.trim())
      .filter(s => s.length > 0 && !s.startsWith('#'))
  );
}

function loadMigrationOrphanLocalBaseline() {
  const raw = readFileSync(MIGRATION_ORPHAN_LOCAL_BASELINE_PATH, 'utf8');
  return new Set(
    raw
      .split('\n')
      .map(s => s.trim())
      .filter(s => s.length > 0 && !s.startsWith('#'))
  );
}

function loadMigrationEmptyStatementsBaseline() {
  const raw = readFileSync(MIGRATION_EMPTY_STATEMENTS_BASELINE_PATH, 'utf8');
  return new Set(
    raw
      .split('\n')
      .map(s => s.trim())
      .filter(s => s.length > 0 && !s.startsWith('#'))
  );
}

function extractLocalMigrationVersions() {
  // Extract unique version prefix from supabase/migrations/*.sql filenames.
  // Filename format: <version>_<name>.sql or <version>.sql (rare).
  // Returns Set of version strings (deduped).
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql'));
  const out = new Set();
  for (const f of files) {
    const base = f.replace(/\.sql$/, '');
    const version = base.split('_')[0];
    out.add(version);
  }
  return out;
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

// CI sentinel (p177): if we are running inside GitHub Actions / a CI runner
// and SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY are absent, the DB-aware contract
// assertions below would silently skip — exactly the gap that hid 3 weeks of
// drift accumulation (23 orphans) before p174 fixed the workflow env block.
// This sentinel hard-fails CI when secrets are missing so the next "secrets
// rotated out" or "fork PR doesn't see secrets" incident surfaces immediately
// instead of letting drift accumulate invisibly.
test('CI sentinel: SUPABASE_URL + SERVICE_ROLE_KEY must be set when running in CI', () => {
  const inCi = process.env.CI === 'true' || process.env.GITHUB_ACTIONS === 'true';
  if (!inCi) return;
  assert.ok(
    SUPABASE_URL,
    'SUPABASE_URL env var missing in CI context — DB-aware Track Q-C / Phase C ' +
    'contract tests would silently skip. Add SUPABASE_URL to GH repo secrets ' +
    'and reference it via `${{ secrets.SUPABASE_URL }}` in the workflow env ' +
    'block (see .github/workflows/ci.yml `Run Unit Tests` step).'
  );
  assert.ok(
    SERVICE_ROLE_KEY,
    'SUPABASE_SERVICE_ROLE_KEY env var missing in CI context — DB-aware ' +
    'Track Q-C / Phase C contract tests would silently skip. Add ' +
    'SUPABASE_SERVICE_ROLE_KEY to GH repo secrets and reference it via ' +
    '`${{ secrets.SUPABASE_SERVICE_ROLE_KEY }}` in the workflow env block.'
  );
});

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
    const orphanAllowlist = loadTableOrphanAllowlist();

    const dbTables = new Set(rows.map(r => r.table_name));
    const allOrphans = [...dbTables].filter(
      n => !buildCreateTableMatcher(n).test(allSQL)
    );

    // Filter against p174 baseline allowlist (35 pre-discipline tables).
    // Future orphans must either be captured via apply_migration OR added
    // to the allowlist with PM ack + baseline bump.
    const newOrphans = allOrphans.filter(n => !orphanAllowlist.has(n));

    if (newOrphans.length > 0) {
      assert.fail(
        `NEW orphan table(s) detected — exist in DB but no CREATE TABLE ` +
          `migration captures them, and not in p174 baseline allowlist. ` +
          `Add a migration via apply_migration (NEVER execute_sql for DDL — ` +
          `see GC-097 + ADR-0029 governance gap). If intentionally outside ` +
          `migration discipline (e.g., introspection view), extend ` +
          `${TABLE_ORPHAN_ALLOWLIST_PATH} with rationale AND bump ` +
          `TABLE_ORPHAN_ALLOWLIST_BASELINE_SIZE.\n\n` +
          `New orphan tables:\n  ${newOrphans.sort().join('\n  ')}`
      );
    }
  }
);

test(
  'p174 ratchet: table-orphan allowlist stays in sync (no resolved-or-extinct entries)',
  { skip: !canRun && skipMsg },
  async () => {
    const rows = await callTablesAuditRpc();
    const orphanAllowlist = loadTableOrphanAllowlist();
    const allSQL = loadAllMigrationsConcat();

    const dbTables = new Set(rows.map(r => r.table_name));

    const stale = [...orphanAllowlist].filter(name => {
      const stillInDb = dbTables.has(name);
      const captured = buildCreateTableMatcher(name).test(allSQL);
      // Stale if: removed from DB OR captured by migration (orphan resolved).
      return !stillInDb || captured;
    });

    if (stale.length > 0) {
      assert.fail(
        `Table-orphan allowlist contains entries that are no longer orphans. ` +
          `Remove them from ${TABLE_ORPHAN_ALLOWLIST_PATH} (drift cleanup ` +
          `ratcheting down) and update TABLE_ORPHAN_ALLOWLIST_BASELINE_SIZE:\n\n  ` +
          stale.sort().join('\n  ')
      );
    }
  }
);

test('p174 ratchet: table-orphan allowlist size matches baseline', () => {
  const allowlist = loadTableOrphanAllowlist();
  assert.equal(
    allowlist.size,
    TABLE_ORPHAN_ALLOWLIST_BASELINE_SIZE,
    `Table-orphan allowlist size drifted from ${TABLE_ORPHAN_ALLOWLIST_BASELINE_SIZE} ` +
      `to ${allowlist.size}. p174 baseline was 35 pre-migration-discipline ` +
      `tables. Ratcheting DOWN (capture via apply_migration) requires updating ` +
      `the baseline constant in this file. Ratcheting UP requires PM ack + ` +
      `documented justification in the allowlist file.`
  );
});

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

// ============================================================================
// Phase C body-hash drift — closes the "captured ≠ canonical" gap
//
// Q-C catches when a function exists in DB without ANY CREATE FUNCTION
// migration capturing it (orphan). It does NOT catch when a function IS
// captured by a migration but the live body has since diverged — the
// drift pattern that motivated the entire p52 / p174 audits.
//
// Phase C compares md5(regexp_replace(prosrc, '\s+', ' ', 'g')) on the
// live function (via `_audit_list_public_function_bodies()`) against the
// same hash computed over the latest CREATE FUNCTION migration capture
// per (name, normalized_args) key. Drift = hashes differ.
//
// The 225-entry allowlist baseline (p175) freezes today's known drift;
// ratchets DOWN each Phase B/D bucket session. Three failure paths:
//   1. NEW drift: live body diverged AND key not in allowlist. Author
//      either captures via apply_migration + writes file (Phase B
//      pattern) OR adds key to allowlist with bump (rare — drift recovery
//      is the preferred path).
//   2. RESOLVED drift: allowlisted key is now clean (or extinct). Author
//      removes it AND decrements BODY_DRIFT_BASELINE_SIZE.
//   3. SIZE mismatch: allowlist count != BODY_DRIFT_BASELINE_SIZE.
//      Forces every cleanup to update the test constant.
//
// Helper: tests/helpers/rpc-body-drift-parser.mjs (shared with
// scripts/audit-rpc-body-drift.mjs).
// ============================================================================

test(
  'Phase C: no NEW body-hash drift vs p175 allowlist',
  { skip: !canRun && skipMsg },
  async () => {
    const liveRows = await callBodiesAuditRpc();
    const captures = loadLatestCaptures(MIGRATIONS_DIR);
    const diff = diffLiveVsCaptures(liveRows, captures);
    const allowlist = loadBodyDriftAllowlist();

    const allDrift = [...diff.driftedDefinite, ...diff.driftedSuspect];
    const newDrift = allDrift.filter(r => !allowlist.has(r.key));

    if (newDrift.length > 0) {
      const summary = newDrift
        .sort((a, b) => (b.touch_count || 0) - (a.touch_count || 0))
        .slice(0, 20)
        .map(r => `  [${r.touch_count}x] ${r.name}(${r.args})  live_len=${r.live_len}  mig_len=${r.migration_len}  latest=${r.latest_file}`)
        .join('\n');
      const more = newDrift.length > 20 ? `\n  ... and ${newDrift.length - 20} more` : '';
      assert.fail(
        `NEW body-hash drift detected — live function body diverged from ` +
          `the latest CREATE FUNCTION migration capture, and the key is NOT ` +
          `in the p175 allowlist.\n\n` +
          `Preferred fix: capture the current body via apply_migration ` +
          `(GC-097 / ADR-0029 governance). For each function, run\n` +
          `  SELECT pg_get_functiondef(p.oid) FROM pg_proc p WHERE p.proname = '<name>' AND ...\n` +
          `then commit the verbatim DDL as a new migration file (see ` +
          `scripts/audit-rpc-body-drift.mjs for capture workflow).\n\n` +
          `Alternate fix (rare): extend ${BODY_DRIFT_ALLOWLIST_PATH} and ` +
          `bump BODY_DRIFT_BASELINE_SIZE in this test file. Use only when ` +
          `body intentionally diverges and capture is blocked.\n\n` +
          `NEW drift (top 20 by touch_count):\n${summary}${more}`
      );
    }
  }
);

test(
  'Phase C: body-drift allowlist stays in sync (no resolved-or-extinct entries)',
  { skip: !canRun && skipMsg },
  async () => {
    const liveRows = await callBodiesAuditRpc();
    const captures = loadLatestCaptures(MIGRATIONS_DIR);
    const diff = diffLiveVsCaptures(liveRows, captures);
    const allowlist = loadBodyDriftAllowlist();

    const currentDriftKeys = new Set(
      [...diff.driftedDefinite, ...diff.driftedSuspect].map(r => r.key)
    );

    const stale = [...allowlist].filter(key => !currentDriftKeys.has(key));

    if (stale.length > 0) {
      assert.fail(
        `Body-drift allowlist contains entries that are no longer drifted ` +
          `(either captured by a new migration OR the function is extinct). ` +
          `Remove from ${BODY_DRIFT_ALLOWLIST_PATH} and decrement ` +
          `BODY_DRIFT_BASELINE_SIZE in this file by ${stale.length}:\n\n  ` +
          stale.sort().join('\n  ')
      );
    }
  }
);

test('Phase C: body-drift allowlist size matches p175 baseline', () => {
  const allowlist = loadBodyDriftAllowlist();
  assert.equal(
    allowlist.size,
    BODY_DRIFT_BASELINE_SIZE,
    `Body-drift allowlist size drifted from ${BODY_DRIFT_BASELINE_SIZE} to ${allowlist.size}. ` +
      `Ratcheting DOWN (Phase B/D drift recovery): decrement the baseline ` +
      `constant in this file to match the new allowlist count. ` +
      `Ratcheting UP requires capturing the body via apply_migration first; ` +
      `if intentionally accepting new drift, document the rationale in the ` +
      `allowlist file AND bump the constant.`
  );
});

// ============================================================================
// ADR-0097 / WATCH-185 — schema_migrations drift baselines (p224)
//
// Closes the gap between supabase_migrations.schema_migrations (tracked rows)
// and supabase/migrations/*.sql (local files). Three orthogonal drift classes:
//
//   1. MISSING FILE: tracked − local. 694 entries at p224 baseline.
//      Pre-GC-097 era: apply_migration applied DDL to DB without manual
//      file sync. Body still in statements column (1742/1783 rows).
//
//   2. ORPHAN LOCAL: local − tracked. 15 entries at p224 baseline.
//      Files exist on disk but never registered via `migration repair --status
//      applied`. 3 clusters: p64 (3) + p125-E1/E2/p126-E3 (11) + TAP CPMAI (1).
//
//   3. EMPTY STATEMENTS: tracked rows with NULL/empty statements. 39 entries
//      at p224 baseline. Two sub-categories: 12 ALSO missing local file
//      (truly lost — body only in pg_proc), 27 with local file (cosmetic).
//
// Discovery: P162 log #185 WATCH-AUDIT-HIGH-17. Decision: ADR-0097 (Path δ
// Hybrid amnesty + ratchet). Helper RPC: `_audit_list_schema_migrations()`
// (migration 20260805000003).
//
// Three failure paths per drift class (mirror Q-C / Pacote M / Phase C):
//   - NEW: live drift entry not in baseline allowlist → fail (drift grew)
//   - STALE: baseline entry not in current live state → fail (ratchet DOWN)
//   - SIZE: allowlist file size != BASELINE_SIZE constant → fail (force bump)
// ============================================================================

test(
  'ADR-0097: no NEW missing-file drift vs p224 baseline (tracked − local)',
  { skip: !canRun && skipMsg },
  async () => {
    const rows = await callSchemaMigrationsAuditRpc();
    const localVersions = extractLocalMigrationVersions();
    const baseline = loadMigrationFileDriftBaseline();

    const trackedVersions = new Set(rows.map(r => r.version));
    const currentMissing = [...trackedVersions].filter(v => !localVersions.has(v));
    const newMissing = currentMissing.filter(v => !baseline.has(v));

    if (newMissing.length > 0) {
      assert.fail(
        `NEW missing-file drift detected — version(s) appear in ` +
          `supabase_migrations.schema_migrations but no corresponding .sql ` +
          `exists in supabase/migrations/. Pre-GC-097 era apply_migration ` +
          `pattern (DDL applied via MCP without manual file sync) was the ` +
          `historical cause; GC-097 protocol now requires writing the local ` +
          `file + running 'supabase migration repair --status applied <ts>' ` +
          `after every apply_migration call.\n\n` +
          `To fix: either (a) write the missing .sql file with the DDL body ` +
          `(query the live row's statements via SELECT * FROM ` +
          `supabase_migrations.schema_migrations WHERE version='<v>'), or ` +
          `(b) extend ${MIGRATION_FILE_DRIFT_BASELINE_PATH} with PM ack + ` +
          `bump MIGRATION_FILE_DRIFT_BASELINE_SIZE in this file (rare — ` +
          `recovery is the preferred path).\n\n` +
          `New missing-file drift:\n  ${newMissing.sort().join('\n  ')}`
      );
    }
  }
);

test(
  'ADR-0097: missing-file baseline stays in sync (no resolved entries)',
  { skip: !canRun && skipMsg },
  async () => {
    const rows = await callSchemaMigrationsAuditRpc();
    const localVersions = extractLocalMigrationVersions();
    const baseline = loadMigrationFileDriftBaseline();

    const trackedVersions = new Set(rows.map(r => r.version));
    const currentMissing = new Set(
      [...trackedVersions].filter(v => !localVersions.has(v))
    );

    const stale = [...baseline].filter(v => !currentMissing.has(v));

    if (stale.length > 0) {
      assert.fail(
        `Missing-file baseline contains entries that are no longer missing ` +
          `(either local .sql was added OR row was deleted from ` +
          `supabase_migrations.schema_migrations). Remove from ` +
          `${MIGRATION_FILE_DRIFT_BASELINE_PATH} (drift cleanup ratcheting ` +
          `down) and decrement MIGRATION_FILE_DRIFT_BASELINE_SIZE in this ` +
          `file by ${stale.length}:\n\n  ` +
          stale.sort().join('\n  ')
      );
    }
  }
);

test('ADR-0097: missing-file baseline size matches p224 constant', () => {
  const baseline = loadMigrationFileDriftBaseline();
  assert.equal(
    baseline.size,
    MIGRATION_FILE_DRIFT_BASELINE_SIZE,
    `Missing-file baseline size drifted from ${MIGRATION_FILE_DRIFT_BASELINE_SIZE} ` +
      `to ${baseline.size}. Ratcheting DOWN (drift recovery): decrement ` +
      `the constant in this file to match the new baseline count. ` +
      `Ratcheting UP requires PM ack + ADR-0097 amendment + documented ` +
      `rationale in the baseline file header.`
  );
});

test(
  'ADR-0097: no NEW orphan-local drift vs p224 baseline (local − tracked)',
  { skip: !canRun && skipMsg },
  async () => {
    const rows = await callSchemaMigrationsAuditRpc();
    const localVersions = extractLocalMigrationVersions();
    const baseline = loadMigrationOrphanLocalBaseline();

    const trackedVersions = new Set(rows.map(r => r.version));
    const currentOrphans = [...localVersions].filter(v => !trackedVersions.has(v));
    const newOrphans = currentOrphans.filter(v => !baseline.has(v));

    if (newOrphans.length > 0) {
      assert.fail(
        `NEW orphan-local drift detected — version(s) appear as .sql files ` +
          `in supabase/migrations/ but no corresponding row in ` +
          `supabase_migrations.schema_migrations. Indicates a file was added ` +
          `without running 'supabase migration repair --status applied <ts>' ` +
          `(GC-097 manual sync step).\n\n` +
          `To fix: run \`supabase migration repair --status applied <version>\` ` +
          `for each new orphan to register it. Files should NEVER exist ` +
          `without registration.\n\n` +
          `New orphan-local drift:\n  ${newOrphans.sort().join('\n  ')}`
      );
    }
  }
);

test(
  'ADR-0097: orphan-local baseline stays in sync (no resolved entries)',
  { skip: !canRun && skipMsg },
  async () => {
    const rows = await callSchemaMigrationsAuditRpc();
    const localVersions = extractLocalMigrationVersions();
    const baseline = loadMigrationOrphanLocalBaseline();

    const trackedVersions = new Set(rows.map(r => r.version));
    const currentOrphans = new Set(
      [...localVersions].filter(v => !trackedVersions.has(v))
    );

    const stale = [...baseline].filter(v => !currentOrphans.has(v));

    if (stale.length > 0) {
      assert.fail(
        `Orphan-local baseline contains entries that are no longer orphan ` +
          `(either row was registered via migration repair OR file was ` +
          `deleted). Remove from ${MIGRATION_ORPHAN_LOCAL_BASELINE_PATH} and ` +
          `decrement MIGRATION_ORPHAN_LOCAL_BASELINE_SIZE in this file by ` +
          `${stale.length}:\n\n  ` +
          stale.sort().join('\n  ')
      );
    }
  }
);

test('ADR-0097: orphan-local baseline size matches p224 constant', () => {
  const baseline = loadMigrationOrphanLocalBaseline();
  assert.equal(
    baseline.size,
    MIGRATION_ORPHAN_LOCAL_BASELINE_SIZE,
    `Orphan-local baseline size drifted from ${MIGRATION_ORPHAN_LOCAL_BASELINE_SIZE} ` +
      `to ${baseline.size}. Ratcheting DOWN (orphan registered via migration ` +
      `repair): decrement the constant in this file. Ratcheting UP prohibited ` +
      `(files should never exist without registration — GC-097 violation).`
  );
});

test(
  'ADR-0097: no NEW empty-statements drift vs p224 baseline',
  { skip: !canRun && skipMsg },
  async () => {
    const rows = await callSchemaMigrationsAuditRpc();
    const baseline = loadMigrationEmptyStatementsBaseline();

    const currentEmpty = rows.filter(r => !r.has_body).map(r => r.version);
    const newEmpty = currentEmpty.filter(v => !baseline.has(v));

    if (newEmpty.length > 0) {
      assert.fail(
        `NEW empty-statements drift detected — row(s) in ` +
          `supabase_migrations.schema_migrations have NULL or empty ` +
          `statements column. The apply_migration MCP should always capture ` +
          `the body. Empty statements indicate either (a) row inserted via ` +
          `'supabase migration repair --status applied' without statements ` +
          `column being set, or (b) dashboard SQL editor DDL without ` +
          `migration discipline.\n\n` +
          `To fix: re-run 'supabase migration repair --status applied <v>' ` +
          `for each new empty row IF the corresponding local file exists ` +
          `(CLI backfills body from file). If no local file, the DDL is ` +
          `only recoverable from pg_proc/pg_policies introspection.\n\n` +
          `New empty-statements drift:\n  ${newEmpty.sort().join('\n  ')}`
      );
    }
  }
);

test(
  'ADR-0097: empty-statements baseline stays in sync (no resolved entries)',
  { skip: !canRun && skipMsg },
  async () => {
    const rows = await callSchemaMigrationsAuditRpc();
    const baseline = loadMigrationEmptyStatementsBaseline();

    const currentEmpty = new Set(
      rows.filter(r => !r.has_body).map(r => r.version)
    );

    const stale = [...baseline].filter(v => !currentEmpty.has(v));

    if (stale.length > 0) {
      assert.fail(
        `Empty-statements baseline contains entries that no longer have empty ` +
          `statements (body was backfilled — typically by 'supabase migration ` +
          `repair --status applied' cascading to other versions with local ` +
          `files present). Remove from ${MIGRATION_EMPTY_STATEMENTS_BASELINE_PATH} ` +
          `and decrement MIGRATION_EMPTY_STATEMENTS_BASELINE_SIZE in this ` +
          `file by ${stale.length}:\n\n  ` +
          stale.sort().join('\n  ')
      );
    }
  }
);

test('ADR-0097: empty-statements baseline size matches p224 constant', () => {
  const baseline = loadMigrationEmptyStatementsBaseline();
  assert.equal(
    baseline.size,
    MIGRATION_EMPTY_STATEMENTS_BASELINE_SIZE,
    `Empty-statements baseline size drifted from ${MIGRATION_EMPTY_STATEMENTS_BASELINE_SIZE} ` +
      `to ${baseline.size}. Ratcheting DOWN (body backfilled): decrement ` +
      `the constant. Ratcheting UP prohibited (apply_migration MCP should ` +
      `always capture body — investigate cause before accepting).`
  );
});
