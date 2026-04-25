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
