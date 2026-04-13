/**
 * Domain Model V4 — Fase 5 — Engagement Lifecycle Configuration Fixtures
 *
 * Static analysis contract test for Phase 5 migrations (ADR-0008).
 * Validates that:
 *   1. engagement_kinds has lifecycle columns from ADR-0008
 *   2. Per-kind retention and anonymization policies are correctly seeded
 *   3. anonymize_by_engagement_kind() function exists
 *   4. v4_expire_engagements() real expiration function exists
 *   5. v4_notify_expiring_engagements() notification function exists
 *   6. Cron jobs scheduled for expiration and notification
 *   7. MCP cutover: canV4 replaces canWrite/canWriteBoard
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const MCP_INDEX = resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts');

function findMigration(pattern) {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.includes(pattern));
  assert.ok(files.length > 0, `Migration matching "${pattern}" must exist`);
  return readFileSync(resolve(MIGRATIONS_DIR, files[0]), 'utf8');
}

// ═══════════════════════════════════════════════════════════════════════════
// Migration 1/3: engagement_kinds lifecycle enrichment
// ═══════════════════════════════════════════════════════════════════════════

test('Phase 5 Migration 1: engagement_kinds lifecycle enrichment exists', () => {
  const sql = findMigration('v4_phase5_engagement_kinds_lifecycle');
  assert.ok(sql.length > 0);
});

test('Phase 5 M1: adds lifecycle columns from ADR-0008', () => {
  const sql = findMigration('v4_phase5_engagement_kinds_lifecycle');
  const expectedColumns = [
    'requires_vep',
    'requires_selection',
    'max_duration_days',
    'anonymization_policy',
    'renewable',
    'auto_expire_behavior',
    'notify_before_expiry_days',
    'created_by_role',
    'revocable_by_role',
    'initiative_kinds_allowed',
    'metadata_schema',
  ];
  for (const col of expectedColumns) {
    assert.ok(sql.includes(col), `Column "${col}" must be added in migration`);
  }
});

test('Phase 5 M1: expands legal_basis CHECK constraint', () => {
  const sql = findMigration('v4_phase5_engagement_kinds_lifecycle');
  const expectedBases = [
    'contract_volunteer',
    'contract_course',
    'consent',
    'legitimate_interest',
    'chapter_delegation',
  ];
  for (const basis of expectedBases) {
    assert.ok(sql.includes(`'${basis}'`), `Legal basis "${basis}" must be in CHECK constraint`);
  }
});

test('Phase 5 M1: anonymization_policy has correct CHECK values', () => {
  const sql = findMigration('v4_phase5_engagement_kinds_lifecycle');
  assert.ok(sql.includes("'anonymize'"));
  assert.ok(sql.includes("'delete'"));
  assert.ok(sql.includes("'retain_for_legal'"));
});

test('Phase 5 M1: auto_expire_behavior has correct CHECK values', () => {
  const sql = findMigration('v4_phase5_engagement_kinds_lifecycle');
  assert.ok(sql.includes("'suspend'"));
  assert.ok(sql.includes("'offboard'"));
  assert.ok(sql.includes("'notify_only'"));
});

// ── Per-kind configuration ──────────────────────────────────────────────────

const EXPECTED_KINDS = {
  volunteer: { legal_basis: 'contract_volunteer', requires_vep: true, requires_selection: true, renewable: true, auto_expire: 'suspend' },
  study_group_owner: { legal_basis: 'contract_volunteer', requires_vep: true, renewable: true, auto_expire: 'suspend' },
  study_group_participant: { legal_basis: 'contract_course', renewable: false, auto_expire: 'offboard' },
  speaker: { legal_basis: 'consent', anonymization: 'delete', auto_expire: 'offboard' },
  guest: { legal_basis: 'consent', anonymization: 'delete', auto_expire: 'offboard' },
  candidate: { legal_basis: 'consent', auto_expire: 'offboard' },
  observer: { legal_basis: 'consent', auto_expire: 'notify_only' },
  alumni: { legal_basis: 'legitimate_interest', auto_expire: 'notify_only' },
  ambassador: { legal_basis: 'consent', auto_expire: 'notify_only' },
  chapter_board: { legal_basis: 'chapter_delegation', auto_expire: 'notify_only' },
  sponsor: { legal_basis: 'legitimate_interest', auto_expire: 'notify_only' },
  partner_contact: { legal_basis: 'legitimate_interest', anonymization: 'delete' },
};

test('Phase 5 M1: all 12 kinds have UPDATE statements with lifecycle config', () => {
  const sql = findMigration('v4_phase5_engagement_kinds_lifecycle');
  for (const slug of Object.keys(EXPECTED_KINDS)) {
    assert.ok(
      sql.includes(`WHERE slug = '${slug}'`),
      `UPDATE for kind "${slug}" must exist`
    );
  }
});

test('Phase 5 M1: volunteer requires VEP + selection + agreement', () => {
  const sql = findMigration('v4_phase5_engagement_kinds_lifecycle');
  // Find the volunteer UPDATE block
  const volStart = sql.indexOf("WHERE slug = 'volunteer'");
  const volBlock = sql.substring(Math.max(0, volStart - 600), volStart + 30);
  assert.ok(volBlock.includes('requires_vep = true'), 'volunteer must require VEP');
  assert.ok(volBlock.includes('requires_selection = true'), 'volunteer must require selection');
  assert.ok(volBlock.includes('requires_agreement = true'), 'volunteer must require agreement');
  assert.ok(volBlock.includes("renewable = true"), 'volunteer must be renewable');
  assert.ok(volBlock.includes("auto_expire_behavior = 'suspend'"), 'volunteer auto_expire must be suspend');
});

test('Phase 5 M1: speaker and guest use delete policy with short retention', () => {
  const sql = findMigration('v4_phase5_engagement_kinds_lifecycle');
  for (const kind of ['speaker', 'guest']) {
    const start = sql.indexOf(`WHERE slug = '${kind}'`);
    const block = sql.substring(Math.max(0, start - 600), start + 30);
    assert.ok(block.includes("anonymization_policy = 'delete'"), `${kind} must use delete policy`);
    assert.ok(block.includes('retention_days_after_end = 30'), `${kind} must have 30-day retention`);
  }
});

test('Phase 5 M1: study_group_participant has 2yr retention', () => {
  const sql = findMigration('v4_phase5_engagement_kinds_lifecycle');
  const start = sql.indexOf("WHERE slug = 'study_group_participant'");
  const block = sql.substring(Math.max(0, start - 600), start + 40);
  assert.ok(block.includes('retention_days_after_end = 730'), 'study_group_participant must have 730-day (2yr) retention');
});

test('Phase 5 M1: chapter_board uses chapter_delegation legal basis', () => {
  const sql = findMigration('v4_phase5_engagement_kinds_lifecycle');
  const start = sql.indexOf("WHERE slug = 'chapter_board'");
  const block = sql.substring(Math.max(0, start - 600), start + 30);
  assert.ok(block.includes("legal_basis = 'chapter_delegation'"), 'chapter_board must use chapter_delegation');
});

// ═══════════════════════════════════════════════════════════════════════════
// Migration 2/3: Kind-aware anonymization
// ═══════════════════════════════════════════════════════════════════════════

test('Phase 5 Migration 2: anonymize_by_engagement_kind function exists', () => {
  const sql = findMigration('v4_phase5_anonymize_by_kind');
  assert.ok(sql.includes('anonymize_by_engagement_kind'));
  assert.ok(sql.includes('p_dry_run boolean'));
  assert.ok(sql.includes('p_limit int'));
});

test('Phase 5 M2: reads retention_days_after_end from engagement_kinds', () => {
  const sql = findMigration('v4_phase5_anonymize_by_kind');
  assert.ok(sql.includes('retention_days_after_end'));
  assert.ok(sql.includes('engagement_kinds'));
});

test('Phase 5 M2: respects anonymization_policy per kind', () => {
  const sql = findMigration('v4_phase5_anonymize_by_kind');
  assert.ok(sql.includes("anonymization_policy = 'retain_for_legal'"), 'Must handle retain_for_legal');
  assert.ok(sql.includes("anonymization_policy = 'anonymize'"), 'Must handle anonymize');
  // delete policy
  assert.ok(sql.includes("'delete'"), 'Must handle delete policy');
});

test('Phase 5 M2: anonymizes both persons and legacy members', () => {
  const sql = findMigration('v4_phase5_anonymize_by_kind');
  assert.ok(sql.includes('UPDATE public.persons SET'), 'Must anonymize persons');
  assert.ok(sql.includes('UPDATE public.members SET'), 'Must anonymize legacy members');
});

test('Phase 5 M2: creates audit trail', () => {
  const sql = findMigration('v4_phase5_anonymize_by_kind');
  assert.ok(sql.includes('admin_audit_log'));
  assert.ok(sql.includes('lgpd_v4_anonymization'));
});

test('Phase 5 M2: scheduled via pg_cron', () => {
  const sql = findMigration('v4_phase5_anonymize_by_kind');
  assert.ok(sql.includes("cron.schedule"));
  assert.ok(sql.includes('v4-anonymize-by-kind-monthly'));
});

test('Phase 5 M2: only processes persons with ALL engagements past retention', () => {
  const sql = findMigration('v4_phase5_anonymize_by_kind');
  assert.ok(sql.includes("e.status IN ('offboarded', 'expired')"), 'Must filter by offboarded/expired');
  assert.ok(sql.includes("NOT EXISTS"), 'Must check no active engagements remain');
});

// ═══════════════════════════════════════════════════════════════════════════
// Migration 3/3: Real expiration + notifications
// ═══════════════════════════════════════════════════════════════════════════

test('Phase 5 Migration 3: v4_expire_engagements function exists', () => {
  const sql = findMigration('v4_phase5_real_expiration');
  assert.ok(sql.includes('v4_expire_engagements()'));
  assert.ok(sql.includes("mode', 'real'"), 'Must run in real mode (not shadow)');
});

test('Phase 5 M3: reads auto_expire_behavior per kind', () => {
  const sql = findMigration('v4_phase5_real_expiration');
  assert.ok(sql.includes('auto_expire_behavior'));
  assert.ok(sql.includes("WHEN 'suspend'"));
  assert.ok(sql.includes("WHEN 'offboard'"));
  assert.ok(sql.includes("WHEN 'notify_only'"));
});

test('Phase 5 M3: suspend sets status to suspended', () => {
  const sql = findMigration('v4_phase5_real_expiration');
  assert.ok(sql.includes("status = 'suspended'"));
});

test('Phase 5 M3: offboard sets status to offboarded', () => {
  const sql = findMigration('v4_phase5_real_expiration');
  assert.ok(sql.includes("status = 'offboarded'"));
});

test('Phase 5 M3: notification function exists', () => {
  const sql = findMigration('v4_phase5_real_expiration');
  assert.ok(sql.includes('v4_notify_expiring_engagements'));
  assert.ok(sql.includes('notify_before_expiry_days'));
});

test('Phase 5 M3: notifications avoid re-notification', () => {
  const sql = findMigration('v4_phase5_real_expiration');
  assert.ok(sql.includes("NOT EXISTS"), 'Must check for existing notifications');
  assert.ok(sql.includes("'engagement_expiring'"), 'Must use engagement_expiring notification type');
  assert.ok(sql.includes("recipient_id"), 'Must use correct column name recipient_id (not member_id)');
});

test('Phase 5 M3: replaces shadow cron with real expiration', () => {
  const sql = findMigration('v4_phase5_real_expiration');
  assert.ok(sql.includes("cron.unschedule('v4_engagement_expiration_shadow')"), 'Must unschedule shadow');
  assert.ok(sql.includes("cron.schedule"), 'Must schedule real expiration');
  assert.ok(sql.includes('v4_engagement_expiration'), 'Must name the real cron');
});

test('Phase 5 M3: notification cron at business hours', () => {
  const sql = findMigration('v4_phase5_real_expiration');
  assert.ok(sql.includes('v4_engagement_expiry_notify'));
  assert.ok(sql.includes('0 8 * * *'), 'Notify cron must run at 08:00 UTC');
});

test('Phase 5 M3: creates audit trail for expirations', () => {
  const sql = findMigration('v4_phase5_real_expiration');
  assert.ok(sql.includes('admin_audit_log'));
  assert.ok(sql.includes('v4_engagement_expiration'));
});

// ═══════════════════════════════════════════════════════════════════════════
// MCP Cutover validation (Fase 4 cutover already applied)
// ═══════════════════════════════════════════════════════════════════════════

test('MCP: canV4 function exists in index.ts', () => {
  const mcp = readFileSync(MCP_INDEX, 'utf8');
  assert.ok(mcp.includes('async function canV4'), 'canV4 must be defined');
  assert.ok(mcp.includes('can_by_member'), 'canV4 must call can_by_member RPC');
  assert.ok(mcp.includes("return data === true"), 'canV4 must return boolean');
});

test('MCP: legacy canWrite/canWriteBoard removed', () => {
  const mcp = readFileSync(MCP_INDEX, 'utf8');
  assert.ok(!mcp.includes('function canWrite('), 'canWrite function must be removed');
  assert.ok(!mcp.includes('function canWriteBoard('), 'canWriteBoard function must be removed');
  assert.ok(!mcp.includes('const WRITE_ROLES'), 'WRITE_ROLES must be removed');
  assert.ok(!mcp.includes('const BOARD_ROLES'), 'BOARD_ROLES must be removed');
});

test('MCP: all write tools use canV4', () => {
  const mcp = readFileSync(MCP_INDEX, 'utf8');
  const writeTools = [
    'create_board_card',
    'update_card_status',
    'create_meeting_notes',
    'register_attendance',
    'register_showcase',
    'send_notification_to_tribe',
    'create_tribe_event',
    'manage_partner',
    'drop_event_instance',
    'update_event_instance',
    'mark_member_excused',
    'bulk_mark_excused',
    'promote_to_leader_track',
  ];
  for (const tool of writeTools) {
    const toolIndex = mcp.indexOf(`"${tool}"`);
    assert.ok(toolIndex > -1, `Tool "${tool}" must exist`);
    // Find the next tool registration after this one to delimit the block
    const nextTool = mcp.indexOf('mcp.tool(', toolIndex + 1);
    const blockEnd = nextTool > -1 ? nextTool : mcp.length;
    const block = mcp.substring(toolIndex, blockEnd);
    assert.ok(block.includes('canV4'), `Tool "${tool}" must use canV4 for authorization`);
  }
});

test('MCP: canV4 is fail-closed', () => {
  const mcp = readFileSync(MCP_INDEX, 'utf8');
  assert.ok(mcp.includes('if (error) return false'), 'canV4 must return false on error (fail-closed)');
});
