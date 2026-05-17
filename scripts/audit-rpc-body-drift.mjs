#!/usr/bin/env node
/**
 * RPC body drift inventory (p174 audit playbook, refactored p175).
 *
 * Compares live `pg_proc.prosrc` normalized body hash against the latest
 * CREATE [OR REPLACE] FUNCTION body in supabase/migrations/*.sql.
 *
 * Parser logic lives in tests/helpers/rpc-body-drift-parser.mjs (shared
 * with the Phase C contract test). This script wraps the helper with
 * file-IO + report printing for one-shot manual audits.
 *
 * Two input modes:
 *   A. LIVE_INVENTORY file (legacy p174 playbook). Set env LIVE_INVENTORY to
 *      a JSON file produced by MCP execute_sql with `<untrusted-data>` wrapper.
 *      Each row needs proname / args / body_md5 / prosrc_len / prosecdef.
 *   B. SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (p175+). Fetches live state
 *      directly via `_audit_list_public_function_bodies()` RPC.
 *
 * If both are set, env-fetch wins. Output written to REPORT_OUT
 * (default /tmp/drift-audit/drift-report.json).
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { loadLatestCaptures, diffLiveVsCaptures } from '../tests/helpers/rpc-body-drift-parser.mjs';

const ROOT = process.cwd();
const MIGRATIONS_DIR = join(ROOT, 'supabase/migrations');
const LIVE_INVENTORY = process.env.LIVE_INVENTORY;
const REPORT_OUT = process.env.REPORT_OUT || '/tmp/drift-audit/drift-report.json';
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

async function fetchLiveViaRpc() {
  const url = `${SUPABASE_URL}/rest/v1/rpc/_audit_list_public_function_bodies`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({}),
  });
  if (!res.ok) {
    throw new Error(`bodies RPC failed: ${res.status} ${await res.text()}`);
  }
  return res.json();
}

function loadLiveFromFile() {
  const raw = readFileSync(LIVE_INVENTORY, 'utf8');
  const outer = JSON.parse(raw);
  const resultStr = outer.result;
  const m = resultStr.match(/<untrusted-data-[^>]+>\n([\s\S]+?)\n<\/untrusted-data-[^>]+>/);
  if (!m) throw new Error('Cannot find untrusted-data wrapper in result string');
  const inner = JSON.parse(m[1].trim());
  // Legacy file format had inventory_json key; pass through transparently.
  const rows = inner[0].inventory_json || inner;
  // Normalize legacy field names to match RPC output.
  return rows.map(r => ({
    proname: r.proname,
    identity_args: r.args || r.identity_args || '',
    body_md5: r.body_md5,
    prosrc_len: r.prosrc_len,
    is_secdef: r.prosecdef ?? r.is_secdef,
  }));
}

async function main() {
  let liveRows;
  if (SUPABASE_URL && SERVICE_ROLE_KEY) {
    console.log('Fetching live inventory via _audit_list_public_function_bodies RPC...');
    liveRows = await fetchLiveViaRpc();
  } else if (LIVE_INVENTORY) {
    console.log(`Loading live inventory from ${LIVE_INVENTORY}`);
    liveRows = loadLiveFromFile();
  } else {
    console.error('Set either SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (preferred) ' +
      'or LIVE_INVENTORY (legacy p174 playbook)');
    process.exit(1);
  }
  console.log(`Live inventory: ${liveRows.length} functions`);

  const captures = loadLatestCaptures(MIGRATIONS_DIR);
  console.log(`Migration files: ${captures.fileCount}`);
  console.log(`Unique captured keys: ${captures.latest.size}`);

  const diff = diffLiveVsCaptures(liveRows, captures);

  console.log('\n========== DRIFT REPORT ==========\n');
  console.log(`Live functions: ${liveRows.length}`);
  console.log(`Clean (live==latest migration body): ${diff.clean}`);
  console.log(`Drifted DEFINITE (live_len != mig_len): ${diff.driftedDefinite.length}`);
  console.log(`Drifted SUSPECT (same len, hash differs): ${diff.driftedSuspect.length}`);
  console.log(`Orphans TRUE (no migration capture of name at all): ${diff.orphansTrue.length}`);
  console.log(`Orphans OVERLOAD (name captured but args mismatch): ${diff.orphansOverload.length}`);
  console.log(`Extinct (captured but not live): ${diff.extinct.length}`);

  const drifted = [...diff.driftedDefinite, ...diff.driftedSuspect];

  const touchBuckets = new Map();
  for (const d of drifted) {
    const b = d.touch_count;
    if (!touchBuckets.has(b)) touchBuckets.set(b, []);
    touchBuckets.get(b).push(d);
  }

  console.log('\n========== DRIFT BY TOUCH-COUNT BUCKET ==========\n');
  for (const b of [...touchBuckets.keys()].sort((a, b) => b - a)) {
    console.log(`  ${b} migrations: ${touchBuckets.get(b).length} drifted`);
  }

  console.log('\n========== DRIFTED FUNCTIONS ==========\n');
  drifted.sort((a, b) => b.touch_count - a.touch_count);
  for (const d of drifted) {
    console.log(`  [${d.touch_count}x] ${d.name}(${d.args})`);
    console.log(`         live=${d.live_md5}  mig=${d.migration_md5}`);
    console.log(`         live_len=${d.live_len}  mig_len=${d.migration_len}  latest=${d.latest_file}`);
  }

  if (diff.orphansTrue.length > 0) {
    console.log('\n========== ORPHANS TRUE (no capture of ANY signature) ==========\n');
    for (const o of diff.orphansTrue) {
      console.log(`  ${o.name}(${o.args}) [secdef=${o.is_secdef}]`);
    }
  }
  if (diff.orphansOverload.length > 0) {
    console.log('\n========== ORPHANS OVERLOAD (name captured, args differ) ==========\n');
    for (const o of diff.orphansOverload) {
      console.log(`  ${o.name}(${o.args}) [secdef=${o.is_secdef}]`);
    }
  }

  mkdirSync(dirname(REPORT_OUT), { recursive: true });
  writeFileSync(REPORT_OUT, JSON.stringify({
    live_count: liveRows.length,
    clean_count: diff.clean,
    drifted_definite_count: diff.driftedDefinite.length,
    drifted_suspect_count: diff.driftedSuspect.length,
    orphan_true_count: diff.orphansTrue.length,
    orphan_overload_count: diff.orphansOverload.length,
    extinct_count: diff.extinct.length,
    drifted_definite: diff.driftedDefinite,
    drifted_suspect: diff.driftedSuspect,
    orphans_true: diff.orphansTrue,
    orphans_overload: diff.orphansOverload,
    extinct: diff.extinct.slice(0, 50),
  }, null, 2));
  console.log(`\nReport saved to ${REPORT_OUT}`);
}

await main();
