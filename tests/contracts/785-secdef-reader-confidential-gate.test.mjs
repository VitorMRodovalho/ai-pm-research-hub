/**
 * #785 recurrence guard — every public SECURITY DEFINER *reader* over an
 * initiative-linked table (boards / board items / events / action items) must
 * apply the confidential visibility gate (rls_can_see_initiative / _board / _item),
 * OR be in the justified allowlist below. A new ungated reader fails CI.
 *
 * Why this exists: the confidential GP×Presidência board leaked to non-engaged
 * members through ~27 ungated SECDEF readers (the 3rd recurrence of the
 * "forgot to enumerate a reader" pattern: PR-3 #838, PR-4 #236/#237, then this).
 * Static name-list tests (785-followup-event-read-gate) only catch the readers
 * they name; this DB-grounded check catches ANY new one, regardless of migration.
 *
 * DB-aware: needs SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY. Skips offline
 * (the offline baseline still runs the static assertions below).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

/**
 * SECDEF readers over initiative-linked tables that intentionally do NOT apply
 * rls_can_see_*, each with the reason. Categories:
 *  - aggregate: returns counts/rollups, not per-board content (Tier 2 — confidential
 *    items contaminate aggregates; tracked as a separate follow-up, NOT this PR).
 *  - self-scoped: filters to the caller's own assignments/membership.
 *  - gp-only: requires manage_platform / superadmin, who may see confidential anyway.
 *  - wrapper: delegates to an already-gated reader.
 *  - system: cron/notification/dev helper, not a user content read.
 */
// NOTE (#932 Part 1 + Part 2, 2026-07-02): the CONTENT/public readers (Part 1: mig 320 —
// exec_cross_initiative_comparison, get_cycle_report, get_public_impact_data) AND the count-only
// board/event aggregates (Part 2: mig 321 — _artia_safe_monthly_metrics, exec_portfolio_board_summary,
// exec_portfolio_health, get_admin_dashboard, get_annual_kpis, get_cycle_evolution, get_kpi_dashboard,
// get_pilot_metrics, get_tags) were REMOVED from this allowlist — they now exclude confidential (they
// contain 'confidential', which _audit_secdef_initiative_reader_gates treats as a gate). Only
// get_portfolio_dashboard / get_portfolio_timeline remain as latent aggregates (they already filter
// is_portfolio_item=true and there are 0 confidential portfolio items), plus the structurally-safe
// (tribe-scoped / GP-only) readers with the reason corrected inline.
const ALLOWLIST = {
  // --- #932 latent remainder: filter is_portfolio_item=true; 0 confidential portfolio items today.
  //     Kept ungated (the is_portfolio_item filter is the current containment); would leak only if a
  //     confidential board item is flagged is_portfolio_item by GP. Hardening tracked on #932. ---
  get_portfolio_dashboard: 'aggregate (latent: filters is_portfolio_item=true; 0 confidential portfolio items)',
  get_portfolio_timeline: 'aggregate (latent: filters is_portfolio_item=true; 0 confidential portfolio items)',
  // --- structurally safe: scoped so the confidential initiative (legacy_tribe_id=NULL) never appears ---
  exec_chapter_dashboard: 'chapter-scoped (member.chapter join) + analytics/own-chapter gate (Part-2: indirect count only)',
  get_chapter_dashboard: 'chapter-scoped (member.chapter join) + analytics/own-chapter gate (Part-2: indirect count only)',
  get_tribe_stats: 'tribe-scoped (legacy_tribe_id filter; confidential has NULL legacy_tribe_id → never matches)',
  get_portfolio_planned_vs_actual: 'tribe-join scoped (JOIN initiatives ON legacy_tribe_id=tribe; confidential NULL → excluded)',
  get_comms_dashboard_metrics: 'can_view_comms_analytics gate + domain_key=communication (confidential board is cross_functional)',
  // --- GP-only in practice (manage_platform, or +view_aggregate_analytics with 0 non-GP holders) ---
  exec_all_tribes_summary: 'manage_platform OR view_chapter_dashboards; tribe-scoped (legacy_tribe_id=NULL invariant → safe)',
  exec_chapter_comparison: 'manage_platform OR view_aggregate_analytics (0 non-GP hold it); confidential curation_approved=0 (latent)',
  exec_cycle_report: 'manage_platform OR view_chapter_dashboards; all reads tribe-scoped via legacy_tribe_id (confidential NULL → safe)',
  exec_tribe_dashboard: 'manage_platform OR view_chapter_dashboards; tribe/initiative-scoped (research_tribe; confidential NULL → safe)',
  platform_activity_summary: 'gp-only (manage_platform gate — sees confidential anyway)',
  detect_operational_alerts: 'system/cron aggregate, manage_platform-gated + tribe-scoped',
  check_code_schema_drift: 'dev helper, no member data',
  // self-scoped to caller
  export_my_data: 'self-scoped (auth.uid own data, LGPD export)',
  get_my_cards: 'self-scoped (caller assignments)',
  get_my_tasks: 'self-scoped (caller assignments)',
  get_weekly_card_digest: 'self-scoped digest',
  get_weekly_member_digest: 'self-scoped digest',
  get_weekly_tribe_digest: 'tribe digest (cron/self)',
  get_weekly_initiative_digest: 'leader/coordinator-OR-manage_member gate (stricter than rls_can_see_initiative)',
  // gp-only / manage_platform (sees confidential anyway)
  get_audit_log: 'manage_platform/superadmin only',
  get_global_research_pipeline: 'manage_platform precondition = GP carve-out of the gate',
  admin_list_curation_drive_grants: 'admin curation drive ops (manage gate)',
  force_grant_curation_drive_access: 'admin curation drive op',
  force_revoke_curation_drive_access: 'admin curation drive op',
  generate_agenda_template: 'template helper (no confidential content surfaced)',
  // wrappers over already-gated readers
  get_board_by_domain: 'delegates to get_board (gated)',
  list_initiative_boards: 'wraps list_project_boards (gated)',
  search_initiative_board_items: 'wraps search_board_items (gated)',
  // notification/trigger functions (no content returned to a caller)
  notify_leader_on_review: 'notification function',
  notify_on_assignment: 'notification function',
};

test('#785 guard: no ungated SECDEF reader over initiative tables outside the allowlist', {
  skip: (!URL || !KEY) ? 'no SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (offline baseline)' : false,
}, async () => {
  const res = await fetch(`${URL}/rest/v1/rpc/_audit_secdef_initiative_reader_gates`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: KEY, Authorization: `Bearer ${KEY}` },
    body: '{}',
  });
  assert.ok(res.ok, `audit RPC must succeed (got ${res.status})`);
  const rows = await res.json();

  const ungated = rows.filter(r =>
    r.reads_initiative_table && !r.is_writer && r.exec_authenticated && !r.references_gate);

  const offenders = [...new Set(ungated.map(r => r.proname))].filter(n => !(n in ALLOWLIST));
  assert.deepEqual(offenders, [],
    `Ungated SECDEF readers over initiative tables (gate them with rls_can_see_* or justify in ALLOWLIST): ${offenders.join(', ')}`);

  // Sanity: the allowlist must not rot — every entry should still exist & still be ungated.
  const stillFlagged = new Set(ungated.map(r => r.proname));
  const staleAllow = Object.keys(ALLOWLIST).filter(n => !stillFlagged.has(n));
  assert.deepEqual(staleAllow, [],
    `ALLOWLIST entries no longer ungated-flagged (remove them): ${staleAllow.join(', ')}`);
});

// --- Static (offline) assertions: the migrations gate the named readers. ---
function migBlock(file, name) {
  const sql = readFileSync(resolve(process.cwd(), file), 'utf8');
  const start = sql.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  if (start === -1) return null;
  const next = sql.indexOf('CREATE OR REPLACE FUNCTION public.', start + 1);
  return sql.slice(start, next === -1 ? undefined : next);
}

const MIG1 = 'supabase/migrations/20260805000274_p785_gate_content_readers_confidential.sql';
const MIG2 = 'supabase/migrations/20260805000275_p785_gate_content_readers_part2.sql';

const GATED_IN_MIG1 = [
  'list_active_boards', 'list_board_items', 'get_board_drive_links', 'get_board_tags',
  'get_card_full_history', 'get_card_timeline', 'get_item_assignments', 'get_item_curation_history',
  'list_card_comments', 'list_card_drive_files', 'get_tribe_housekeeping', 'get_portfolio_items',
  'list_radar_global', 'list_partner_cards', 'list_orphan_card_assignments',
  'list_legacy_board_items_for_tribe', 'list_meeting_action_items', 'get_content_product_reader',
  'get_mirror_target_boards', 'admin_list_archived_board_items',
];
const GATED_IN_MIG2 = [
  'get_board_members', 'list_card_partners', 'list_webinars_v2',
  'get_publication_submission_detail', 'get_curation_queue_state',
];

for (const name of GATED_IN_MIG1) {
  test(`#785 static: ${name} applies a gate in mig 274`, () => {
    const block = migBlock(MIG1, name);
    assert.ok(block, `${name} must be CREATE OR REPLACE'd in migration 274`);
    assert.ok(/rls_can_see_(initiative|board|item)/.test(block),
      `${name} must call rls_can_see_* (confidential gate)`);
  });
}
for (const name of GATED_IN_MIG2) {
  test(`#785 static: ${name} applies a gate in mig 275`, () => {
    const block = migBlock(MIG2, name);
    assert.ok(block, `${name} must be CREATE OR REPLACE'd in migration 275`);
    assert.ok(/rls_can_see_(initiative|board|item)/.test(block),
      `${name} must call rls_can_see_* (confidential gate)`);
  });
}

test('#785 static: rls_can_see_item helper is created in mig 274', () => {
  const sql = readFileSync(resolve(process.cwd(), MIG1), 'utf8');
  assert.ok(/CREATE OR REPLACE FUNCTION public\.rls_can_see_item\(/.test(sql),
    'rls_can_see_item helper must be defined in migration 274');
});

// --- #932 Part 1 (2026-07-02): universal confidential exclusion from content/public/canonical readers.
// Static guard so a future rewrite of these functions cannot silently drop the exclusion. Note
// _artia_safe_event_summary reads only `events` (not board tables), so the DB-aware audit RPC above
// does NOT track it — this static assertion is its only recurrence guard.
const MIG932 = 'supabase/migrations/20260805000320_932_confidential_aggregate_exclusion_part1.sql';

test('#932 static: helpers is_confidential_initiative + is_confidential_board defined in mig 320', () => {
  const sql = readFileSync(resolve(process.cwd(), MIG932), 'utf8');
  assert.ok(/CREATE OR REPLACE FUNCTION public\.is_confidential_initiative\(/.test(sql),
    'is_confidential_initiative helper must be defined');
  assert.ok(/CREATE OR REPLACE FUNCTION public\.is_confidential_board\(/.test(sql),
    'is_confidential_board helper must be defined');
});

test('#932 static: audit RPC references_gate recognizes the confidential-exclusion predicate', () => {
  const sql = readFileSync(resolve(process.cwd(), MIG932), 'utf8');
  const block = migBlock(MIG932, '_audit_secdef_initiative_reader_gates');
  assert.ok(block, '_audit_secdef_initiative_reader_gates must be re-created in mig 320');
  assert.ok(/rls_can_see_\(initiative\|board\|item\)\|confidential/.test(block),
    'references_gate regex must also match the word confidential');
});

const GATED_IN_MIG932 = [
  'get_impact_hours_canonical', 'get_public_platform_stats', 'get_public_impact_data',
  '_artia_safe_event_summary', 'exec_cross_initiative_comparison', 'get_cycle_report',
];
for (const name of GATED_IN_MIG932) {
  test(`#932 static: ${name} excludes confidential in mig 320`, () => {
    const block = migBlock(MIG932, name);
    assert.ok(block, `${name} must be CREATE OR REPLACE'd in migration 320`);
    assert.ok(/confidential/.test(block),
      `${name} must exclude confidential (visibility <> 'confidential' / is_confidential_* / NOT EXISTS ... confidential)`);
  });
}

// --- #932 Part 2 (2026-07-02): count-only board/event aggregates exclude confidential via the
// session-blind helpers (is_confidential_board / is_confidential_initiative). Static guard so a
// future rewrite of these readers cannot silently drop the exclusion.
const MIG932P2 = 'supabase/migrations/20260805000321_932_confidential_aggregate_exclusion_part2.sql';

const GATED_IN_MIG932P2 = [
  '_artia_safe_monthly_metrics', 'exec_portfolio_board_summary', 'exec_portfolio_health',
  'get_admin_dashboard', 'get_annual_kpis', 'get_cycle_evolution', 'get_kpi_dashboard',
  'get_pilot_metrics', 'get_tags',
];
for (const name of GATED_IN_MIG932P2) {
  test(`#932 Part 2 static: ${name} excludes confidential in mig 321`, () => {
    const block = migBlock(MIG932P2, name);
    assert.ok(block, `${name} must be CREATE OR REPLACE'd in migration 321`);
    assert.ok(/is_confidential_(board|initiative)|visibility <> 'confidential'/.test(block),
      `${name} must exclude confidential (is_confidential_board / is_confidential_initiative / visibility <> 'confidential')`);
  });
}
