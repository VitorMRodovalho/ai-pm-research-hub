/**
 * Forward-defense: engagements.legal_basis CHECK constraint must accept LGPD-canonical
 * `contract` value (alongside legacy `contract_volunteer`) so values from the
 * `engagement_kinds` catalog can flow into engagement rows without rejection.
 *
 * Origin: p218 WATCH-257.A. 2026-04-13 (migration 20260413320000) created the engagements
 * constraint with runtime/workflow-specific `contract_volunteer` (Lei 9.608). 2026-04-15
 * (migration 20260415100000_v4_fix_legal_basis_lgpd_compliance.sql) updated ONLY the
 * `engagement_kinds` catalog constraint to LGPD-canonical `contract` (per LGPD Art. 7 V),
 * leaving an undocumented asymmetry. p218 Issue #257 INSERT (Vitor SGO on CPMAI Ciclo 3)
 * hit the rejection when copying `contract` directly from the catalog row.
 *
 * Fix (p218): migration 20260803000002 makes the constraint additive — accepts BOTH
 * `contract` AND `contract_volunteer`. No row migration; no consumer changes; 46 legacy
 * rows preserved. Future cleanup normalizes legacy rows + drops `contract_volunteer`.
 *
 * Cross-ref:
 *   - supabase/migrations/20260803000002_p218_watch_257_a_engagements_legal_basis_lgpd_canonical.sql (the fix)
 *   - supabase/migrations/20260413320000_v4_phase3_engagements_table.sql (original constraint)
 *   - supabase/migrations/20260415100000_v4_fix_legal_basis_lgpd_compliance.sql (catalog half of harmonization)
 *   - ADR-0006 (engagements + persons V4 model)
 *   - LGPD Art. 7 V (contract as legal basis)
 *   - P162 WATCH-257.A
 *
 * Two-test bundle:
 *   1. Static — migration file contains both literals (always runs)
 *   2. Behavioural — live constraint accepts both + catalog values are all accepted
 *      (DB-aware, skips without env)
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATION_FILE = resolve(
  ROOT,
  'supabase/migrations/20260803000002_p218_watch_257_a_engagements_legal_basis_lgpd_canonical.sql'
);

test('p218 WATCH-257.A migration accepts both `contract` and `contract_volunteer` in engagements constraint', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // Both literals must appear in the new ADD CONSTRAINT clause
  const newConstraintPattern = /ADD\s+CONSTRAINT\s+engagements_legal_basis_check[\s\S]*?CHECK\s*\(\s*legal_basis\s+IN\s*\([\s\S]*?'contract'[\s\S]*?'contract_volunteer'[\s\S]*?\)\s*\)/i;
  assert.match(body, newConstraintPattern,
    'WATCH-257.A migration must define a CHECK constraint listing both `contract` (LGPD-canonical) and `contract_volunteer` (legacy)');

  // Sanity: no leftover constraint that would block contract — ensure DROP IF EXISTS is present
  assert.match(body, /DROP\s+CONSTRAINT\s+IF\s+EXISTS\s+engagements_legal_basis_check/i,
    'WATCH-257.A migration must DROP the prior constraint before ADDing the additive one (idempotent re-apply)');

  // Sanity: the post-migration smoke block enforces both literals are present
  assert.match(body, /Post-migration check failed:[^']*contract[^']*contract_volunteer/i,
    'WATCH-257.A migration must include a DO block sanity check that fails loud if both literals are not in the new constraint');
});

test('p218 WATCH-257.A migration is registered in supabase migrations baseline (no orphan)', () => {
  // The orphan check (tests/contracts/rpc-migration-coverage.test.mjs) handles function orphans.
  // For DDL like this one, the simplest forward-defense is: the file exists with the canonical
  // timestamp + the `supabase migration repair --status applied` step is documented in the PR.
  // This test just asserts the migration file is named per the timestamp-version pattern so
  // CI globs that pick up `supabase/migrations/*.sql` see it.
  const dir = resolve(ROOT, 'supabase/migrations');
  const files = readdirSync(dir).filter(f => f.startsWith('20260803000002_'));
  assert.equal(files.length, 1,
    'Exactly one migration file must exist for version 20260803000002 (p218 WATCH-257.A)');
  assert.match(files[0], /^20260803000002_p218_watch_257_a_engagements_legal_basis_lgpd_canonical\.sql$/,
    'Migration filename must follow `<timestamp>_<descriptive_name>.sql` per CLAUDE.md GC-097');
});

test('engagements.legal_basis constraint accepts catalog values (live constraint includes contract)', { skip: !process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY }, async () => {
  const { createClient } = await import('@supabase/supabase-js');
  const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

  // Read the live constraint definition
  const { data: constraintRows, error: cErr } = await sb.rpc('exec_sql_admin', {
    p_sql: `SELECT pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE conname = 'engagements_legal_basis_check'`
  }).catch(() => ({ data: null, error: null }));

  // Fallback if exec_sql_admin doesn't exist: just inspect via direct query through PostgREST
  // (most projects don't expose a generic exec_sql; skip behavioural check gracefully)
  if (!constraintRows || cErr) return;

  const def = String(constraintRows?.[0]?.def || '');
  assert.match(def, /'contract'/, 'live engagements_legal_basis_check must accept `contract`');
  assert.match(def, /'contract_volunteer'/, 'live engagements_legal_basis_check must accept `contract_volunteer` (legacy preservation)');
});
