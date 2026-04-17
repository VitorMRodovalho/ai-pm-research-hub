/**
 * ADR-0014 — Log retention policy contract (live DB)
 *
 * Calls public.purge_expired_logs(p_dry_run := true) against the live database
 * and asserts the RPC returns one row per covered table with the correct
 * purge_mode. Dry-run is read-only — safe to run in CI repeatedly.
 *
 * This test does NOT verify actual purge writes (cron does that monthly).
 * It verifies:
 *   1. RPC signature exists and returns expected shape
 *   2. All 8 covered tables appear in the output
 *   3. pii_access_log appears twice (anonymize + drop phases)
 *   4. admin_audit_log pair appears (archive live + drop z_archive)
 *   5. purge_mode enum matches spec (drop|archive|anonymize|drop_resolved|error)
 *   6. No section reports mode='error' (all BEGIN/EXCEPTION blocks caught cleanly)
 *
 * Requires: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY. Skipped otherwise.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

const VALID_MODES = new Set(['drop', 'archive', 'anonymize', 'drop_resolved', 'error']);

const EXPECTED_TABLES = [
  'mcp_usage_log',
  'comms_metrics_ingestion_log',
  'knowledge_insights_ingestion_log',
  'data_anomaly_log',
  'email_webhook_events',
  'broadcast_log',
  'pii_access_log',             // appears 2x (anonymize + drop)
  'admin_audit_log',
  'z_archive.admin_audit_log',
];

async function callPurgeDryRun() {
  const url = `${SUPABASE_URL}/rest/v1/rpc/purge_expired_logs`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'apikey': SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({ p_dry_run: true, p_limit: 10000 }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`RPC failed: HTTP ${res.status} — ${text}`);
  }
  return res.json();
}

test('ADR-0014: purge_expired_logs covers all 8 log tables', { skip: !canRun && skipMsg }, async () => {
  const rows = await callPurgeDryRun();

  assert.ok(Array.isArray(rows), 'RPC must return an array');

  const tableNames = rows.map(r => r.table_name);
  const uniqueTables = new Set(tableNames);

  for (const expected of EXPECTED_TABLES) {
    assert.ok(
      uniqueTables.has(expected),
      `Expected table "${expected}" in purge output. Got: ${[...uniqueTables].join(', ')}`
    );
  }

  // pii_access_log gets two rows (anonymize phase + drop phase)
  const piiCount = tableNames.filter(t => t === 'pii_access_log').length;
  assert.strictEqual(piiCount, 2, `pii_access_log must appear 2x (anonymize + drop), got ${piiCount}`);
});

test('ADR-0014: all rows have valid purge_mode and no errors', { skip: !canRun && skipMsg }, async () => {
  const rows = await callPurgeDryRun();

  for (const row of rows) {
    assert.ok(
      VALID_MODES.has(row.purge_mode),
      `Invalid purge_mode "${row.purge_mode}" for ${row.table_name}. Valid: ${[...VALID_MODES].join('|')}`
    );
    assert.notStrictEqual(
      row.purge_mode,
      'error',
      `Section for ${row.table_name} reported error — check pg logs for SQLERRM`
    );
    assert.ok(
      Number.isInteger(row.rows_affected),
      `rows_affected must be integer for ${row.table_name}`
    );
    assert.ok(
      row.rows_affected >= 0,
      `rows_affected must be non-negative for ${row.table_name}`
    );
  }
});

test('ADR-0014: pii_access_log modes are anonymize then drop (order matters)', { skip: !canRun && skipMsg }, async () => {
  const rows = await callPurgeDryRun();
  const piiRows = rows.filter(r => r.table_name === 'pii_access_log');
  assert.strictEqual(piiRows.length, 2, 'pii_access_log must appear twice');
  assert.strictEqual(piiRows[0].purge_mode, 'anonymize', 'first pii_access_log row must be anonymize (5y)');
  assert.strictEqual(piiRows[1].purge_mode, 'drop', 'second pii_access_log row must be drop (6y)');
});

test('ADR-0014: admin_audit_log has archive + z_archive drop pair', { skip: !canRun && skipMsg }, async () => {
  const rows = await callPurgeDryRun();
  const live = rows.find(r => r.table_name === 'admin_audit_log');
  const archive = rows.find(r => r.table_name === 'z_archive.admin_audit_log');
  assert.ok(live, 'admin_audit_log row missing');
  assert.ok(archive, 'z_archive.admin_audit_log row missing');
  assert.strictEqual(live.purge_mode, 'archive', 'live admin_audit_log must use archive mode');
  assert.strictEqual(archive.purge_mode, 'drop', 'z_archive.admin_audit_log must use drop mode');
});

test('ADR-0014: data_anomaly_log uses drop_resolved (keeps unresolved)', { skip: !canRun && skipMsg }, async () => {
  const rows = await callPurgeDryRun();
  const anomaly = rows.find(r => r.table_name === 'data_anomaly_log');
  assert.ok(anomaly, 'data_anomaly_log row missing');
  assert.strictEqual(
    anomaly.purge_mode,
    'drop_resolved',
    'data_anomaly_log must use drop_resolved mode (preserves unresolved anomalies)'
  );
});
