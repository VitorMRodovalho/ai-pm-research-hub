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

// Match latest CREATE OR REPLACE FUNCTION public.<name> body across all migrations.
// PostgreSQL allows arbitrary dollar-quoting tags ($$, $function$, $body$, …); the
// backreference \1 ensures we close on the same tag we opened with. Returns the full
// match (so callers can read body via [2] or wrapper text via [0]).
function findLatestFunctionMatch(name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${escaped}\\b[\\s\\S]*?AS\\s+(\\$\\w*\\$)([\\s\\S]*?)\\1`,
    'gi'
  );
  const matches = [...allSQL.matchAll(regex)];
  return matches.length > 0 ? matches[matches.length - 1] : null;
}

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
  const match = findLatestFunctionMatch('_delivery_mode_for');
  assert.ok(match, '_delivery_mode_for body not located.');
  const body = match[2];

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
  const match = findLatestFunctionMatch('get_weekly_member_digest');
  assert.ok(match, 'get_weekly_member_digest must be declared.');
  const body = match[2];

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
  const match = findLatestFunctionMatch('generate_weekly_member_digest_cron');
  assert.ok(match, 'generate_weekly_member_digest_cron must be declared.');
  const body = match[2];

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
  const match = findLatestFunctionMatch('set_my_notification_prefs');
  assert.ok(match);
  const wrapper = match[0];
  assert.ok(/SECURITY\s+DEFINER/i.test(wrapper),
    'set_my_notification_prefs must be SECURITY DEFINER.');
});

// ─── W3 contracts (p62) ───

test('ADR-0022 W3: get_weekly_tribe_digest RPC declared with aggregate-only sections', () => {
  const match = findLatestFunctionMatch('get_weekly_tribe_digest');
  assert.ok(match, 'get_weekly_tribe_digest must be declared.');
  const body = match[2];

  // Aggregate keys (privacy-preserving — no individual cards)
  const requiredAggs = [
    'active_members', 'members_with_overdue_cards', 'cards_overdue_total',
    'cards_due_next_7d', 'cards_without_assignee', 'cards_without_due_date',
    'cards_completed_window', 'tribe_health_pct'
  ];
  for (const agg of requiredAggs) {
    assert.ok(body.includes(`'${agg}'`),
      `Aggregate key '${agg}' must appear in get_weekly_tribe_digest body.`);
  }
});

test('ADR-0022 W3: generate_weekly_leader_digest_cron orchestrator declared', () => {
  const match = findLatestFunctionMatch('generate_weekly_leader_digest_cron');
  assert.ok(match, 'generate_weekly_leader_digest_cron must be declared.');
  const body = match[2];

  // p173: cron refactored from tribe-centric to initiative-aware.
  // Calls get_weekly_initiative_digest (new) instead of get_weekly_tribe_digest.
  // Notification type kept ('weekly_tribe_digest_leader') for email handler back-compat.
  assert.ok(body.includes('get_weekly_initiative_digest'),
    'Leader orchestrator must call get_weekly_initiative_digest RPC (p173 refactor).');
  assert.ok(body.includes('weekly_tribe_digest_leader'),
    'Leader orchestrator must insert weekly_tribe_digest_leader notification type (back-compat).');
  assert.ok(body.includes('suppress_all'),
    'Leader orchestrator must respect suppress_all preference.');
});

test('ADR-0022 W3: tribe_broadcast urgent rate-limit trigger declared', () => {
  assert.ok(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\._tribe_broadcast_urgent_rate_limit/i.test(allSQL),
    'Rate-limit trigger function must be declared.');
  assert.ok(/CREATE\s+TRIGGER\s+trg_tribe_broadcast_urgent_rate_limit/i.test(allSQL),
    'Trigger trg_tribe_broadcast_urgent_rate_limit must be declared.');
  // Must enforce 1/week limit
  const match = findLatestFunctionMatch('_tribe_broadcast_urgent_rate_limit');
  const body = match[2];
  assert.ok(/v_actor_count\s*>=\s*1/i.test(body),
    'Rate-limit must enforce >= 1 (1 batch per week per actor).');
  assert.ok(/rate_limit_exceeded/i.test(body),
    'Rate-limit must raise rate_limit_exceeded exception.');
});

test('ADR-0022 W3: set_my_muted_notification_types + get_my_notification_metrics RPCs declared', () => {
  assert.ok(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.set_my_muted_notification_types/i.test(allSQL),
    'set_my_muted_notification_types RPC must be declared.');
  assert.ok(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.get_my_notification_metrics/i.test(allSQL),
    'get_my_notification_metrics RPC must be declared.');
});

// ─── Amendment D / p228 #260 W2 Leaf 1 contracts (2026-05-23) ───
//
// PM Policy Matrix ratified for selection funnel notification types. Forward-defense:
// each selection_* type below MUST be in the catalog with the expected delivery_mode
// AND must appear as an explicit case in the latest _delivery_mode_for helper body.
// Detecting drift on any one of these is a Stop-The-Line signal.

const SELECTION_POLICY_MATRIX = {
  // Candidate-facing operational (transactional_immediate) — bypass suppress_all per W2 Leaf 6
  selection_termo_due: 'transactional_immediate',
  selection_approved: 'transactional_immediate',
  selection_interview_scheduled: 'transactional_immediate',
  // Evaluator-facing operational (transactional_immediate)
  peer_review_requested: 'transactional_immediate',
  // Admin-facing dashboard-only (suppress)
  selection_evaluation_complete: 'suppress',
  // Admin-facing recap (digest_weekly explicit for parity + forward-drift detection)
  selection_interview_noshow: 'digest_weekly',
};

test('ADR-0022 Amendment D: selection_* policy matrix present in catalog with expected modes', () => {
  for (const [type, expectedMode] of Object.entries(SELECTION_POLICY_MATRIX)) {
    const entry = catalog.types[type];
    assert.ok(entry,
      `Catalog must include "${type}" (W2 Leaf 1 PM Policy Matrix, 2026-05-23).`);
    assert.equal(entry.delivery_mode, expectedMode,
      `Catalog drift on "${type}": expected delivery_mode "${expectedMode}", got "${entry.delivery_mode}".`);
    assert.ok(typeof entry.rationale === 'string' && entry.rationale.includes('p228'),
      `Catalog entry "${type}" must cite p228 W2 Leaf 1 in rationale (audit trail).`);
  }
});

test('ADR-0022 Amendment D: catalog metadata bumped to W1.4 with updated_at 2026-05-23', () => {
  assert.equal(catalog.version, 'W1.4',
    'Catalog version must be bumped to W1.4 to reflect Amendment D shipping.');
  assert.equal(catalog.updated_at, '2026-05-23',
    'Catalog updated_at must be 2026-05-23 (p228 #260 W2 Leaf 1 ship date).');
});

test('ADR-0022 Amendment D: _delivery_mode_for helper explicit-case parity with selection policy', () => {
  // Every type in SELECTION_POLICY_MATRIX must appear as an explicit WHEN clause in
  // the latest helper body, regardless of whether the mode equals the ELSE default.
  // This locks the policy matrix into the SQL — future drift requires an explicit migration.
  const match = findLatestFunctionMatch('_delivery_mode_for');
  assert.ok(match, '_delivery_mode_for body not located.');
  const body = match[2];

  for (const [type, expectedMode] of Object.entries(SELECTION_POLICY_MATRIX)) {
    const literalQuoted = `'${type}'`;
    assert.ok(body.includes(literalQuoted),
      `Helper drift: "${type}" must have an explicit WHEN clause in latest _delivery_mode_for (W2 Leaf 1 policy).`);
    // Match the WHEN ... THEN pair for this type (allow whitespace).
    const whenPattern = new RegExp(
      `WHEN\\s+'${type}'\\s+THEN\\s+'${expectedMode}'`,
      'i'
    );
    assert.ok(whenPattern.test(body),
      `Helper drift: "${type}" must map to "${expectedMode}" (W2 Leaf 1 PM Policy Matrix).`);
  }
});

test('ADR-0022 Amendment D: p228 migration file exists and registers helper update', () => {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql'));
  const leafOne = files.find(f => f.includes('p228_260_w2_leaf1_selection_notification_catalog_helper_parity'));
  assert.ok(leafOne,
    'Migration 20260805000008_p228_260_w2_leaf1_selection_notification_catalog_helper_parity.sql must exist.');
  const body = readFileSync(join(MIGRATIONS_DIR, leafOne), 'utf8');
  assert.ok(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\._delivery_mode_for/i.test(body),
    'Leaf 1 migration must redefine _delivery_mode_for.');
  assert.ok(/NOTIFY\s+pgrst\s*,\s*'reload schema'/i.test(body),
    'Leaf 1 migration must NOTIFY pgrst to reload schema.');
});
