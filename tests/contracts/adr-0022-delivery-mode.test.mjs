/**
 * ADR-0022 W1 contract — notifications.delivery_mode invariants.
 *
 * Enforces:
 *  1. Catalog parity: every type in `_delivery_mode_for(p_type)` SQL helper
 *     is also documented in ADR-0022-notification-types-catalog.json (and vice
 *     versa for non-default types).
 *  2. CHECK constraint: the migration that adds `delivery_mode` declares the
 *     enum (transactional_immediate | digest_weekly | suppress). If any future
 *     migration tightens or replaces this, the contract still matches.
 *  3. Partial index `idx_notifications_digest_pending` is declared in some
 *     migration (enforces the W2 query path stays performant).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const CATALOG_PATH = resolve(ROOT, 'docs/adr/ADR-0022-notification-types-catalog.json');

function loadAllMigrationsConcat() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => readFileSync(join(MIGRATIONS_DIR, f), 'utf8')).join('\n');
}

function loadCatalog() {
  return JSON.parse(readFileSync(CATALOG_PATH, 'utf8'));
}

const allSQL = loadAllMigrationsConcat();
const catalog = loadCatalog();

test('ADR-0022 W1: catalog declares ≥3 delivery_modes', () => {
  const modes = Object.keys(catalog.delivery_modes);
  assert.ok(modes.includes('transactional_immediate'));
  assert.ok(modes.includes('digest_weekly'));
  assert.ok(modes.includes('suppress'));
});

test('ADR-0022 W1: CHECK constraint enum matches catalog modes', () => {
  // Find the migration that declares the CHECK and assert it lists the same
  // 3 modes the catalog documents.
  const expected = Object.keys(catalog.delivery_modes).sort().join(',');
  // Match either single-line or multiline CHECK clause containing all modes.
  const checkClauseMatches = allSQL.match(/CHECK\s*\(\s*delivery_mode\s+IN\s*\(([^)]+)\)\s*\)/i);
  assert.ok(checkClauseMatches, 'Migration must declare CHECK (delivery_mode IN (...)).');
  const declared = checkClauseMatches[1]
    .split(',')
    .map(s => s.trim().replace(/^['"]|['"]$/g, ''))
    .sort()
    .join(',');
  assert.equal(declared, expected,
    `CHECK enum drift: declared [${declared}] vs catalog [${expected}]`);
});

test('ADR-0022 W1: partial index idx_notifications_digest_pending declared', () => {
  // Required for the W2 digest aggregation hot path.
  assert.ok(/idx_notifications_digest_pending/i.test(allSQL),
    'Migration must declare idx_notifications_digest_pending');
  assert.ok(
    /idx_notifications_digest_pending[\s\S]*?WHERE\s+delivery_mode\s*=\s*['"]digest_weekly['"][\s\S]*?digest_delivered_at\s+IS\s+NULL/i.test(allSQL),
    'Index must be PARTIAL on (delivery_mode = digest_weekly AND digest_delivered_at IS NULL).');
});

test('ADR-0022 W1: _delivery_mode_for() helper exists in migrations', () => {
  assert.ok(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\._delivery_mode_for\s*\(/i.test(allSQL),
    'Helper public._delivery_mode_for(text) must be created in some migration.');
});

test('ADR-0022 W1: helper SQL covers every transactional_immediate + suppress type from catalog', () => {
  // Extract the LATEST CREATE/REPLACE _delivery_mode_for function body. Multiple
  // migrations may redefine this helper; runtime behavior tracks the last one
  // applied (CREATE OR REPLACE semantics) — so the contract checks the last.
  const helperRegex = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\._delivery_mode_for[\s\S]*?\$function\$([\s\S]*?)\$function\$/gi;
  const matches = [...allSQL.matchAll(helperRegex)];
  assert.ok(matches.length > 0, '_delivery_mode_for body not located.');
  const body = matches[matches.length - 1][1];

  for (const [type, info] of Object.entries(catalog.types)) {
    if (info.delivery_mode === 'digest_weekly') continue;  // covered by ELSE branch
    const literalQuoted = `'${type}'`;
    assert.ok(body.includes(literalQuoted),
      `Catalog type "${type}" (mode=${info.delivery_mode}) must appear in _delivery_mode_for body. Drift between SQL and catalog.`);
  }
});

test('ADR-0022 W1: every catalog type maps to a known delivery_mode', () => {
  const validModes = new Set(Object.keys(catalog.delivery_modes));
  for (const [type, info] of Object.entries(catalog.types)) {
    assert.ok(validModes.has(info.delivery_mode),
      `Type "${type}" maps to unknown delivery_mode "${info.delivery_mode}".`);
    assert.ok(typeof info.rationale === 'string' && info.rationale.length > 10,
      `Type "${type}" must include a rationale string (≥10 chars).`);
  }
});

test('ADR-0022 W1: digest_delivered_at + digest_batch_id columns declared', () => {
  assert.ok(/ADD\s+COLUMN[\s\S]{0,80}digest_delivered_at\s+timestamptz/i.test(allSQL),
    'digest_delivered_at column must be declared.');
  assert.ok(/ADD\s+COLUMN[\s\S]{0,80}digest_batch_id\s+uuid/i.test(allSQL),
    'digest_batch_id column must be declared.');
});

// ─── W2 contracts (p61) ───

test('ADR-0022 W2: members.notify_delivery_mode_pref column declared with 4-mode CHECK', () => {
  assert.ok(/ADD\s+COLUMN[\s\S]{0,200}notify_delivery_mode_pref\s+text/i.test(allSQL),
    'members.notify_delivery_mode_pref column must be declared.');
  // CHECK enum must list all 4 modes
  for (const mode of ['immediate_all', 'weekly_digest', 'suppress_all', 'custom_per_type']) {
    assert.ok(new RegExp(`notify_delivery_mode_pref[\\s\\S]{0,500}'${mode}'`, 'i').test(allSQL),
      `4-mode CHECK constraint must include '${mode}'.`);
  }
});

test('ADR-0022 W2: get_weekly_member_digest RPC declared with 7 sections', () => {
  // Find LAST definition (CREATE OR REPLACE semantics)
  const regex = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.get_weekly_member_digest\s*\([^)]*\)[\s\S]*?\$\$([\s\S]*?)\$\$/gi;
  const matches = [...allSQL.matchAll(regex)];
  assert.ok(matches.length > 0, 'get_weekly_member_digest must be declared.');
  const body = matches[matches.length - 1][1];

  // 7 section keys must appear in body
  const requiredSections = [
    'cards', 'engagements_new', 'events_upcoming', 'publications_new',
    'broadcasts', 'governance_pending', 'achievements'
  ];
  for (const section of requiredSections) {
    assert.ok(body.includes(`'${section}'`),
      `RPC body must include section key '${section}'.`);
  }
  // Must return consumed_notification_ids for orchestrator
  assert.ok(body.includes('consumed_notification_ids'),
    'RPC must include consumed_notification_ids field for orchestrator.');
});

test('ADR-0022 W2: generate_weekly_member_digest_cron orchestrator declared', () => {
  const regex = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.generate_weekly_member_digest_cron[\s\S]*?\$\$([\s\S]*?)\$\$/gi;
  const matches = [...allSQL.matchAll(regex)];
  assert.ok(matches.length > 0, 'generate_weekly_member_digest_cron must be declared.');
  const body = matches[matches.length - 1][1];

  // Must call get_weekly_member_digest
  assert.ok(body.includes('get_weekly_member_digest'),
    'Orchestrator must call get_weekly_member_digest RPC.');
  // Must respect notify_delivery_mode_pref (skip suppress_all/immediate_all)
  assert.ok(/notify_delivery_mode_pref[\s\S]{0,200}weekly_digest/i.test(body),
    'Orchestrator must filter by notify_delivery_mode_pref.');
  // Must mark consumed notifications
  assert.ok(/digest_delivered_at\s*=\s*now\(\)/i.test(body),
    'Orchestrator must mark consumed notifications digest_delivered_at.');
});

test('ADR-0022 W2: set_my_notification_prefs RPC declared (member self-edit)', () => {
  assert.ok(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.set_my_notification_prefs/i.test(allSQL),
    'set_my_notification_prefs RPC must be declared for /settings/notifications page.');
  // Must be SECURITY DEFINER (gates by auth.uid)
  const regex = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.set_my_notification_prefs[\s\S]*?\$\$([\s\S]*?)\$\$/gi;
  const matches = [...allSQL.matchAll(regex)];
  assert.ok(matches.length > 0);
  const wrapper = matches[matches.length - 1][0];
  assert.ok(/SECURITY\s+DEFINER/i.test(wrapper),
    'set_my_notification_prefs must be SECURITY DEFINER.');
});
