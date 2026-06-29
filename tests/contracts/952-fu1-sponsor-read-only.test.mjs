/**
 * FU-1 (#952) — Sponsor read-only de fato: read/write split forward-defense.
 *
 * ADR-0110. The sponsor x sponsor seed used to grant the WRITE actions
 * manage_finance + manage_partner. Those same actions also gate ~12 READ RPCs,
 * so FU-1 introduced dedicated READ actions (view_finance/view_partner), repointed
 * the read gates, and revoked ONLY the sponsor write seeds. Net: sponsor keeps every
 * read, loses every write.
 *
 * Two layers:
 *  - STATIC (always runs, offline-safe): asserts the FU-1 migration is present + correct,
 *    and that NO later migration re-seeds a sponsor WRITE action (the regression class
 *    this ADR exists to prevent — mirrors the ambassador-catalog-invariant tripwire).
 *  - DB-GATED (only with SUPABASE_URL + SERVICE_ROLE_KEY): asserts the live seed state
 *    (sponsor has view_finance/view_partner, lacks manage_finance/manage_partner; reads
 *    held by the same audience as before).
 *
 * Cross-ref: ADR-0110, ADR-0025 (Q1, superseded), ADR-0033, ADR-0043 (trigger retained),
 * plan ~/.claude/plans/onda-2-auditoria-keen-kahn.md (F1 + F9), #952.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const FU1 = '20260805000291_onda2_fu1_sponsor_read_only_split.sql';

function loadMigrations() {
  return readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .map((f) => ({ name: f, body: readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8') }));
}

// ─────────────────────────────────────────────────────────────────────────────
// STATIC — migration shape + forward-defense (no DB env required)
// ─────────────────────────────────────────────────────────────────────────────
test('FU-1 migration 20260805000291 is present and correct', async (t) => {
  const migs = loadMigrations();
  const m = migs.find((x) => x.name === FU1);

  await t.test('migration file exists', () => {
    assert.ok(m, `${FU1} must exist`);
  });

  await t.test('seeds the new READ actions view_finance + view_partner', () => {
    assert.match(m.body, /'view_finance'/);
    assert.match(m.body, /'view_partner'/);
    // sponsor gets both read actions
    assert.match(m.body, /'sponsor',\s*'sponsor',\s*'view_finance'/);
    assert.match(m.body, /'sponsor',\s*'sponsor',\s*'view_partner'/);
  });

  await t.test('revokes the sponsor WRITE seeds (manage_finance + manage_partner)', () => {
    assert.match(m.body, /DELETE\s+FROM\s+public\.engagement_kind_permissions[\s\S]*?kind\s*=\s*'sponsor'[\s\S]*?action\s+IN\s*\(\s*'manage_finance'\s*,\s*'manage_partner'\s*\)/i);
  });

  await t.test('repoints exactly the 12 read RPCs (CREATE OR REPLACE) with view gates, no manage gate left', () => {
    const creates = (m.body.match(/^CREATE OR REPLACE FUNCTION/gm) || []).length;
    assert.equal(creates, 12, `expected 12 repointed read functions, found ${creates}`);
    // No read gate should still reference a manage_* action inside a can_by_member(...) call.
    assert.ok(!/can_by_member\([^,]+,\s*'manage_(finance|partner)'\)/.test(m.body),
      'no repointed read body may still gate on manage_finance/manage_partner');
    // The new view gates are present.
    assert.match(m.body, /can_by_member\([^,]+,\s*'view_finance'\)/);
    assert.match(m.body, /can_by_member\([^,]+,\s*'view_partner'\)/);
  });

  await t.test('has an in-tx fail-closed post-condition block', () => {
    assert.match(m.body, /DO\s*\$verify\$/);
    assert.match(m.body, /RAISE\s+EXCEPTION/);
  });
});

test('forward-defense: no migration after FU-1 re-seeds a sponsor WRITE action', async () => {
  const migs = loadMigrations();
  const idx = migs.findIndex((x) => x.name === FU1);
  assert.ok(idx >= 0, 'FU-1 migration must anchor the invariant');

  // A later migration that INSERTs (sponsor, sponsor, manage_finance|manage_partner) is a regression.
  // Anchor to a single VALUES tuple to avoid multi-row false positives.
  const reseed = /'sponsor'\s*,\s*'sponsor'\s*,\s*'manage_(finance|partner)'/i;
  const offenders = migs.slice(idx + 1).filter((x) => reseed.test(x.body));
  assert.equal(offenders.length, 0,
    `Migrations after FU-1 must not re-grant sponsor write. Offenders: ${offenders.map((x) => x.name).join(', ')}`);
});

// ─────────────────────────────────────────────────────────────────────────────
// DB-GATED — live seed state (skips silently offline, per WATCH-205.A)
// ─────────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);

test('FU-1 live seed state: sponsor read-only', { skip: dbGated ? false : 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required' }, async (t) => {
  const { createClient } = await import('@supabase/supabase-js');
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  const { data, error } = await sb
    .from('engagement_kind_permissions')
    .select('action')
    .eq('kind', 'sponsor').eq('role', 'sponsor');
  assert.ok(!error, error?.message);
  const actions = new Set((data || []).map((r) => r.action));

  await t.test('sponsor has NO write actions', () => {
    assert.ok(!actions.has('manage_finance'), 'sponsor must not hold manage_finance');
    assert.ok(!actions.has('manage_partner'), 'sponsor must not hold manage_partner');
  });

  await t.test('sponsor retains the READ actions (reads preserved)', () => {
    assert.ok(actions.has('view_finance'), 'sponsor must hold view_finance');
    assert.ok(actions.has('view_partner'), 'sponsor must hold view_partner');
  });

  await t.test('view_partner read audience still includes chapter_board liaison (unchanged)', async () => {
    const { data: liaison } = await sb
      .from('engagement_kind_permissions')
      .select('action')
      .eq('kind', 'chapter_board').eq('role', 'liaison').eq('action', 'view_partner');
    assert.ok((liaison || []).length === 1, 'chapter_board liaison must hold view_partner');
  });
});
