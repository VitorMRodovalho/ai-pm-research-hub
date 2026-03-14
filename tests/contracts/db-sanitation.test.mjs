/**
 * W132 Contract Tests: Database Audit & Sanitation
 * Static analysis — validates migration, schema cleanup, data enrichment.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();

function readFile(relPath) {
  return readFileSync(resolve(ROOT, relPath), 'utf8');
}

// ═══════════════════════════════════════════════════
// Migration
// ═══════════════════════════════════════════════════

test('W132 migration exists', () => {
  assert.ok(
    existsSync(resolve(ROOT, 'supabase/migrations/20260319100035_w132_db_sanitation.sql')),
    'W132 migration must exist'
  );
});

test('W132 creates z_archive schema', () => {
  const sql = readFile('supabase/migrations/20260319100035_w132_db_sanitation.sql');
  assert.ok(sql.includes('CREATE SCHEMA IF NOT EXISTS z_archive'), 'Must create z_archive schema');
});

// ═══════════════════════════════════════════════════
// Table archival
// ═══════════════════════════════════════════════════

test('W132 archives ingestion tables (10)', () => {
  const sql = readFile('supabase/migrations/20260319100035_w132_db_sanitation.sql');
  const ingestionTables = [
    'ingestion_alert_events', 'ingestion_alert_remediation_rules',
    'ingestion_alert_remediation_runs', 'ingestion_alerts',
    'ingestion_apply_locks', 'ingestion_batch_files',
    'ingestion_batches', 'ingestion_provenance_signatures',
    'ingestion_rollback_plans', 'ingestion_run_ledger',
  ];
  for (const t of ingestionTables) {
    assert.ok(sql.includes(t), `Must archive ${t}`);
  }
});

test('W132 archives rollback/readiness tables (4)', () => {
  const sql = readFile('supabase/migrations/20260319100035_w132_db_sanitation.sql');
  const tables = ['rollback_audit_events', 'readiness_slo_alerts', 'release_readiness_history', 'governance_bundle_snapshots'];
  for (const t of tables) {
    assert.ok(sql.includes(t), `Must archive ${t}`);
  }
});

test('W132 archives legacy/import tables (3)', () => {
  const sql = readFile('supabase/migrations/20260319100035_w132_db_sanitation.sql');
  const tables = ['legacy_member_links', 'legacy_tribe_board_links', 'notion_import_staging'];
  for (const t of tables) {
    assert.ok(sql.includes(t), `Must archive ${t}`);
  }
});

test('W132 archives misc unused tables (5)', () => {
  const sql = readFile('supabase/migrations/20260319100035_w132_db_sanitation.sql');
  const tables = ['publication_submission_events', 'presentations', 'member_chapter_affiliations', 'comms_token_alerts', 'portfolio_data_sanity_runs'];
  for (const t of tables) {
    assert.ok(sql.includes(t), `Must archive ${t}`);
  }
});

test('W132 uses SET SCHEMA (reversible, not DROP)', () => {
  const sql = readFile('supabase/migrations/20260319100035_w132_db_sanitation.sql');
  assert.ok(!sql.includes('DROP TABLE'), 'Must NOT drop tables (use SET SCHEMA instead)');
  const setSchemaCount = (sql.match(/SET SCHEMA z_archive/g) || []).length;
  assert.ok(setSchemaCount >= 22, `Must have at least 22 SET SCHEMA statements, found ${setSchemaCount}`);
});

// ═══════════════════════════════════════════════════
// Assignee bulk-fix
// ═══════════════════════════════════════════════════

test('W132 bulk-assigns tribe_leaders to unassigned items', () => {
  const sql = readFile('supabase/migrations/20260319100035_w132_db_sanitation.sql');
  assert.ok(sql.includes('assignee_id IS NULL'), 'Must target items with no assignee');
  assert.ok(sql.includes("operational_role = 'tribe_leader'"), 'Must assign tribe_leader');
  assert.ok(sql.includes('is_active = true'), 'Must only assign to active tribe leaders');
});

// ═══════════════════════════════════════════════════
// Reference docs (extraction docs committed to repo)
// ═══════════════════════════════════════════════════

test('Miro extraction doc exists', () => {
  assert.ok(
    existsSync(resolve(ROOT, 'docs/MIRO_DRIVE_EXTRACTION_CICLO2.md')),
    'Miro extraction doc must be committed'
  );
});

test('Comms friction analysis doc exists', () => {
  assert.ok(
    existsSync(resolve(ROOT, 'docs/COMMS_TEAM_FRICTION_ANALYSIS.md')),
    'Comms friction analysis must be committed'
  );
});

test('DB audit plan doc exists', () => {
  assert.ok(
    existsSync(resolve(ROOT, 'docs/DB_AUDIT_AND_SANITATION_PLAN.md')),
    'DB audit plan must be committed'
  );
});

// ═══════════════════════════════════════════════════
// Data quality — existing contract test coverage
// ═══════════════════════════════════════════════════

test('W131 campaign engine tables are NOT archived (active features)', () => {
  const sql = readFile('supabase/migrations/20260319100035_w132_db_sanitation.sql');
  assert.ok(!sql.includes('campaign_templates'), 'Must NOT archive campaign_templates');
  assert.ok(!sql.includes('campaign_sends'), 'Must NOT archive campaign_sends');
  assert.ok(!sql.includes('campaign_recipients'), 'Must NOT archive campaign_recipients');
  assert.ok(!sql.includes('blog_posts'), 'Must NOT archive blog_posts');
});

test('W130 tables are NOT archived (active features)', () => {
  const sql = readFile('supabase/migrations/20260319100035_w132_db_sanitation.sql');
  assert.ok(!sql.includes('help_journeys'), 'Must NOT archive help_journeys');
  assert.ok(!sql.includes('visitor_leads'), 'Must NOT archive visitor_leads');
});
