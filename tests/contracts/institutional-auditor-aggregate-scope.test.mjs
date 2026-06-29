/**
 * Forward-defense: FU-3 (#952 / ADR-0111) — institutional_auditor tier is an EXTERNAL,
 * aggregate-only, read-only persona. The whole point is allowlist-by-construction:
 * the dedicated action `view_aggregate_analytics` must reach ONLY the curated PII-free /
 * write-free aggregate RPCs, and must NEVER be seeded to any role other than the auditor,
 * nor wired into a PII-bearing RPC.
 *
 * Why this matters: the naive FU-3 plan (seed view_internal_analytics + view_chapter_dashboards)
 * was disproven by a live audit — those actions gate ~40 RPCs of which 37 return individual PII
 * or write (admin_list_members full directory, get_member_detail, get_selection_dashboard,
 * get_org_chart, get_tribe_gamification, + 5 writes). This test is the tripwire that keeps the
 * new action from sliding back into that surface.
 *
 * Static-only (no DB env): parses migration history. Behavioural 2-sided proof done live
 * (apply-time fail-closed DO block + session verification, 2026-06-29).
 *
 * Cross-ref:
 *   - supabase/migrations/20260805000292_onda2_fu3_institutional_auditor.sql
 *   - docs/adr/ADR-0111-institutional-auditor-aggregate-analytics.md
 *   - ADR-0023 (ladder parity — see role-ladder-parity.test.mjs)
 *   - ADR-0007 (V4 can()), ADR-0009 (kinds = config)
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const FU3_FILE = '20260805000292_onda2_fu3_institutional_auditor.sql';

const ACTION = 'view_aggregate_analytics';
const KIND = 'institutional_auditor';

// The curated allowlist: live-verified to return zero individual PII and perform zero writes.
const SAFE_RPCS = [
  'get_cycle_report', 'get_annual_kpis', 'get_selection_pipeline_metrics', 'get_diversity_dashboard',
  'get_portfolio_items', 'get_in_dashboard', 'get_comms_to_adoption_funnel', 'exec_role_transitions',
];

// RPCs proven to return individual PII or write — the auditor action must NEVER reach these.
const PII_OR_WRITE_RPCS = [
  'admin_list_members', 'get_member_detail', 'get_selection_dashboard', 'get_selection_rankings',
  'get_org_chart', 'get_tribe_gamification', 'get_initiative_gamification', 'exec_tribe_dashboard',
  'get_chapter_dashboard', 'get_adoption_dashboard', 'get_campaign_analytics',
  'get_dual_track_merged_payload', 'list_initiative_engagements_by_kind', 'get_member_affiliation_status',
  'admin_list_archived_board_items', 'mark_vep_reconciled', 'capture_vep_baseline',
  'trigger_ai_calibration_run', 'submit_chapter_need', 'record_drive_discovery',
];

function loadMigrations() {
  return readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .map((f) => ({ name: f, body: readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8') }));
}

// Strip SQL line comments so a `-- ... view_aggregate_analytics ...` note never trips a body check.
const stripComments = (sql) => sql.replace(/--[^\n]*/g, '');

// Extract every CREATE OR REPLACE FUNCTION <name> body across all migrations.
function functionBodies(allSql, name) {
  const re = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${name}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi'
  );
  return [...allSql.matchAll(re)].map((m) => m[2]);
}

// Name-capturing sweep: map every CREATE OR REPLACE FUNCTION to its LATEST body across all
// migrations (migrations load sorted by timestamp, so a later redefinition overwrites — latest wins,
// i.e. what is actually live). Used to assert the allowlist as a true superset bound, not a denylist.
function latestFunctionBodies() {
  const re = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(?:public\.)?([a-z_][a-z0-9_]*)\s*\([^)]*\)[\s\S]*?AS\s+\$(\w*)\$([\s\S]*?)\$\2\$/gi;
  const map = new Map();
  for (const { body } of loadMigrations()) {
    for (const m of body.matchAll(re)) map.set(m[1], m[3]);
  }
  return map;
}

test('FU-3 migration is registered at the canonical name', () => {
  const m = loadMigrations().find((x) => x.name === FU3_FILE);
  assert.ok(m, `${FU3_FILE} must exist`);
});

test('FU-3 seeds the kind + the single auditor action correctly', () => {
  const body = loadMigrations().find((x) => x.name === FU3_FILE).body;
  // kind row
  assert.match(body, /INSERT\s+INTO\s+public\.engagement_kinds[\s\S]*?'institutional_auditor'/i,
    'must INSERT the institutional_auditor kind');
  // institutional read-only family: legitimate_interest + requires_agreement=false (so it satisfies
  // the catalog invariant that a requires_agreement kind must name an agreement_template — p235/#323).
  assert.match(body, /'institutional_auditor',\s*'Auditor Institucional'[\s\S]*?'legitimate_interest',\s*false/i,
    "kind must be legal_basis='legitimate_interest' + requires_agreement=false");
  // exactly the one read action, scoped to the auditor
  assert.match(body, /INSERT\s+INTO\s+public\.engagement_kind_permissions[\s\S]*?\('institutional_auditor',\s*'auditor',\s*'view_aggregate_analytics',\s*'organization'\)/i,
    'must seed institutional_auditor/auditor/view_aggregate_analytics@organization');
  // end_date CHECK
  assert.match(body, /engagements_institutional_auditor_end_date_check[\s\S]*?kind\s*<>\s*'institutional_auditor'\s+OR\s+end_date\s+IS\s+NOT\s+NULL/i,
    'must add the end_date NOT NULL CHECK for the kind');
  // RLS carve-out — keeps the literal `<> 'guest'` guard (rls-members-directory-authoritative.test)
  // AND adds the auditor exclusion (so the auditor never gets the baseline member-directory PII).
  assert.match(body, /operational_role\s*<>\s*'guest'\s+AND\s+m\.operational_role\s*<>\s*'institutional_auditor'/i,
    'rls_is_authoritative_member must keep <> guest AND also exclude institutional_auditor');
  // ADR reference
  assert.match(body, /ADR-0111/i, 'header must reference ADR-0111');
});

test('FU-3 wires view_aggregate_analytics into EXACTLY the 8 curated safe RPCs', () => {
  const body = stripComments(loadMigrations().find((x) => x.name === FU3_FILE).body);
  for (const fn of SAFE_RPCS) {
    const bodies = functionBodies(body, fn);
    assert.ok(bodies.length >= 1, `${fn} CREATE OR REPLACE must be in the FU-3 migration`);
    assert.ok(bodies[bodies.length - 1].includes(ACTION),
      `${fn} gate must honor ${ACTION}`);
  }
});

test('forward-defense: view_aggregate_analytics reaches ONLY the curated allowlist (true bound, no drift)', () => {
  // Denylist (PII_OR_WRITE_RPCS) catches the KNOWN-bad surface; this asserts the COMPLEMENT —
  // that no function OUTSIDE the curated 8 ever carries the action, even one not on the denylist.
  // Converts the check from denylist into genuine allowlist-by-construction: any future migration
  // wiring a 9th RPC into the action fails here. (Security review #952 FU-4.)
  const carriers = [...latestFunctionBodies().entries()]
    .filter(([, body]) => stripComments(body).includes(ACTION))
    .map(([name]) => name)
    .sort();
  assert.deepEqual(carriers, [...SAFE_RPCS].sort(),
    `${ACTION} must reach EXACTLY the curated allowlist — found carriers: ${carriers.join(', ') || '(none)'}`);
});

test('forward-defense: NO PII/write RPC ever gains the auditor action (any migration)', () => {
  const all = stripComments(loadMigrations().map((m) => m.body).join('\n'));
  for (const fn of PII_OR_WRITE_RPCS) {
    for (const fnBody of functionBodies(all, fn)) {
      assert.ok(!fnBody.includes(ACTION),
        `${fn} returns PII or writes — it must NEVER reference ${ACTION} (ADR-0111 allowlist breach)`);
    }
  }
});

test('forward-defense: view_aggregate_analytics is ONLY ever seeded to institutional_auditor', () => {
  const all = loadMigrations().map((m) => m.body).join('\n');
  // Every engagement_kind_permissions seed tuple that mentions the action must also be the auditor.
  const tupleRe = /\(\s*'([a-z_]+)'\s*,\s*'([a-z_]+)'\s*,\s*'view_aggregate_analytics'\s*,\s*'[a-z]+'\s*\)/gi;
  const seeds = [...all.matchAll(tupleRe)];
  assert.ok(seeds.length >= 1, 'the action must be seeded at least once');
  for (const s of seeds) {
    assert.equal(s[1], KIND, `${ACTION} seeded to kind='${s[1]}' — must be institutional_auditor only`);
    assert.equal(s[2], 'auditor', `${ACTION} seeded to role='${s[2]}' — must be auditor only`);
  }
});
