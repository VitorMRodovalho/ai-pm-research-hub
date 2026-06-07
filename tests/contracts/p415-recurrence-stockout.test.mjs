/**
 * #415 contract test — recurrence stockout observability.
 *
 * Background: the C3 leadership series ended and nobody noticed #4..#N were never created until the
 * meeting hour — there was no active observability for recurring series running out of future events.
 *
 * Fix (migration 20260805000125): a SECURITY DEFINER helper _recurrence_stockout_rows(horizon) that
 * flags recently-active series (>=2 events, sane cadence, alive within 2 cadences, last_date within
 * horizon), surfaced three ways — get_recurrence_stockout RPC (gated manage_event), a daily cron
 * detect_recurrence_stockout_cron() that notifies manage_platform holders (idempotent), and a fold
 * into the computed detect_operational_alerts dashboard. MCP tool get_recurrence_stockout wraps the RPC.
 *
 * No operational_alerts table is created (none exists); alerts surface via notifications + the computed
 * dashboard, mirroring detect_stale_events_cron.
 *
 * Live-verified at ship: real data → 8 recently-stuck weekly series (dead/well-stocked excluded);
 * synthetic last_date=today+10 flagged, today+90 not; RPC fail-closed; cron run → 8 stockout / 2 admins
 * notified (idempotent); fold appears on the dashboard.
 *
 * (A) static  — migration wiring + MCP tool + matrix (always run).
 * (B) DB-gated — the gated RPC is live + fail-closed (service-role has no auth.uid() → Not authenticated).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000125_p415_recurrence_stockout_observability.sql');
const MCP = resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts');
const MATRIX_JSON = resolve(ROOT, 'docs/reference/mcp-tool-matrix.json');

const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const mcpRaw = existsSync(MCP) ? readFileSync(MCP, 'utf8') : '';

// ── (A) static ──────────────────────────────────────────────────────────────
test('#415 static: migration defines the helper + RPC + cron fn + pg_cron job', () => {
  assert.ok(migRaw, 'migration 20260805000125 present');
  assert.match(migRaw, /FUNCTION public\._recurrence_stockout_rows\(p_horizon_days integer/, 'helper defined');
  assert.match(migRaw, /FUNCTION public\.get_recurrence_stockout\(p_horizon_days integer/, 'consumer RPC defined');
  assert.match(migRaw, /FUNCTION public\.detect_recurrence_stockout_cron\(\)/, 'cron detector defined');
  assert.match(migRaw, /cron\.schedule\('recurrence-stockout-alert',\s*'0 14 \* \* \*'/, 'daily 14:00 pg_cron registered');
});

test('#415 static: stockout predicate is "alive + low buffer" (not the naive last_date<=today+horizon)', () => {
  // the alive clause excludes long-dead historical series (which the naive predicate would flood)
  assert.match(migRaw, /HAVING count\(\*\) >= 2/, 'requires >=2 events (has a cadence)');
  assert.match(migRaw, /modal_gap_days BETWEEN 1 AND 92/, 'sane recurring cadence window');
  assert.match(migRaw, /last_date >= CURRENT_DATE - \(gp\.modal_gap_days \* 2\)/, 'alive: last event within 2 cadences');
  assert.match(migRaw, /last_date <= CURRENT_DATE \+ p_horizon_days/, 'low buffer: within horizon');
});

test('#415 static: RPC gated on manage_event + fold into detect_operational_alerts', () => {
  assert.match(migRaw, /can_by_member\(v_caller_id, 'manage_event'\)/, 'get_recurrence_stockout gated manage_event');
  // the dashboard fold: a recurrence_stockout alert built from the shared helper
  assert.match(migRaw, /'type', 'recurrence_stockout'/, 'detect_operational_alerts emits a recurrence_stockout alert');
  assert.match(migRaw, /FROM public\._recurrence_stockout_rows\(30\) r;/, 'fold reuses the shared helper');
});

test('#415 static: cron detector is least-privilege (PUBLIC revoked) + idempotent notify', () => {
  assert.match(migRaw, /REVOKE EXECUTE ON FUNCTION public\.detect_recurrence_stockout_cron\(\) FROM PUBLIC/, 'cron fn PUBLIC revoked');
  assert.match(migRaw, /n\.type = 'recurrence_stockout'\s*\n\s*AND n\.created_at >= now\(\) - interval '6 days'/, 'idempotent 6-day dedup');
  assert.match(migRaw, /can_by_member\(m\.id, 'manage_platform'\)/, 'notifies manage_platform holders');
});

test('#415 static: MCP get_recurrence_stockout tool wired + gated + in matrix', () => {
  assert.match(mcpRaw, /mcp\.tool\("get_recurrence_stockout"/, 'MCP tool registered');
  assert.match(mcpRaw, /canV4\(sb, member\.id, 'manage_event'\)/, 'MCP tool gated manage_event');
  assert.match(mcpRaw, /sb\.rpc\("get_recurrence_stockout", \{ p_horizon_days/, 'MCP tool calls the RPC with horizon');
  assert.ok(existsSync(MATRIX_JSON), 'matrix json present');
  const matrix = JSON.parse(readFileSync(MATRIX_JSON, 'utf8'));
  const tools = Array.isArray(matrix) ? matrix : (matrix.tools || []);
  assert.ok(tools.some((t) => t.name === 'get_recurrence_stockout'), 'matrix includes get_recurrence_stockout');
});

// ── (B) DB-gated ────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#415 DB: get_recurrence_stockout is live + fail-closed', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // service-role has no auth.uid() → the RPC RAISEs 'Not authenticated' (house pattern; cannot impersonate).
  // A "could not find function" error here would mean the new RPC is NOT deployed — what this guards against.
  const { error } = await sb.rpc('get_recurrence_stockout', { p_horizon_days: 30 });
  assert.ok(error, 'service-role (no auth.uid()) must be rejected, not allowed through');
  assert.match(String(error.message || ''), /Not authenticated|Unauthorized|manage_event/i,
    `must fail closed on the auth gate (got: ${error?.message})`);
});
