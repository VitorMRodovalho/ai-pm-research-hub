/**
 * ADR-0012 — Static contract: cache/derivable columns must ship with triggers
 *
 * Complements:
 *   - rpc-v4-auth.test.mjs       — ADR-0011 auth gate static check
 *   - schema-invariants.test.mjs — ADR-0012 live-DB runtime violations
 *
 * Gap this test closes: a new migration that adds a column to `members`,
 * `engagements`, or `initiatives` should either (a) ship a trigger in the
 * same file that maintains the column's invariant, or (b) explicitly declare
 * the column as storage-only via STORAGE_ONLY_ALLOWLIST with a rationale.
 *
 * Why: cache columns without triggers drift silently. B5+B7 (2026-04-17)
 * and the `operational_role` cache (V4 Phase 4) both exist because earlier
 * approaches allowed manual UPDATE paths that diverged from the source of
 * truth. ADR-0012 makes this explicit: on these 3 tables, the default is
 * "derivable, needs a trigger"; pure-storage must be opted-in.
 *
 * Enforcement window: migrations ≥ CUTOVER are under the contract. Earlier
 * migrations contain historical ADD COLUMN that predate the ADR.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const MIGRATIONS_DIR = resolve(process.cwd(), 'supabase/migrations');

// ADR-0012 effective from 2026-04-26 (post Eixo B closure + volunteer_funnel refactor).
// Earlier migrations are historical and covered by live-DB invariants test.
const CUTOVER = '20260426020000';

const PROTECTED_TABLES = ['members', 'engagements', 'initiatives'];

// Columns added post-cutover that are pure storage (manual INSERT/UPDATE by
// app code, not derived from other state) must be explicitly declared here.
// Each entry: 'table.column' → short reason. Keeps reviewers honest about the
// derivability trade-off instead of letting it slip silently.
const STORAGE_ONLY_ALLOWLIST = new Map([
  // Pure user preference — opt-in/out flag for weekly card digest (issue #98, p39).
  // Set only via /settings/notifications toggle; not derivable from any other state.
  ['members.notify_weekly_digest', 'User opt-out flag for weekly card digest; no derivation source'],
  // Pure user preference — 4-mode delivery (immediate_all/weekly_digest/suppress_all/custom_per_type)
  // for ADR-0022 W2 communication batching (p61). Set only via /settings/notifications RPC
  // set_my_notification_prefs(); not derivable from any other state. CHECK constraint enforces enum.
  ['members.notify_delivery_mode_pref', 'User-chosen email delivery mode (ADR-0022 W2); no derivation source'],
]);

// ADR-0011 contract reuses this allowlist — keep it sorted for review.

function parseAddColumns(sql) {
  // Matches: ALTER TABLE [public.]table ADD COLUMN [IF NOT EXISTS] column_name ...
  // Skips: ADD CONSTRAINT, ADD CHECK, ADD FOREIGN KEY, etc.
  const regex = /ALTER\s+TABLE\s+(?:public\.)?([a-z_][a-z0-9_]*)\s+ADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-z_][a-z0-9_]*)/gi;
  const out = [];
  let m;
  while ((m = regex.exec(sql)) !== null) {
    out.push({ table: m[1], column: m[2] });
  }
  return out;
}

function fileHasTrigger(sql) {
  // Accepts CREATE TRIGGER, CREATE OR REPLACE TRIGGER, or trigger-returning functions
  // (LANGUAGE plpgsql … RETURNS trigger). The latter covers migrations that create
  // the function + attach it via CREATE TRIGGER in the same file.
  return /CREATE\s+(?:OR\s+REPLACE\s+)?TRIGGER/i.test(sql)
      || /\bRETURNS\s+trigger\b/i.test(sql);
}

test('ADR-0012: new columns on members/engagements/initiatives ship with triggers or are allowlisted', () => {
  const files = readdirSync(MIGRATIONS_DIR)
    .filter(f => f.endsWith('.sql') && f >= CUTOVER)
    .sort();

  const violations = [];
  for (const f of files) {
    const sql = readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8');
    const added = parseAddColumns(sql).filter(a => PROTECTED_TABLES.includes(a.table));
    if (added.length === 0) continue;

    const hasTrigger = fileHasTrigger(sql);
    for (const { table, column } of added) {
      const key = `${table}.${column}`;
      if (hasTrigger) continue;
      if (STORAGE_ONLY_ALLOWLIST.has(key)) continue;
      violations.push(`${f} :: ${key}`);
    }
  }

  if (violations.length > 0) {
    const msg = [
      'ADR-0012 violation: new columns on protected tables (members/engagements/initiatives)',
      'MUST ship with either:',
      '  (a) a trigger in the SAME migration that keeps the column in sync with its source,',
      '      or validates/coerces it on INSERT/UPDATE (BEFORE trigger pattern); OR',
      '  (b) an entry in STORAGE_ONLY_ALLOWLIST (tests/contracts/schema-cache-columns.test.mjs)',
      '      with a short rationale explaining why no trigger is needed.',
      '',
      'Why: cache/derivable columns without triggers cause silent drift. B5+B7 and the',
      'operational_role cache exist because prior manual-sync patterns diverged in prod.',
      '',
      'Violations:',
      ...violations.map(v => `  - ${v}`),
      '',
      'Fix: add a trigger to the migration, OR register the column as storage-only.',
    ].join('\n');
    assert.fail(msg);
  }
});

test('ADR-0012: known cache columns are maintained by live triggers (reference map)', () => {
  // Documents the canonical cache-column → trigger-source mapping for reviewers.
  // Each trigger-source file must still exist and mention the trigger name.
  const KNOWN_CACHE_COLUMNS = [
    {
      key: 'members.operational_role',
      trigger: 'trg_sync_role_cache',
      source: '20260413430000_v4_phase4_role_cache_sync.sql',
      note: 'Cache of engagements role aggregation (ADR-0007).',
    },
    {
      key: 'members.member_status',
      trigger: 'trg_sync_member_status_consistency',
      source: '20260424070000_b5_b7_member_invariants.sql',
      note: 'B5+B7 status/role/designations invariants (ADR-0011).',
    },
    {
      key: 'members.tribe_id',
      trigger: 'trg_b_sync_tribe_members',
      source: '20260413230000_v4_phase2_dual_write_triggers.sql',
      note: 'Dual-write bridge engagements → members.tribe_id (ADR-0005).',
    },
    {
      key: 'initiatives.custom_fields',
      trigger: 'trg_validate_initiative_metadata',
      source: '20260413620000_v4_phase6_custom_fields_validation.sql',
      note: 'Config-driven metadata validation per kind (ADR-0009).',
    },
  ];

  // Cache columns WITHOUT trigger — registered as DEBT via COMMENT ON COLUMN
  // (data-architect tier 3 audit p28). Fix pendente: trigger dedicated per column.
  // This block does NOT fail the test — just documents the debt. Trigger implementation
  // requires domain decision per column and lives in separate session.
  const UNSYNCED_CACHE_DEBT = [
    { key: 'members.current_cycle_active', source_hint: 'selection_cycles + member_cycle_enrollments' },
    { key: 'members.cpmai_certified',      source_hint: 'certificates WHERE type=cpmai' },
    { key: 'members.credly_badges',        source_hint: 'Credly API (external)' },
    { key: 'members.cycles',               source_hint: 'selection_applications + enrollments' },
  ];
  // Each debt column MUST have a COMMENT ON COLUMN in migration 20260504070000
  // documenting the drift risk explicitly. Assert file exists at minimum.
  const debtDocPath = resolve(MIGRATIONS_DIR, '20260504070000_adr0012_document_unsynced_cache_columns.sql');
  assert.ok(existsSync(debtDocPath),
    `Expected ADR-0012 debt documentation migration to exist at ${debtDocPath}. ` +
    `If you removed it, also remove the UNSYNCED_CACHE_DEBT entries from this test.`);
  const debtDoc = readFileSync(debtDocPath, 'utf8');
  for (const { key } of UNSYNCED_CACHE_DEBT) {
    const [, column] = key.split('.');
    assert.ok(
      debtDoc.includes(column),
      `Expected COMMENT ON COLUMN for ${key} in debt documentation migration (${debtDocPath})`,
    );
  }

  for (const { key, trigger, source, note } of KNOWN_CACHE_COLUMNS) {
    const path = resolve(MIGRATIONS_DIR, source);
    assert.ok(existsSync(path), `Expected trigger source migration ${source} to exist for ${key}`);
    const sql = readFileSync(path, 'utf8');
    assert.ok(
      sql.includes(trigger),
      `Expected trigger "${trigger}" in ${source} (maintains ${key}: ${note})`,
    );
  }
});
