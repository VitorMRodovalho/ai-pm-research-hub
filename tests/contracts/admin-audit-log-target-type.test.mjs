/**
 * admin_audit_log target_type contract
 *
 * Forward-defense for the p179 latent bug pattern: passing NULL explicit
 * for `admin_audit_log.target_type` overrides the column's NOT NULL DEFAULT
 * 'member' and triggers a 23502 NOT NULL violation at INSERT time.
 *
 * Origin (p179 → fixed p180):
 *   - migration `20260687000000_p179_arm9_detect_inactive_members_v4_auth.sql`
 *     introduced `detect_inactive_members` with `INSERT INTO admin_audit_log
 *     (..., target_type, ...) VALUES (..., NULL, ...)`. The fn ran only with
 *     `p_dry_run=true` (which skips the INSERT block), so the bug was latent
 *     until p180 council mid-sweep caught it 6 days before first scheduled
 *     non-dry-run execution.
 *   - migration `20260690000000_p180_fix_detect_inactive_members_target_type.sql`
 *     surgical 1-line fix: NULL → 'system_event' explicit.
 *
 * Convention established p180 (Sediment p180/p182):
 *   - `'member'`        — member lifecycle events (DEFAULT)
 *   - `'system_event'`  — cron/no-target / service-role contexts
 *   - `'event'`         — event-target operations
 *   - `'document'`      — document-target operations
 *   - others as needed (per domain)
 *
 * What this test does:
 *   1. Scan ALL migration files for `INSERT INTO ... admin_audit_log` blocks.
 *   2. For each block, parse the column list and VALUES list.
 *   3. If `target_type` appears in the column list AND the corresponding
 *      VALUES position is explicit `NULL`, flag as violation.
 *
 * What this test does NOT do:
 *   - Track function-body supersession (rpcLatest pattern). If you
 *     CREATE OR REPLACE a function and the new body fixes the INSERT, both
 *     the old buggy body AND the fixed body live in the migrations dir. To
 *     avoid double-flagging the historical buggy version, files that have
 *     been explicitly superseded are tracked in `KNOWN_SUPERSEDED_VIOLATIONS`
 *     below.
 *   - Validate INSERTs at runtime — that's the integration test layer.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const MIGRATIONS_DIR = resolve(process.cwd(), 'supabase/migrations');

// Migrations whose admin_audit_log INSERT with NULL target_type has been
// explicitly superseded by a later migration. The buggy body remains in the
// historical file but is dead code at runtime (overridden via CREATE OR
// REPLACE FUNCTION). Add a row per (file, fn_name, superseded_by) when a
// fix migration lands.
const KNOWN_SUPERSEDED_VIOLATIONS = new Set([
  // detect_inactive_members chain — all 3 historical bodies passed explicit NULL
  // for target_type. Superseded by p180 fix migration 20260690000000 which set
  // target_type='system_event' explicit. Live function body (verified via
  // pg_get_functiondef p185) carries the fix.
  '20260516870000_arm9_features_g4_inactivity_detection_cron.sql::detect_inactive_members',
  '20260684000000_p178_phase_b_drift_capture_1_touch_a_g_69fns.sql::detect_inactive_members',
  '20260687000000_p179_adr_0011_governance_admin_notification_v4.sql::detect_inactive_members',
]);

function splitArgs(s) {
  // Split a comma-separated VALUES/column list while respecting nested
  // parentheses and string literals. Postgres uses '...' for strings and
  // double-quoted identifiers for case-sensitive names.
  const out = [];
  let depth = 0;
  let inString = false;
  let stringChar = '';
  let buf = '';
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (inString) {
      buf += c;
      if (c === stringChar && s[i - 1] !== '\\') inString = false;
      continue;
    }
    if (c === "'" || c === '"') { inString = true; stringChar = c; buf += c; continue; }
    if (c === '(') { depth++; buf += c; continue; }
    if (c === ')') { depth--; buf += c; continue; }
    if (c === ',' && depth === 0) { out.push(buf.trim()); buf = ''; continue; }
    buf += c;
  }
  if (buf.trim()) out.push(buf.trim());
  return out;
}

function findFunctionAroundOffset(sql, offset) {
  // Walk backwards from `offset` to find the nearest CREATE [OR REPLACE]
  // FUNCTION header. Returns the function name (e.g., "public.foo" or
  // "foo") or null if INSERT is outside a function body (raw DML).
  const head = sql.slice(0, offset);
  const m = /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+([a-z_.]+)/gi;
  let lastMatch = null;
  let mm;
  while ((mm = m.exec(head)) !== null) lastMatch = mm[1];
  return lastMatch;
}

test('admin_audit_log INSERT must not pass explicit NULL for target_type', () => {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();

  const violations = [];
  const insertRegex = /INSERT\s+INTO\s+(?:public\.)?admin_audit_log\s*\(([^)]+)\)\s*VALUES\s*\(((?:[^()]|\([^)]*\))+)\)/gi;

  for (const f of files) {
    const sql = readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8');
    let match;
    while ((match = insertRegex.exec(sql)) !== null) {
      const cols = splitArgs(match[1]).map(c => c.replace(/^"|"$/g, '').toLowerCase());
      const vals = splitArgs(match[2]);

      const ttIdx = cols.findIndex(c => c === 'target_type');
      if (ttIdx < 0) continue;  // column not present — uses DEFAULT 'member', safe

      const ttVal = vals[ttIdx];
      if (!ttVal) continue;  // misaligned column/value counts — skip (likely SELECT-based insert, not VALUES literal)
      if (!/^NULL$/i.test(ttVal.trim())) continue;  // not literal NULL, safe

      const fnName = findFunctionAroundOffset(sql, match.index);
      const key = `${f}::${fnName ? fnName.replace(/^public\./, '') : '__raw_dml__'}`;
      if (KNOWN_SUPERSEDED_VIOLATIONS.has(key)) continue;

      violations.push(`${f} :: ${fnName || 'raw DML'} — col[${ttIdx}]=target_type VALUES position is NULL`);
    }
  }

  if (violations.length > 0) {
    const msg = [
      'admin_audit_log INSERT contract violation: target_type column is NOT NULL DEFAULT \'member\'.',
      'Explicit NULL overrides DEFAULT and causes 23502 at INSERT time.',
      'Use one of: \'member\' (default), \'system_event\' (cron/no-target), \'event\', \'document\', etc.',
      '',
      'Violations:',
      ...violations.map(v => `  - ${v}`),
      '',
      'If a violation is in a function body that was later superseded by a fix migration,',
      'add `<filename>::<fn_name>` to KNOWN_SUPERSEDED_VIOLATIONS in this test file.',
    ].join('\n');
    assert.fail(msg);
  }
});
