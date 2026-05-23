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
  // Admin-facing reminder for stale interviews (W2 Leaf 2 — emitted by cron)
  selection_interview_overdue: 'digest_weekly',
  // Candidate-facing invite to book interview after objective phase clears
  // (W2 Leaf 4 — dispatched via notify_selection_cutoff_approved RPC)
  selection_cutoff_approved: 'transactional_immediate',
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

test('ADR-0022 Amendment D: catalog metadata bumped per latest selection workstream ship', () => {
  // W1.4 shipped Leaf 1; W1.5 ships Leaf 2 (selection_interview_overdue). Each
  // selection workstream leaf bumps the catalog minor version so reviewers can
  // spot the latest active milestone in the catalog file alone.
  assert.ok(['W1.4', 'W1.5', 'W1.6', 'W1.7', 'W1.8', 'W1.9', 'W1.10'].includes(catalog.version),
    `Catalog version must be ≥ W1.4 (Amendment D shipping). Got "${catalog.version}".`);
  assert.equal(catalog.updated_at, '2026-05-23',
    'Catalog updated_at must be 2026-05-23 (p228 selection workstream ship date).');
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

// ─── Amendment D / p228 #260 W2 Leaf 2 contracts ───
// selection_interview_overdue: new admin-facing type + daily cron with 7d
// idempotency window. Forward-defense locks the cron RPC signature, the pg_cron
// schedule, and the scope guards (24h grace + status filter).

test('ADR-0022 Amendment D Leaf 2: _selection_interview_overdue_cron RPC declared with idempotency guard', () => {
  const match = findLatestFunctionMatch('_selection_interview_overdue_cron');
  assert.ok(match, '_selection_interview_overdue_cron must be declared in some migration.');
  const wrapper = match[0];
  const body = match[2];

  assert.ok(/SECURITY\s+DEFINER/i.test(wrapper),
    '_selection_interview_overdue_cron must be SECURITY DEFINER.');
  assert.ok(/RETURNS\s+jsonb/i.test(wrapper),
    '_selection_interview_overdue_cron must RETURN jsonb (count + run_at envelope).');

  // 24h grace window — prevents alerting interviews running late same-day
  assert.ok(/scheduled_at\s*<\s*now\(\)\s*-\s*interval\s+'24\s*hours'/i.test(body),
    'Cron must enforce 24-hour grace window.');

  // Status scope guard — only scheduled/rescheduled trigger alerts
  assert.ok(/status\s+IN\s*\(\s*'scheduled'\s*,\s*'rescheduled'\s*\)/i.test(body),
    'Cron scope must include status IN (scheduled, rescheduled).');

  // Conducted_at NULL guard — completed interviews never alert
  assert.ok(/conducted_at\s+IS\s+NULL/i.test(body),
    'Cron must require conducted_at IS NULL.');

  // 7-day idempotency window — one notif per (interview, recipient) per week
  assert.ok(/NOT\s+EXISTS[\s\S]{0,800}selection_interview_overdue[\s\S]{0,600}now\(\)\s*-\s*interval\s+'7\s*days'/i.test(body),
    'Cron must implement 7-day NOT EXISTS idempotency window.');

  // INSERT routes via helper (no hardcoded delivery_mode)
  assert.ok(/_delivery_mode_for\(\s*'selection_interview_overdue'\s*\)/i.test(body),
    'Cron INSERT must derive delivery_mode via _delivery_mode_for helper.');

  // Source attribution for traceability + dedupe
  assert.ok(/source_type[\s\S]{0,200}'selection_interview'/i.test(body),
    "Cron must set source_type='selection_interview' for traceability.");
});

test('ADR-0022 Amendment D Leaf 2: pg_cron schedule selection-interview-overdue-daily declared', () => {
  assert.ok(/cron\.schedule\(\s*'selection-interview-overdue-daily'\s*,\s*'0\s+14\s+\*\s+\*\s+\*'/i.test(allSQL),
    'pg_cron schedule selection-interview-overdue-daily must run at 14:00 UTC daily.');
  // Cron body must call the RPC
  assert.ok(/cron\.schedule\([\s\S]{0,200}'selection-interview-overdue-daily'[\s\S]{0,400}public\._selection_interview_overdue_cron/i.test(allSQL),
    'pg_cron schedule must invoke public._selection_interview_overdue_cron().');
});

test('ADR-0022 Amendment D Leaf 2: cron RPC grants restrict to service_role only', () => {
  // Service-role-only execution prevents authenticated users from triggering admin spam
  assert.ok(/REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\._selection_interview_overdue_cron[\s\S]{0,200}FROM\s+public[\s\S]{0,200}anon[\s\S]{0,200}authenticated/i.test(allSQL),
    'Cron RPC must REVOKE ALL FROM public, anon, authenticated.');
  assert.ok(/GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\._selection_interview_overdue_cron[\s\S]{0,200}TO\s+service_role/i.test(allSQL),
    'Cron RPC must GRANT EXECUTE TO service_role.');
});

test('ADR-0022 Amendment D Leaf 2: p228 Leaf 2 migration file exists', () => {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql'));
  const leafTwo = files.find(f => f.includes('p228_260_w2_leaf2_selection_interview_overdue_cron'));
  assert.ok(leafTwo,
    'Migration 20260805000009_p228_260_w2_leaf2_selection_interview_overdue_cron.sql must exist.');
  const body = readFileSync(join(MIGRATIONS_DIR, leafTwo), 'utf8');
  assert.ok(/NOTIFY\s+pgrst\s*,\s*'reload schema'/i.test(body),
    'Leaf 2 migration must NOTIFY pgrst to reload schema.');
  // Idempotent cron re-registration — unschedule prior if exists
  assert.ok(/IF\s+EXISTS[\s\S]{0,200}'selection-interview-overdue-daily'[\s\S]{0,200}cron\.unschedule/i.test(body),
    'Leaf 2 migration must idempotently unschedule prior version before re-creating cron.');
});

// ─── Amendment D / p228 #260 W2 Leaf 3 contracts ───
// Soft AI gate: dispatch_peer_review_invitations no longer hard-blocks when AI
// context is absent. Forward-defense locks the parameter count, body branches,
// and admin_audit_log capture of no_ai_context + no_ai_reason.

test('ADR-0022 Amendment D Leaf 3: dispatch_peer_review_invitations gains p_force_no_ai_context parameter', () => {
  const match = findLatestFunctionMatch('dispatch_peer_review_invitations');
  assert.ok(match, 'dispatch_peer_review_invitations must be declared.');
  const wrapper = match[0];

  // Three params: p_application_id uuid, p_max_peers integer DEFAULT 2,
  // p_force_no_ai_context boolean DEFAULT false
  assert.ok(/p_force_no_ai_context\s+boolean\s+DEFAULT\s+false/i.test(wrapper),
    'Leaf 3: dispatch_peer_review_invitations must declare p_force_no_ai_context boolean DEFAULT false parameter.');
});

test('ADR-0022 Amendment D Leaf 3: hard PEER_PRECONDITION raise is removed', () => {
  const match = findLatestFunctionMatch('dispatch_peer_review_invitations');
  assert.ok(match);
  const body = match[2];

  // Forward-defense: latest body MUST NOT raise PEER_PRECONDITION (the audit doc
  // identified this as the cycle 4 hard-block source). Implicit no-AI now flows
  // through to v_no_ai_context flag.
  assert.ok(!/RAISE\s+EXCEPTION\s+'PEER_PRECONDITION/i.test(body),
    'Leaf 3: PEER_PRECONDITION hard raise must be removed (soft gate). Re-introducing it regresses cycle 4 fix.');
});

test('ADR-0022 Amendment D Leaf 3: no_ai_context branching with 4 reason states', () => {
  const match = findLatestFunctionMatch('dispatch_peer_review_invitations');
  assert.ok(match);
  const body = match[2];

  // The four sources of no_ai_context flag, in priority order:
  //   admin_override → explicit force
  //   no_consent     → consent_ai_analysis_at IS NULL
  //   analysis_pending → ai_analysis IS NULL
  //   (else)         → v_no_ai_context := false (AI context available)
  for (const reason of ['admin_override', 'no_consent', 'analysis_pending']) {
    assert.ok(body.includes(`'${reason}'`),
      `Leaf 3: no_ai_reason value '${reason}' must be present in dispatch body.`);
  }
  assert.ok(/v_no_ai_context\s*:=\s*true/i.test(body),
    'Leaf 3: dispatch body must assign v_no_ai_context := true in at least one branch.');
  assert.ok(/v_no_ai_context\s*:=\s*false/i.test(body),
    'Leaf 3: dispatch body must have a v_no_ai_context := false branch for AI-present path.');
});

test('ADR-0022 Amendment D Leaf 3: no_ai_context flows into audit log + return jsonb', () => {
  const match = findLatestFunctionMatch('dispatch_peer_review_invitations');
  assert.ok(match);
  const body = match[2];

  // admin_audit_log changes JSON must capture no_ai_context + no_ai_reason
  assert.ok(/'no_ai_context'\s*,\s*v_no_ai_context/i.test(body),
    "Leaf 3: admin_audit_log changes JSON must include 'no_ai_context' field.");
  assert.ok(/'no_ai_reason'\s*,\s*v_no_ai_reason/i.test(body),
    "Leaf 3: admin_audit_log changes JSON must include 'no_ai_reason' field.");

  // Return jsonb must surface the flags for callers
  const lastReturn = body.split('RETURN ').pop();
  assert.ok(/'no_ai_context'\s*,\s*v_no_ai_context/i.test(lastReturn),
    "Leaf 3: terminal RETURN jsonb must include 'no_ai_context' for caller visibility.");
});

test('ADR-0022 Amendment D Leaf 3: peer_review_requested INSERT uses helper for delivery_mode', () => {
  const match = findLatestFunctionMatch('dispatch_peer_review_invitations');
  assert.ok(match);
  const body = match[2];

  // Pre-leaf-3, delivery_mode was hardcoded 'transactional_immediate' at INSERT.
  // Leaf 3 routes through _delivery_mode_for so the policy matrix stays the single
  // source of truth (Leaf 1 added 'peer_review_requested' to helper).
  assert.ok(/_delivery_mode_for\(\s*'peer_review_requested'\s*\)/i.test(body),
    'Leaf 3: peer_review_requested INSERT must derive delivery_mode via _delivery_mode_for helper (not hardcoded).');
});

test('ADR-0022 Amendment D Leaf 3: p228 Leaf 3 migration uses DROP + CREATE pattern + restores GRANTs', () => {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql'));
  const leafThree = files.find(f => f.includes('p228_260_w2_leaf3_soft_ai_gate_no_ai_context'));
  assert.ok(leafThree,
    'Migration 20260805000010_p228_260_w2_leaf3_soft_ai_gate_no_ai_context.sql must exist.');
  const body = readFileSync(join(MIGRATIONS_DIR, leafThree), 'utf8');

  // GC-097 §4: parameter count changes require DROP first (to avoid PostgreSQL
  // creating a parallel overload). CREATE OR REPLACE for the brand-new signature
  // is equivalent to CREATE since no function with that signature exists post-DROP,
  // AND keeps the function discoverable by the test's findLatestFunctionMatch helper.
  assert.ok(/DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.dispatch_peer_review_invitations\s*\(\s*uuid\s*,\s*integer\s*\)/i.test(body),
    'Leaf 3 migration must DROP IF EXISTS the prior dispatch_peer_review_invitations(uuid, integer) signature.');
  assert.ok(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.dispatch_peer_review_invitations\s*\([^)]*p_force_no_ai_context/i.test(body),
    'Leaf 3 migration must CREATE (or CREATE OR REPLACE) FUNCTION with the new 3-param signature including p_force_no_ai_context.');

  // GRANTs restored to authenticated + service_role; explicitly REVOKE anon
  assert.ok(/GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.dispatch_peer_review_invitations\([^)]*boolean[^)]*\)\s+TO\s+authenticated\s*,\s*service_role/i.test(body),
    'Leaf 3 migration must GRANT EXECUTE TO authenticated, service_role on new signature.');
  assert.ok(/REVOKE\s+ALL[\s\S]{0,300}dispatch_peer_review_invitations[\s\S]{0,200}FROM[\s\S]{0,200}anon/i.test(body),
    'Leaf 3 migration must REVOKE anon from new signature.');

  // NOTIFY pgrst to publish new signature
  assert.ok(/NOTIFY\s+pgrst\s*,\s*'reload schema'/i.test(body),
    'Leaf 3 migration must NOTIFY pgrst to reload schema.');
});

// ─── Amendment D / p228 #260 W2 Leaf 4 contracts ───
// selection_cutoff_approved: new candidate-facing type + manual dispatch RPC + multi-lang
// campaign template. Forward-defense locks the idempotency column, authority gate,
// and the email goes via campaign_send_one_off (NOT notifications table, since
// candidate is not a member yet).

test('ADR-0022 Amendment D Leaf 4: selection_applications.cutoff_approved_email_sent_at column declared', () => {
  assert.ok(
    /ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+cutoff_approved_email_sent_at\s+timestamptz/i.test(allSQL),
    'Leaf 4 migration must declare ADD COLUMN cutoff_approved_email_sent_at timestamptz for single-fire idempotency.'
  );
});

test('ADR-0022 Amendment D Leaf 4: notify_selection_cutoff_approved RPC declared with authority + idempotency', () => {
  const match = findLatestFunctionMatch('notify_selection_cutoff_approved');
  assert.ok(match, 'notify_selection_cutoff_approved must be declared in some migration.');
  const wrapper = match[0];
  const body = match[2];

  assert.ok(/SECURITY\s+DEFINER/i.test(wrapper),
    'notify_selection_cutoff_approved must be SECURITY DEFINER.');
  assert.ok(/RETURNS\s+jsonb/i.test(wrapper),
    'notify_selection_cutoff_approved must RETURN jsonb (envelope with success + idempotency state).');

  // Authority gate — same pattern as dispatch_peer_review_invitations
  assert.ok(/selection_committee[\s\S]{0,400}role\s*=\s*'lead'/i.test(body),
    'Authority gate must check selection_committee.role = lead.');
  assert.ok(/can_by_member\(\s*v_caller\.id\s*,\s*'manage_member'/i.test(body),
    "Authority gate must fall back to can_by_member('manage_member').");

  // Single-fire idempotency on cutoff_approved_email_sent_at
  assert.ok(/cutoff_approved_email_sent_at\s+IS\s+NOT\s+NULL/i.test(body),
    'Idempotency guard must check cutoff_approved_email_sent_at IS NOT NULL.');

  // Dispatches via campaign_send_one_off (NOT notifications table — candidate not member)
  assert.ok(/campaign_send_one_off[\s\S]{0,400}'selection_cutoff_approved'/i.test(body),
    'Email must dispatch via campaign_send_one_off with template_slug selection_cutoff_approved.');

  // Marks idempotency post-send
  assert.ok(/UPDATE\s+public\.selection_applications[\s\S]{0,300}cutoff_approved_email_sent_at\s*=\s*now\(\)/i.test(body),
    'After dispatch, RPC must UPDATE selection_applications SET cutoff_approved_email_sent_at = now().');

  // Audit log
  assert.ok(/admin_audit_log[\s\S]{0,1000}'selection\.cutoff_approved_email_dispatched'/i.test(body),
    'RPC must write admin_audit_log entry with action selection.cutoff_approved_email_dispatched.');

  // Booking URL precondition
  assert.ok(/CUTOFF_NO_BOOKING_URL/i.test(body),
    'RPC must raise CUTOFF_NO_BOOKING_URL when cycle has no interview_booking_url.');
});

test('ADR-0022 Amendment D Leaf 4: notify_selection_cutoff_approved grants restrict anon', () => {
  assert.ok(/REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.notify_selection_cutoff_approved\(uuid\)\s+FROM\s+PUBLIC\s*,\s*anon/i.test(allSQL),
    'RPC must REVOKE ALL FROM PUBLIC, anon.');
  assert.ok(/GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.notify_selection_cutoff_approved\(uuid\)\s+TO\s+authenticated\s*,\s*service_role/i.test(allSQL),
    'RPC must GRANT EXECUTE TO authenticated, service_role.');
});

test('ADR-0022 Amendment D Leaf 4: selection_cutoff_approved campaign template declared with multi-lang body', () => {
  // INSERT on campaign_templates with the canonical slug + ON CONFLICT upsert pattern
  assert.ok(/INSERT\s+INTO\s+public\.campaign_templates[\s\S]{0,500}'selection_cutoff_approved'/i.test(allSQL),
    'Leaf 4 migration must INSERT campaign_templates row for slug selection_cutoff_approved.');
  // Multi-language body required (PT/EN/ES) — matching interview_reminder_1h pattern
  for (const lang of ['pt', 'en', 'es']) {
    assert.ok(
      new RegExp(`'${lang}'\\s*,\\s*'[^']{0,5000}interview_booking_url`, 'i').test(allSQL),
      `Template body must include ${lang} variant referencing interview_booking_url variable.`
    );
  }
  // Variables declaration must list first_name + interview_booking_url
  assert.ok(/'first_name'[\s\S]{0,200}'interview_booking_url'/i.test(allSQL),
    'Template variables must declare first_name + interview_booking_url as required.');
  // Upsert idempotency
  assert.ok(/ON\s+CONFLICT\s*\(\s*slug\s*\)\s+DO\s+UPDATE/i.test(allSQL),
    'Template INSERT must use ON CONFLICT (slug) DO UPDATE for idempotent reruns.');
});

test('ADR-0022 Amendment D Leaf 4: p228 Leaf 4 migration file exists', () => {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql'));
  const leafFour = files.find(f => f.includes('p228_260_w2_leaf4_selection_cutoff_approved'));
  assert.ok(leafFour,
    'Migration 20260805000011_p228_260_w2_leaf4_selection_cutoff_approved.sql must exist.');
  const body = readFileSync(join(MIGRATIONS_DIR, leafFour), 'utf8');
  assert.ok(/NOTIFY\s+pgrst\s*,\s*'reload schema'/i.test(body),
    'Leaf 4 migration must NOTIFY pgrst to reload schema.');
});
