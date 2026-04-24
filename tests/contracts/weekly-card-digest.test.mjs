/**
 * Issue #98 — Weekly Card Digest MVP V1
 *
 * Static contract tests (migration file sanity) — always run.
 * Live DB tests — only with SUPABASE_URL + SERVICE_ROLE_KEY.
 *
 * Covers:
 *   1. Migration file declares cron schedule '0 12 * * 6' for weekly-card-digest-saturday
 *   2. Migration file wires generate_weekly_card_digest_cron() into cron.schedule
 *   3. Migration adds notify_weekly_digest column com DEFAULT true
 *   4. get_weekly_card_digest RPC uses can_by_member (ADR-0011) + raises Unauthorized
 *   5. Live DB: get_weekly_card_digest returns expected jsonb shape (skipped sem env)
 *   6. Live DB: members.notify_weekly_digest column is selectable (skipped sem env)
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const MIGRATION_FILE = resolve(
  process.cwd(),
  'supabase/migrations/20260508020000_weekly_card_digest_member_mvp_issue_98.sql'
);
const migrationSql = readFileSync(MIGRATION_FILE, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

// ===== Static tests (always run) =====

test('Issue #98: migration schedules weekly-card-digest-saturday at 0 12 * * 6', () => {
  assert.ok(
    migrationSql.includes("'weekly-card-digest-saturday'"),
    'Must schedule cron job named weekly-card-digest-saturday'
  );
  assert.ok(
    migrationSql.includes("'0 12 * * 6'"),
    "Schedule must be '0 12 * * 6' (Saturday 12:00 UTC = 09:00 BRT)"
  );
  assert.ok(
    migrationSql.includes('generate_weekly_card_digest_cron()'),
    'Cron command must call generate_weekly_card_digest_cron()'
  );
});

test('Issue #98: migration adds notify_weekly_digest column with DEFAULT true', () => {
  assert.ok(
    /ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+notify_weekly_digest\s+boolean\s+NOT\s+NULL\s+DEFAULT\s+true/i.test(migrationSql),
    'Must add notify_weekly_digest NOT NULL DEFAULT true'
  );
});

test('Issue #98: get_weekly_card_digest uses can_by_member (ADR-0011) and raises Unauthorized for cross-member', () => {
  assert.ok(
    /can_by_member\s*\(\s*v_caller_id\s*,\s*'manage_member'\s*\)/i.test(migrationSql),
    "RPC must check can_by_member(v_caller_id, 'manage_member') for cross-member read"
  );
  assert.ok(
    /RAISE\s+EXCEPTION\s+'Unauthorized/i.test(migrationSql),
    'RPC must raise Unauthorized when cross-member read denied'
  );
});

test('Issue #98: migration creates both RPCs with SECURITY DEFINER + search_path hardening', () => {
  const rpcDefinitions = migrationSql.match(/CREATE OR REPLACE FUNCTION public\.(get_weekly_card_digest|generate_weekly_card_digest_cron)/g);
  assert.ok(rpcDefinitions?.length === 2, 'Must define both RPCs');
  assert.ok(/SECURITY\s+DEFINER/i.test(migrationSql), 'RPCs must be SECURITY DEFINER');
  assert.ok(/SET\s+search_path\s+TO\s+'public'\s*,\s*'pg_temp'/i.test(migrationSql), "search_path must be hardened to 'public', 'pg_temp'");
});

test('Issue #98: cron orchestrator iterates opt-in active members and skips zero-content', () => {
  assert.ok(
    /WHERE\s+is_active\s*=\s*true/i.test(migrationSql),
    'Orchestrator must filter is_active = true'
  );
  assert.ok(
    /notify_weekly_digest/i.test(migrationSql),
    'Orchestrator must respect notify_weekly_digest opt-out'
  );
  assert.ok(
    /no_pending_cards_skip/i.test(migrationSql),
    'Orchestrator must emit reason no_pending_cards_skip when member has no content'
  );
});

// ===== Live DB tests (skip if no env) =====

test('Issue #98: [live] get_weekly_card_digest returns expected jsonb shape', { skip: !canRun && skipMsg }, async () => {
  const membersRes = await fetch(
    `${SUPABASE_URL}/rest/v1/members?select=id&is_active=eq.true&limit=1`,
    { headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` } }
  );
  const members = await membersRes.json();
  assert.ok(members.length > 0, 'Need at least one active member for shape test');

  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/get_weekly_card_digest`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({ p_member_id: members[0].id }),
  });
  assert.equal(res.status, 200, `Expected 200, got ${res.status}`);
  const body = await res.json();
  assert.equal(typeof body, 'object');
  assert.ok('member_id' in body);
  assert.ok('generated_at' in body);
  assert.ok(Array.isArray(body.this_week_pending));
  assert.ok(Array.isArray(body.next_week_due));
  assert.ok(Array.isArray(body.overdue_7plus));
});

test('Issue #98: [live] members.notify_weekly_digest is selectable and boolean-typed', { skip: !canRun && skipMsg }, async () => {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/members?select=notify_weekly_digest&limit=1`,
    { headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` } }
  );
  assert.equal(res.status, 200, 'notify_weekly_digest column must be selectable');
  const rows = await res.json();
  if (rows.length > 0) {
    assert.equal(typeof rows[0].notify_weekly_digest, 'boolean');
  }
});
