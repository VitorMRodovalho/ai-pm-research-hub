/**
 * Contract: p239b #332 hotfix — accessor_id FK violation in the 2 LGPD
 * retroactive RPCs (lgpd_record_retroactive_notification +
 * lgpd_execute_retroactive_deletion).
 *
 * Bug origin: p238b (migration 20260805000023) shipped both RPCs with
 * `accessor_id := auth.uid()` in the INSERT INTO pii_access_log VALUES
 * clause. The FK `pii_access_log_accessor_id_fkey` targets `members(id)`
 * (NOT `auth.users(id)`), so the INSERT raised "violates foreign key
 * constraint" on the first PM-authenticated invocation.
 *
 * Why it slipped past p238b smoke: smoke ran via service-role context,
 * which returns `auth.uid() = NULL`. The gate ladder's
 * `IF v_caller_member_id IS NULL THEN RAISE` fired BEFORE the INSERT
 * could reach the FK check. The original test asserted the gate +
 * context literal + dual-overload defense but did NOT assert the
 * source of `accessor_id` in the INSERT statement.
 *
 * Discovery: p239b — PM invoked the freshly-shipped MCP wrapper from
 * an authenticated MCP-Claude session for the actual Eduardo Luz
 * dispatch. RPC returned: "insert or update on table 'pii_access_log'
 * violates foreign key constraint 'pii_access_log_accessor_id_fkey'".
 *
 * Fix: migration 20260805000024 CREATE OR REPLACE both RPCs with the
 * only change being `auth.uid()` → `v_caller_member_id` in the INSERT
 * VALUES. Signature + all other body logic preserved byte-for-byte.
 *
 * Convention reference (canonical helpers also follow this):
 *   - `public.log_pii_access` declares `v_accessor_id` via
 *     `SELECT id FROM members WHERE auth_id = auth.uid()` and uses it
 *     in the INSERT.
 *   - `public.log_pii_access_batch` follows same pattern.
 *   - `public.list_initiative_engagements_by_kind` declares
 *     `v_caller_member_id` and uses it in the batch INSERT.
 *
 * This test enforces the convention specifically for the 2 p238b RPCs
 * going forward. The forward-defense rules block any future migration
 * that re-declares either RPC with `auth.uid()` in the INSERT VALUES.
 *
 * Static-only (no DB, no live HTTP). Verifies source-code invariants
 * that survive refactors.
 *
 * Cross-ref:
 *   - GH #332 (issue this PR's MCP tools enable PM to act on)
 *   - Migration: supabase/migrations/20260805000024_p239b_332_hotfix_accessor_id_fk.sql
 *   - Sibling test: tests/contracts/lgpd-art-18-retroactive-deletion.test.mjs (asserts the original p238b migration body — kept unchanged so the historical assertion still anchors what shipped initially)
 *   - Sibling test: tests/contracts/mcp-lgpd-retroactive-operator-tools.test.mjs (asserts the MCP wrapper tools that surfaced the bug)
 *   - SEDIMENT-239b.A: contract tests for SECDEF RPCs that INSERT into FK-constrained tables MUST assert the source of every FK column, not just the gate ladder presence.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const HOTFIX_FILE = resolve(
  MIGRATIONS_DIR,
  '20260805000024_p239b_332_hotfix_accessor_id_fk.sql'
);

// ===================================================================
// STATIC migration body assertions (always run)
// ===================================================================

test('p239b #332 hotfix: migration file exists', () => {
  assert.ok(existsSync(HOTFIX_FILE), `Hotfix migration must exist at ${HOTFIX_FILE}`);
});

test('p239b #332 hotfix: lgpd_record_retroactive_notification CREATE OR REPLACE present with same signature', () => {
  const body = readFileSync(HOTFIX_FILE, 'utf8');
  assert.match(
    body,
    /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.lgpd_record_retroactive_notification\s*\(\s*p_application_id\s+uuid\s*,\s*p_template_version\s+text\s*,\s*p_lang\s+text\s*,\s*p_notification_method\s+text\s+DEFAULT\s+'email'\s*,\s*p_dispatched_at\s+timestamptz\s+DEFAULT\s+NULL\s*\)\s+RETURNS\s+jsonb/i,
    'Hotfix must CREATE OR REPLACE lgpd_record_retroactive_notification with identical signature (5 params, DEFAULTs preserved)'
  );
});

test('p239b #332 hotfix: lgpd_execute_retroactive_deletion CREATE OR REPLACE present with same signature', () => {
  const body = readFileSync(HOTFIX_FILE, 'utf8');
  assert.match(
    body,
    /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.lgpd_execute_retroactive_deletion\s*\(\s*p_application_id\s+uuid\s*,\s*p_video_id\s+uuid\s*,\s*p_deletion_reason\s+text\s*,\s*p_drive_deletion_ref\s+text\s+DEFAULT\s+NULL\s*\)\s+RETURNS\s+jsonb/i,
    'Hotfix must CREATE OR REPLACE lgpd_execute_retroactive_deletion with identical signature (4 params, DEFAULT preserved)'
  );
});

test('p239b #332 hotfix: notification INSERT INTO pii_access_log VALUES starts with v_caller_member_id (NOT auth.uid())', () => {
  const body = readFileSync(HOTFIX_FILE, 'utf8');
  // Match the notification RPC's INSERT block and verify the first column (accessor_id)
  // is sourced from v_caller_member_id, not auth.uid().
  const block = body.split('CREATE OR REPLACE FUNCTION public.lgpd_execute_retroactive_deletion')[0];
  assert.ok(block.includes('lgpd_record_retroactive_notification'), 'notification block must be the first half of the hotfix');
  assert.match(
    block,
    /INSERT\s+INTO\s+public\.pii_access_log\s*\([\s\S]*?accessor_id[\s\S]*?\)\s*VALUES\s*\(\s*v_caller_member_id\b/i,
    'notification INSERT must start VALUES with v_caller_member_id (members.id) to satisfy FK'
  );
});

test('p239b #332 hotfix: deletion INSERT INTO pii_access_log VALUES starts with v_caller_member_id (NOT auth.uid())', () => {
  const body = readFileSync(HOTFIX_FILE, 'utf8');
  const block = body.split('CREATE OR REPLACE FUNCTION public.lgpd_execute_retroactive_deletion')[1];
  assert.ok(block, 'deletion block must exist as second half of the hotfix');
  assert.match(
    block,
    /INSERT\s+INTO\s+public\.pii_access_log\s*\([\s\S]*?accessor_id[\s\S]*?\)\s*VALUES\s*\(\s*v_caller_member_id\b/i,
    'deletion INSERT must start VALUES with v_caller_member_id (members.id) to satisfy FK'
  );
});

test('p239b #332 hotfix: neither RPC body uses auth.uid() inside the INSERT INTO pii_access_log VALUES clause', () => {
  // The bug pattern: `INSERT INTO pii_access_log ... VALUES (auth.uid(), ...)`.
  // The hotfix removes this from both bodies. auth.uid() is still allowed in the
  // gate ladder (`SELECT id FROM members WHERE auth_id = auth.uid()`) — that's
  // legitimate and unchanged.
  const body = readFileSync(HOTFIX_FILE, 'utf8');
  // Look for the bad pattern across both function bodies.
  const offending = body.match(
    /INSERT\s+INTO\s+public\.pii_access_log[\s\S]*?VALUES\s*\(\s*auth\.uid\(\)/gi
  );
  assert.equal(
    offending,
    null,
    `Hotfix must not have any INSERT INTO pii_access_log ... VALUES (auth.uid(), ...) patterns; found: ${JSON.stringify(offending)}`
  );
});

test('p239b #332 hotfix: sanity DO block asserts both RPCs use v_caller_member_id in INSERT', () => {
  const body = readFileSync(HOTFIX_FILE, 'utf8');
  assert.match(body, /DO\s+\$sanity\$/, 'must have sanity DO block tagged $sanity$');
  // Both RPC bodies must be regex-asserted by the sanity block.
  assert.match(
    body,
    /sanity:\s+lgpd_record_retroactive_notification INSERT does not use v_caller_member_id/i,
    'sanity must defend against record RPC regression'
  );
  assert.match(
    body,
    /sanity:\s+lgpd_execute_retroactive_deletion INSERT does not use v_caller_member_id/i,
    'sanity must defend against deletion RPC regression'
  );
  // Single-overload defense preserved
  assert.match(body, /lgpd_record_retroactive_notification has more than one overload/i, 'sanity must preserve dual-overload defense for notification RPC');
  assert.match(body, /lgpd_execute_retroactive_deletion has more than one overload/i, 'sanity must preserve dual-overload defense for deletion RPC');
  // NOTIFY pgrst at end
  assert.match(body, /NOTIFY\s+pgrst\s*,\s*'reload schema'/i, 'must NOTIFY pgrst at end');
});

test('p239b #332 hotfix: COMMENT ON FUNCTION reflects the hotfix provenance for both RPCs', () => {
  const body = readFileSync(HOTFIX_FILE, 'utf8');
  // Both COMMENT statements should mention "p239b hotfix" so anyone querying
  // pg_proc.obj_description sees provenance immediately.
  const commentMatches = body.match(/p239b hotfix/g) || [];
  assert.ok(
    commentMatches.length >= 4,
    `Both COMMENT ON FUNCTION statements + 2 inline body comments should mention p239b hotfix (≥4 total occurrences); found ${commentMatches.length}`
  );
});

// ===================================================================
// FORWARD-DEFENSE: no future migration regresses either RPC to use auth.uid()
// ===================================================================

test('p239b #332 hotfix: no future migration redeclares either RPC with auth.uid() inside INSERT INTO pii_access_log VALUES', () => {
  const all = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort();
  const fixIdx = all.indexOf('20260805000024_p239b_332_hotfix_accessor_id_fk.sql');
  assert.ok(fixIdx >= 0, 'hotfix migration must be in registry');
  const subsequent = all.slice(fixIdx + 1).map((f) => ({
    name: f,
    body: readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8'),
  }));
  for (const rpc of ['lgpd_record_retroactive_notification', 'lgpd_execute_retroactive_deletion']) {
    const declarePattern = new RegExp(
      `CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\.${rpc}\\s*\\(`,
      'i'
    );
    const offenders = subsequent.filter((m) => {
      if (!declarePattern.test(m.body)) return false;
      // Extract just THIS function's CREATE block (from name forward until end of function or next CREATE).
      const fnIdx = m.body.search(declarePattern);
      const nextFnIdx = m.body.indexOf('CREATE OR REPLACE FUNCTION', fnIdx + 1);
      const fnBlock = m.body.slice(fnIdx, nextFnIdx > 0 ? nextFnIdx : undefined);
      // The bad pattern in the body's INSERT block.
      return /INSERT\s+INTO\s+public\.pii_access_log[\s\S]*?VALUES\s*\(\s*auth\.uid\(\)/i.test(fnBlock);
    });
    assert.equal(
      offenders.length,
      0,
      `Future migrations must not redeclare ${rpc} with auth.uid() in the INSERT INTO pii_access_log VALUES — must use v_caller_member_id (members.id). Offenders: ${offenders.map((m) => m.name).join(', ')}`
    );
  }
});
