#!/usr/bin/env node
/**
 * RPC body drift inventory (p174 audit playbook).
 *
 * Compares live `pg_proc.prosrc` normalized body hash against the latest
 * CREATE [OR REPLACE] FUNCTION body in supabase/migrations/*.sql.
 *
 * See docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md § "Repeat audit playbook" for
 * how to generate the LIVE_INVENTORY file (Supabase MCP execute_sql output
 * with `<untrusted-data-X>` wrapper preserved).
 *
 * Methodology (mirrors p52 Phase B):
 *   1. Normalize whitespace via `regexp_replace(prosrc, '\s+', ' ', 'g')`
 *      then md5. DB hashes already computed in LIVE_INVENTORY JSON.
 *   2. For each migration file (chronological by filename), extract every
 *      CREATE [OR REPLACE] FUNCTION block via state machine handling $$
 *      and $tag$ delimiters.
 *   3. For each block: extract name + identity args + body content.
 *      Compute the same md5.
 *   4. Per function (key = name@normalized_args), track latest captured body md5.
 *   5. Diff vs live. Bucket: drifted DEFINITE (length diff) vs SUSPECT,
 *      orphans TRUE vs OVERLOAD, extinct captures.
 *
 * Usage:
 *   LIVE_INVENTORY=/tmp/drift/live.json node scripts/audit-rpc-body-drift.mjs
 *   # outputs full report to stdout + /tmp/drift-audit/drift-report.json
 */
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';

const ROOT = process.cwd();
const MIGRATIONS_DIR = join(ROOT, 'supabase/migrations');
const LIVE_INVENTORY = process.env.LIVE_INVENTORY || '/tmp/drift-audit/live-inventory.json';
const REPORT_OUT = process.env.REPORT_OUT || '/tmp/drift-audit/drift-report.json';

function readLiveInventory() {
  const raw = readFileSync(LIVE_INVENTORY, 'utf8');
  // File is a JSON object: {"result": "...string with \\n and <untrusted-data-X> wrapped JSON..."}
  // Step 1: parse outer JSON to unescape the result field.
  const outer = JSON.parse(raw);
  const resultStr = outer.result;
  // Step 2: extract content between <untrusted-data-X> and </untrusted-data-X>.
  const m = resultStr.match(/<untrusted-data-[^>]+>\n([\s\S]+?)\n<\/untrusted-data-[^>]+>/);
  if (!m) throw new Error('Cannot find untrusted-data wrapper in result string');
  // Step 3: parse the inner JSON array — shape is [{inventory_json: [...]}].
  const inner = JSON.parse(m[1].trim());
  return inner[0].inventory_json;
}

function normalizeBody(s) {
  // Match PG's `regexp_replace(prosrc, '\s+', ' ', 'g')`. NO trim — PG side
  // doesn't trim, so we must not either.
  return s.replace(/\s+/g, ' ');
}

function md5(s) {
  return createHash('md5').update(s).digest('hex');
}

// Normalize PG arg signature for comparison.
// PG identity_args examples: "p_id uuid, p_name text DEFAULT NULL"
// Migration args examples: "p_id uuid, p_name text DEFAULT 'x'"
// We normalize: lowercase, collapse whitespace, strip DEFAULT clauses
// (defaults aren't part of identity but PG strips them in identity_args
// — migration text may still include them, so we drop them on both sides).
function normalizeArgs(s) {
  if (!s) return '';
  let out = s.toLowerCase();
  // Strip DEFAULT clauses up to next comma or close paren
  out = out.replace(/\s+default\s+[^,)]+/g, '');
  // Collapse whitespace
  out = out.replace(/\s+/g, ' ').trim();
  // Strip trailing commas
  out = out.replace(/,$/, '');
  // Strip parameter mode prefixes (in, out, inout, variadic)
  out = out.replace(/\b(in|out|inout|variadic)\s+/g, '');
  return out;
}

function parseMigration(filename, sql) {
  // Find all CREATE [OR REPLACE] FUNCTION blocks.
  // Returns array of { name, args, bodyHash, lineNo }.
  const blocks = [];

  // Regex to find function start anchors. Case-insensitive.
  // Captures: schema-prefix, name, args (until balanced close paren).
  const headerRe = /\bCREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:"?public"?\.)?"?([a-z_][a-z0-9_]*)"?\s*\(/gi;

  let match;
  while ((match = headerRe.exec(sql)) !== null) {
    const name = match[1].toLowerCase();
    const startIdx = match.index;
    const argStart = headerRe.lastIndex; // position right after opening paren

    // Find matching close paren (balance count).
    let depth = 1;
    let i = argStart;
    while (i < sql.length && depth > 0) {
      const c = sql[i];
      if (c === '(') depth++;
      else if (c === ')') depth--;
      i++;
      if (depth === 0) break;
    }
    if (depth !== 0) continue; // unbalanced — skip
    const argEnd = i - 1; // position of close paren
    const args = sql.slice(argStart, argEnd);

    // Now find the body. Look for `AS $delim$ ... $delim$` after argEnd.
    // Skip RETURNS, LANGUAGE, STABLE, IMMUTABLE, SECURITY, SET, etc.
    // Body delimiter is `$$` or `$tag$`.
    const afterArgs = sql.slice(i);
    const asMatch = afterArgs.match(/\bAS\s+(\$[a-zA-Z_]*\$)/);
    if (!asMatch) continue; // No body found — skip

    const delim = asMatch[1];
    const bodyStart = i + asMatch.index + asMatch[0].length;
    // Find matching close delim
    const closeIdx = sql.indexOf(delim, bodyStart);
    if (closeIdx === -1) continue;
    const body = sql.slice(bodyStart, closeIdx);

    const bodyNorm = normalizeBody(body);
    const bodyHash = md5(bodyNorm);

    blocks.push({
      name,
      args: normalizeArgs(args),
      bodyHash,
      bodyLen: body.length,
    });
  }

  return blocks;
}

function main() {
  // 1. Load live inventory
  const live = readLiveInventory();
  console.log(`Live inventory: ${live.length} functions`);

  // Index live by key
  const liveMap = new Map();
  for (const row of live) {
    const key = `${row.proname.toLowerCase()}@${normalizeArgs(row.args)}`;
    if (liveMap.has(key)) {
      console.warn(`Duplicate live key: ${key}`);
    }
    liveMap.set(key, {
      name: row.proname,
      args: row.args,
      body_md5: row.body_md5,
      prosrc_len: row.prosrc_len,
      prosecdef: row.prosecdef,
    });
  }

  // 2. Parse all migrations (chronological by filename)
  const files = readdirSync(MIGRATIONS_DIR)
    .filter(f => f.endsWith('.sql'))
    .sort();
  console.log(`Migration files: ${files.length}`);

  // Track LATEST capture per function key
  const latestCapture = new Map(); // key -> { bodyHash, file, bodyLen }
  const touchCount = new Map();    // key -> integer (how many migrations touch it)

  let totalBlocks = 0;
  for (const f of files) {
    const sql = readFileSync(join(MIGRATIONS_DIR, f), 'utf8');
    const blocks = parseMigration(f, sql);
    totalBlocks += blocks.length;
    for (const b of blocks) {
      const key = `${b.name}@${b.args}`;
      latestCapture.set(key, { bodyHash: b.bodyHash, file: f, bodyLen: b.bodyLen });
      touchCount.set(key, (touchCount.get(key) || 0) + 1);
    }
  }
  console.log(`Total CREATE FUNCTION blocks parsed: ${totalBlocks}`);
  console.log(`Unique function keys captured: ${latestCapture.size}`);

  // Build name-only capture index (any signature of name has a capture)
  const namesWithAnyCapture = new Set();
  for (const key of latestCapture.keys()) {
    namesWithAnyCapture.add(key.split('@')[0]);
  }

  // 3. Diff: live vs latest migration capture
  const drifted_definite = [];   // length diff — almost certainly real drift
  const drifted_suspect = [];    // same length, different hash — possibly parser noise
  const cleanCount = { total: 0 };
  const orphans_strict = [];     // live but no migration capture (name+args)
  const orphans_overload = [];   // captured under different signature but name exists in migrations
  const orphans_true = [];       // no capture of ANY signature of this name
  const extinct = [];            // captured but not in live

  for (const [key, liveRow] of liveMap.entries()) {
    const cap = latestCapture.get(key);
    if (!cap) {
      const name = key.split('@')[0];
      const orphanRow = { key, ...liveRow };
      if (namesWithAnyCapture.has(name)) {
        orphans_overload.push(orphanRow);
      } else {
        orphans_true.push(orphanRow);
      }
      orphans_strict.push(orphanRow);
      continue;
    }
    if (cap.bodyHash !== liveRow.body_md5) {
      const driftRow = {
        key,
        name: liveRow.name,
        args: liveRow.args,
        live_md5: liveRow.body_md5,
        migration_md5: cap.bodyHash,
        live_len: liveRow.prosrc_len,
        migration_len: cap.bodyLen,
        latest_file: cap.file,
        touch_count: touchCount.get(key),
        prosecdef: liveRow.prosecdef,
      };
      if (liveRow.prosrc_len !== cap.bodyLen) {
        drifted_definite.push(driftRow);
      } else {
        drifted_suspect.push(driftRow);
      }
    } else {
      cleanCount.total++;
    }
  }

  for (const [key, cap] of latestCapture.entries()) {
    if (!liveMap.has(key)) {
      extinct.push({ key, ...cap });
    }
  }

  const drifted = [...drifted_definite, ...drifted_suspect];

  // 4. Bucket by touch count
  const touchBuckets = new Map();
  for (const d of drifted) {
    const b = d.touch_count;
    if (!touchBuckets.has(b)) touchBuckets.set(b, []);
    touchBuckets.get(b).push(d);
  }

  // 5. Report
  console.log('\n========== DRIFT REPORT ==========\n');
  console.log(`Live functions: ${liveMap.size}`);
  console.log(`Clean (live==latest migration body): ${cleanCount.total}`);
  console.log(`Drifted DEFINITE (live_len != mig_len): ${drifted_definite.length}`);
  console.log(`Drifted SUSPECT (same len, hash differs): ${drifted_suspect.length}`);
  console.log(`Orphans TRUE (no migration capture of name at all): ${orphans_true.length}`);
  console.log(`Orphans OVERLOAD (name captured but args mismatch): ${orphans_overload.length}`);
  console.log(`Extinct (captured but not live): ${extinct.length}`);

  console.log('\n========== DRIFT BY TOUCH-COUNT BUCKET ==========\n');
  const sortedBuckets = [...touchBuckets.keys()].sort((a, b) => b - a);
  for (const b of sortedBuckets) {
    console.log(`  ${b} migrations: ${touchBuckets.get(b).length} drifted`);
  }

  console.log('\n========== DRIFTED FUNCTIONS ==========\n');
  drifted.sort((a, b) => b.touch_count - a.touch_count);
  for (const d of drifted) {
    console.log(`  [${d.touch_count}x] ${d.name}(${d.args})`);
    console.log(`         live=${d.live_md5}  mig=${d.migration_md5}`);
    console.log(`         live_len=${d.live_len}  mig_len=${d.migration_len}  latest=${d.latest_file}`);
  }

  if (orphans_true.length > 0) {
    console.log('\n========== ORPHANS TRUE (no capture of ANY signature) ==========\n');
    for (const o of orphans_true) {
      console.log(`  ${o.name}(${o.args}) [secdef=${o.prosecdef}]`);
    }
  }

  if (orphans_overload.length > 0) {
    console.log('\n========== ORPHANS OVERLOAD (name captured, args differ) ==========\n');
    for (const o of orphans_overload) {
      console.log(`  ${o.name}(${o.args}) [secdef=${o.prosecdef}]`);
    }
  }

  // 6. Persist results
  writeFileSync(REPORT_OUT, JSON.stringify({
    live_count: liveMap.size,
    clean_count: cleanCount.total,
    drifted_definite_count: drifted_definite.length,
    drifted_suspect_count: drifted_suspect.length,
    orphan_true_count: orphans_true.length,
    orphan_overload_count: orphans_overload.length,
    extinct_count: extinct.length,
    drifted_definite,
    drifted_suspect,
    orphans_true,
    orphans_overload,
    extinct: extinct.slice(0, 50),
  }, null, 2));
  console.log(`\nReport saved to ${REPORT_OUT}`);
}

main();
