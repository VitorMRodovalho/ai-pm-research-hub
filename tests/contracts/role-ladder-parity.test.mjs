// Role ladder parity contract test (ADR-0023)
// -----------------------------------------------------------------------------
// Asserts that the CASE ladder in sync_operational_role_cache() matches the
// expected_role CASE ladder in check_schema_invariants().A3 byte-for-byte
// (modulo whitespace). ADR-0023 declares invariant parity rule — this test
// enforces it at build time.
//
// Extraction strategy:
//   1. Concatenate all migration files
//   2. For each target function, find the LATEST CREATE OR REPLACE FUNCTION
//      via findFunctionBody (same helper shape as rpc-acl.test.mjs p41 fix)
//   3. Within each body, locate THE CASE block that is the role ladder
//      (identified by the presence of "ae.role = 'manager'" and
//      "ae.role = 'deputy_manager'" as discriminators)
//   4. Parse line-by-line into a sequence of (condition, result) clauses
//   5. Compare sequences — any divergence fails test

import { test } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const MIGRATIONS_DIR = path.join(__dirname, '..', '..', 'supabase', 'migrations');

const migrations = fs.readdirSync(MIGRATIONS_DIR)
  .filter(f => f.endsWith('.sql'))
  .sort()
  .map(f => ({ name: f, content: fs.readFileSync(path.join(MIGRATIONS_DIR, f), 'utf-8') }));
const allSQL = migrations.map(m => m.content).join('\n');

function findFunctionBody(funcName) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi'
  );
  const matches = [...allSQL.matchAll(regex)];
  if (matches.length === 0) return null;
  return matches[matches.length - 1][2];
}

// Find the role-ladder CASE block within a function body.
// Discriminator: contains both "ae.role = 'manager'" and "ae.role = 'deputy_manager'".
// Returns the inner text between CASE and END (exclusive).
function findLadderCaseBlock(body) {
  if (!body) return null;
  const caseRegex = /CASE\b([\s\S]+?)\bEND\b/g;
  const matches = [...body.matchAll(caseRegex)];
  for (const m of matches) {
    const inner = m[1];
    if (inner.includes("ae.role = 'manager'") && inner.includes("ae.role = 'deputy_manager'")) {
      return inner;
    }
  }
  return null;
}

// Normalize a SQL condition for semantic equivalence comparison.
// Collapses whitespace, removes spaces around commas/parens/operators so that
// `('a', 'b')` == `('a','b')` and `x = 1` == `x=1`. Purely textual — doesn't
// understand SQL semantics but handles the typical cosmetic variations that
// appear in hand-written CASE blocks.
function normalizeCondition(raw) {
  return raw
    .replace(/\s+/g, ' ')
    .replace(/\s*,\s*/g, ',')
    .replace(/\s*\(\s*/g, '(')
    .replace(/\s*\)\s*/g, ')')
    .replace(/\s*=\s*/g, '=')
    .trim();
}

// Parse CASE inner into normalized clauses.
function parseClauses(caseInner) {
  const lines = caseInner.split('\n');
  const whenClauses = [];
  let elseResult = null;
  for (const raw of lines) {
    const line = raw.trim();
    if (!line) continue;
    const whenMatch = line.match(/^WHEN\s+(.+?)\s+THEN\s+'([^']+)'/);
    if (whenMatch) {
      whenClauses.push({ condition: normalizeCondition(whenMatch[1]), result: whenMatch[2].trim() });
      continue;
    }
    const elseMatch = line.match(/^ELSE\s+'([^']+)'/);
    if (elseMatch) {
      elseResult = elseMatch[1].trim();
    }
  }
  return { whenClauses, elseResult };
}

// ─── Tests ────────────────────────────────────────────────────────────────────

test('sync_operational_role_cache function body extractable', () => {
  const body = findFunctionBody('sync_operational_role_cache');
  assert.ok(body, 'latest sync_operational_role_cache CREATE OR REPLACE must be extractable');
});

test('check_schema_invariants function body extractable', () => {
  const body = findFunctionBody('check_schema_invariants');
  assert.ok(body, 'latest check_schema_invariants CREATE OR REPLACE must be extractable');
});

test('sync_operational_role_cache ladder CASE block present', () => {
  const body = findFunctionBody('sync_operational_role_cache');
  const caseInner = findLadderCaseBlock(body);
  assert.ok(caseInner, 'sync_operational_role_cache must contain role-ladder CASE block');
});

test('check_schema_invariants A3 ladder CASE block present', () => {
  const body = findFunctionBody('check_schema_invariants');
  const caseInner = findLadderCaseBlock(body);
  assert.ok(caseInner, 'check_schema_invariants must contain A3 role-ladder CASE block');
});

test('ADR-0023 parity: ladders match clause-by-clause', () => {
  const syncBody = findFunctionBody('sync_operational_role_cache');
  const invBody = findFunctionBody('check_schema_invariants');
  const syncCase = findLadderCaseBlock(syncBody);
  const invCase = findLadderCaseBlock(invBody);
  assert.ok(syncCase && invCase, 'both CASE blocks must be extractable');

  const syncParsed = parseClauses(syncCase);
  const invParsed = parseClauses(invCase);

  // ELSE clause parity
  assert.strictEqual(
    syncParsed.elseResult,
    invParsed.elseResult,
    `ELSE result diverges — sync=${syncParsed.elseResult} vs invariant=${invParsed.elseResult}. See ADR-0023 parity rule.`
  );

  // WHEN clause count parity
  assert.strictEqual(
    syncParsed.whenClauses.length,
    invParsed.whenClauses.length,
    `WHEN clause count diverges — sync=${syncParsed.whenClauses.length} vs invariant=${invParsed.whenClauses.length}. ADR-0023 requires same ladder length.`
  );

  // WHEN clause order + content parity
  for (let i = 0; i < syncParsed.whenClauses.length; i++) {
    const s = syncParsed.whenClauses[i];
    const iv = invParsed.whenClauses[i];
    assert.strictEqual(
      s.condition,
      iv.condition,
      `WHEN #${i + 1} condition diverges — sync="${s.condition}" vs invariant="${iv.condition}". ADR-0023 requires identical ladder conditions in same order.`
    );
    assert.strictEqual(
      s.result,
      iv.result,
      `WHEN #${i + 1} result diverges — sync→'${s.result}' vs invariant→'${iv.result}' for condition "${s.condition}". ADR-0023 requires identical result roles. (Latent bug time-bomb if divergent.)`
    );
  }
});

test('ADR-0023 parity: ladder has no duplicate conditions', () => {
  const body = findFunctionBody('sync_operational_role_cache');
  const caseInner = findLadderCaseBlock(body);
  const { whenClauses } = parseClauses(caseInner);
  const seen = new Set();
  for (const c of whenClauses) {
    assert.ok(!seen.has(c.condition), `duplicate WHEN condition: "${c.condition}"`);
    seen.add(c.condition);
  }
});

test('ADR-0023 parity: ladder has ≥ 10 clauses (sanity check)', () => {
  const body = findFunctionBody('sync_operational_role_cache');
  const caseInner = findLadderCaseBlock(body);
  const { whenClauses } = parseClauses(caseInner);
  assert.ok(
    whenClauses.length >= 10,
    `ladder has only ${whenClauses.length} WHEN clauses — expected ≥ 10 (12 at time of ADR-0023). Did a migration strip clauses by mistake?`
  );
});
