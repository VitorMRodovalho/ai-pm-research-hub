/**
 * Engagement kinds catalog invariants — forward defense
 *
 * Static analysis tripwire over migration history. Asserts that the
 * `engagement_kinds` catalog stays consistent with ADR-0006 + each row's
 * own `description` field.
 *
 * Origin: p217 issue #160 — discovered that `engagement_kinds(slug='ambassador')`
 * had `requires_agreement=TRUE` despite the description "Reconhecimento
 * honorário / mérito. Sem termo obrigatório." and `legal_basis='consent'`,
 * contradicting ADR-0006 line 55. Fix shipped via migration
 * `20260803000001_p217_160_ambassador_catalog_fix.sql`.
 *
 * Why static analysis (not behavioural):
 *   - DB-aware tests gate on SUPABASE_URL + SERVICE_ROLE_KEY env which is
 *     not configured by default in offline CI (per WATCH-205.A /
 *     `feedback_contract_test_ci_skip_silent.md`). Static tripwire runs
 *     in every offline + with-DB CI run.
 *   - The behavioural surface is validated by the migration's in-tx
 *     `DO $$ ... RAISE EXCEPTION` sanity block + the post-state smoke
 *     in the session handoff.
 *   - This test catches the regression class where a future migration
 *     silently re-flips ambassador to TRUE (the same seed bug pattern
 *     that motivated this fix).
 *
 * Pattern: pattern-agnostic regex over migration bodies (per WATCH-215.A).
 *
 * Cross-ref:
 *   - ADR-0006 line 55 (ambassador canonical model: legal_basis=consent, agreement=null)
 *   - ADR-0008 line 19 (lifecycle table: ambassador NOT listed under termo flow)
 *   - Migration 20260803000001 (the fix)
 *   - P162 RESOLVED-160.A (decision log)
 *
 * Scope: static analysis only. Fast, no DB env required.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function loadMigrations() {
  return readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .map((f) => ({
      name: f,
      body: readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8'),
    }));
}

test('p217 #160 ambassador catalog fix migration is present and correct', async (t) => {
  const migrations = loadMigrations();
  const fix = migrations.find((m) => m.name === '20260803000001_p217_160_ambassador_catalog_fix.sql');

  await t.test('migration file 20260803000001 exists', () => {
    assert.ok(fix, 'Migration 20260803000001_p217_160_ambassador_catalog_fix.sql must exist');
  });

  await t.test('migration body UPDATEs engagement_kinds.requires_agreement to false for ambassador', () => {
    const body = fix.body;
    // Pattern-agnostic: tolerate whitespace + column ordering + the idempotent guard
    const updatePattern = /UPDATE\s+public\.engagement_kinds[\s\S]*?SET[\s\S]*?requires_agreement\s*=\s*false[\s\S]*?WHERE\s+slug\s*=\s*'ambassador'/i;
    assert.match(body, updatePattern, 'Must UPDATE engagement_kinds SET requires_agreement=false WHERE slug=ambassador');
  });

  await t.test('migration body includes idempotent guard (AND requires_agreement = true)', () => {
    // Prevents re-running the migration from spuriously bumping updated_at
    assert.match(fix.body, /AND\s+requires_agreement\s*=\s*true/i, 'Migration should guard with AND requires_agreement = true for idempotency');
  });

  await t.test('migration body includes in-tx sanity DO block that RAISEs on failure', () => {
    assert.match(fix.body, /DO\s*\$\$/i, 'Should include DO $$ ... $$ block');
    assert.match(fix.body, /RAISE\s+EXCEPTION/i, 'Should RAISE EXCEPTION if post-condition fails');
  });

  await t.test('migration header documents ADR-0006 alignment', () => {
    assert.match(fix.body, /ADR-0006/i, 'Header must reference ADR-0006');
  });

  await t.test('migration header documents ROLLBACK strategy', () => {
    assert.match(fix.body, /ROLLBACK/i, 'Header must include a ROLLBACK section');
    assert.match(fix.body, /requires_agreement\s*=\s*true/i, 'Rollback must restore requires_agreement=true');
  });

  await t.test('migration header documents zero V4 capability side-effects', () => {
    // Critical safety claim — ambassadors have 0 rows in engagement_kind_permissions,
    // so the is_authoritative flip grants no new actions/scopes. Without this claim
    // the migration would need a separate capability-impact analysis.
    assert.match(fix.body, /(capability|engagement_kind_permissions|capabilities)/i,
      'Header must document capability impact (zero for ambassador per V4 matrix)');
  });
});

test('engagement_kinds catalog invariant: no migration re-flips ambassador.requires_agreement to TRUE after the p217 fix', async () => {
  const migrations = loadMigrations();
  const fixIdx = migrations.findIndex((m) => m.name === '20260803000001_p217_160_ambassador_catalog_fix.sql');
  assert.ok(fixIdx >= 0, 'Fix migration must be in the registry to anchor the invariant');

  // Any migration *after* the fix that sets ambassador.requires_agreement = true is a regression
  const subsequent = migrations.slice(fixIdx + 1);
  const reflipPattern = /UPDATE\s+public\.engagement_kinds[\s\S]*?SET[\s\S]*?requires_agreement\s*=\s*true[\s\S]*?WHERE\s+slug\s*=\s*'ambassador'/i;
  // VALUES-tuple-scoped INSERT pattern — avoids the multi-row false-positive
  // where ambassador=false but a sibling row has true (per code-reviewer LOW
  // in PR #250 council review). Anchors to a single VALUES(...) tuple.
  const insertReflipPattern = /VALUES\s*\([^)]*'ambassador'[^)]*,\s*true[^)]*\)/i;
  // ON CONFLICT DO UPDATE upsert form (per code-reviewer LOW in PR #250 — also
  // bypasses the UPDATE pattern since ON CONFLICT has no WHERE clause).
  const onConflictReflipPattern = /ON\s+CONFLICT[\s\S]*?DO\s+UPDATE\s+SET[\s\S]*?requires_agreement\s*=\s*true/i;
  // Note: MERGE statement (Postgres 15+) is not covered. Codebase has zero
  // MERGE usage; revisit if a future migration adopts MERGE patterns.

  const offenders = subsequent.filter((m) =>
    reflipPattern.test(m.body) ||
    insertReflipPattern.test(m.body) ||
    onConflictReflipPattern.test(m.body)
  );

  assert.equal(
    offenders.length,
    0,
    `Future migrations must not re-flip ambassador.requires_agreement to TRUE. Offenders: ${offenders.map((m) => m.name).join(', ')}`
  );
});
